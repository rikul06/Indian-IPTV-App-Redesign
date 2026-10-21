import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../model/channel.dart';
import '../services/device.dart';
import '../services/library_store.dart';
import '../services/stream_health.dart';
import '../services/youtube_live.dart';

/// Remote and keyboard keys that toggle play/pause.
final _playPauseKeys = {
  LogicalKeyboardKey.mediaPlayPause,
  LogicalKeyboardKey.mediaPlay,
  LogicalKeyboardKey.mediaPause,
  LogicalKeyboardKey.space,
};

/// Keys that bring the controls back while they are hidden. Up hides them;
/// Left and Right change channel while they are hidden.
final _wakeKeys = {
  LogicalKeyboardKey.select,
  LogicalKeyboardKey.enter,
  LogicalKeyboardKey.arrowDown,
};

/// Remote and keyboard keys for the next and previous channel.
final _channelUpKeys = {
  LogicalKeyboardKey.channelUp,
  LogicalKeyboardKey.pageUp,
};
final _channelDownKeys = {
  LogicalKeyboardKey.channelDown,
  LogicalKeyboardKey.pageDown,
};

/// How much of the screen the picture fills. Smaller looks sharper for
/// low-resolution channels on a big TV.
enum _PictureSize {
  full('Full', 1),
  // Fills the screen, cropping the edges of 4:3 or letterboxed pictures.
  zoom('Zoom', 1),
  large('Large', 0.85),
  medium('Medium', 0.7),
  small('Small', 0.55);

  const _PictureSize(this.label, this.factor);
  final String label;
  final double factor;

  _PictureSize get next => values[(index + 1) % values.length];
}

class Player extends StatefulWidget {
  final Channel channel;
  final LibraryStore library;

  /// The row or grid the channel was opened from; channel up/down moves
  /// through it.
  final List<Channel> channels;

  const Player({
    super.key,
    required this.channel,
    required this.library,
    this.channels = const [],
  });

  @override
  State<Player> createState() => _PlayerState();
}

class _PlayerState extends State<Player> {
  static const _sizeKey = 'picture_size';

  /// Seconds the picture may stay frozen before the stream is reconnected.
  static const _stallLimit = 10;

  /// The last picture size, kept for the next channel.
  static _PictureSize _size = _PictureSize.full;

  VideoPlayerController? videoPlayerController;

  /// Plays the source instead of [videoPlayerController] when it is a
  /// YouTube live stream.
  YoutubeLive? _youtube;
  bool _isLoading = true;
  bool _channelNotFound = false;

  /// Index of the stream variant being played.
  int _streamIndex = 0;

  /// Bumped on every stream switch so late callbacks from an old stream
  /// are ignored.
  int _generation = 0;

  /// Full screen: no app bar, no system bars, landscape on phones.
  /// Always on for TV.
  bool _fullScreen = Device.isTv;

  bool _controlsVisible = true;
  Timer? _hideTimer;
  final FocusNode _screenFocus = FocusNode(debugLabel: 'player');
  final FocusNode _playPauseFocus = FocusNode(debugLabel: 'play/pause');
  final FocusNode _retryFocus = FocusNode(debugLabel: 'try again');
  final FocusNode _nextSourceFocus = FocusNode(debugLabel: 'next source');

  /// Sources that failed while watching this time; the automatic fallback
  /// does not try them again.
  final Set<int> _failedNow = {};

  /// Keeps the video widget alive when it moves between the normal and
  /// full-screen layouts.
  final GlobalKey _videoKey = GlobalKey();

  /// Watches for a frozen picture: live streams often stall after a few
  /// minutes, and reconnecting jumps back to the live point.
  Timer? _watchdog;
  Duration _lastPosition = Duration.zero;
  int _stalledSeconds = 0;
  int _reconnects = 0;
  bool _userPaused = false;

  /// Whether the screen is being kept on, so the wakelock is only switched
  /// when playback starts or stops.
  bool _wakelockOn = false;

  bool get _isPlaying =>
      (videoPlayerController?.value.isPlaying ?? false) ||
      (_youtube?.isPlaying ?? false);
  bool get _isStalled =>
      !_userPaused &&
      ((videoPlayerController?.value.isBuffering ?? false) ||
          _stalledSeconds >= 4);
  bool get _showOverlay => !_isLoading && !_channelNotFound;

  @override
  void initState() {
    super.initState();
    if (_fullScreen) _applySystemUi();
    _loadSize();
    _watchdog =
        Timer.periodic(const Duration(seconds: 2), (_) => _checkStall());
    _play(StreamHealth.firstSource(_urls,
        lastGood: StreamHealth.lastGood(widget.channel.key)));
  }

  List<String> get _urls => [for (final s in widget.channel.streams) s.url];

  Future<void> _loadSize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_sizeKey);
      final size = _PictureSize.values.where((s) => s.name == saved);
      if (size.isNotEmpty && mounted) setState(() => _size = size.first);
    } catch (_) {
      // Keep the current size.
    }
  }

  Future<void> _play(int index, {bool reconnect = false}) async {
    final generation = ++_generation;
    _disposeController();
    if (!reconnect) _reconnects = 0;
    _stalledSeconds = 0;
    _lastPosition = Duration.zero;
    _userPaused = false;
    setState(() {
      _streamIndex = index;
      _isLoading = true;
      _channelNotFound = false;
    });
    // On TV, put the remote on "Next source" while this one connects.
    if (Device.isTv && widget.channel.streams.length > 1) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _nextSourceFocus.requestFocus());
    }

    final stream = widget.channel.streams[index];
    if (stream.isYoutube) {
      _playYoutube(index, generation);
      return;
    }
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(stream.url),
      httpHeaders: stream.headers,
      // Android's own video surface: far lighter than drawing every frame
      // through Flutter, which matters on a TV's small chip.
      viewType: !kIsWeb && defaultTargetPlatform == TargetPlatform.android
          ? VideoViewType.platformView
          : VideoViewType.textureView,
    );
    videoPlayerController = controller;
    controller.addListener(_onControllerChanged);

    try {
      // A server that stops answering would otherwise spin forever.
      await controller.initialize().timeout(const Duration(seconds: 10));
    } catch (_) {
      if (!mounted || generation != _generation) return;
      // Close the failed connection so it stops reporting errors.
      _disposeController();
      _playNextOrFail(index);
      return;
    }
    if (!mounted || generation != _generation) return;

    await controller.play();
    _failedNow.remove(index);
    StreamHealth.markGood(widget.channel.key, stream.url);
    setState(() => _isLoading = false);
    if (!reconnect) _showControls(focusPlayPause: Device.isTv);
  }

  Future<void> _playYoutube(int index, int generation) async {
    final youtube = YoutubeLive()..addListener(_onYoutubeChanged);
    _youtube = youtube;
    final started = await youtube
        .start(widget.channel.streams[index].url)
        .timeout(const Duration(seconds: 20), onTimeout: () => false);
    if (!mounted || generation != _generation) return;
    if (!started) {
      _disposeController();
      _playNextOrFail(index);
      return;
    }
    _failedNow.remove(index);
    StreamHealth.markGood(
        widget.channel.key, widget.channel.streams[index].url);
    setState(() => _isLoading = false);
    _showControls(focusPlayPause: Device.isTv);
  }

  /// The YouTube player started, paused or broke.
  void _onYoutubeChanged() {
    final youtube = _youtube;
    if (youtube == null || !mounted) return;
    if (youtube.failed && !_isLoading && !_channelNotFound) {
      _disposeController();
      _playNextOrFail(_streamIndex);
      return;
    }
    if (_isPlaying != _wakelockOn) {
      _wakelockOn = _isPlaying;
      WakelockPlus.toggle(enable: _wakelockOn);
    }
    setState(() {});
  }

  /// This source is down: try the next one, sources that failed last time
  /// last, and give up only when every source has failed now.
  void _playNextOrFail(int index) {
    _failedNow.add(index);
    StreamHealth.markBad(widget.channel.streams[index].url);
    final next = StreamHealth.nextSource(_urls, index, _failedNow);
    if (next != null) {
      _play(next);
      return;
    }
    setState(() {
      _isLoading = false;
      _channelNotFound = true;
    });
    // Put the remote on "Try again" so the buttons can be reached.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _retryFocus.requestFocus());
  }

  /// "Next source" while connecting: stop waiting on this one.
  void _skipSource() {
    final count = widget.channel.streams.length;
    _play(StreamHealth.nextSource(_urls, _streamIndex, _failedNow) ??
        (_streamIndex + 1) % count);
  }

  /// Starts over with every source, as when the channel was opened.
  void _retry() {
    _failedNow.clear();
    _play(StreamHealth.firstSource(_urls,
        lastGood: StreamHealth.lastGood(widget.channel.key)));
  }

  void _checkStall() {
    final controller = videoPlayerController;
    if (controller == null || !controller.value.isInitialized || _userPaused) {
      _stalledSeconds = 0;
      return;
    }
    final position = controller.value.position;
    if (position != _lastPosition) {
      _lastPosition = position;
      if (_stalledSeconds != 0 || _reconnects != 0) {
        setState(() {
          _stalledSeconds = 0;
          _reconnects = 0;
        });
      }
      return;
    }
    setState(() => _stalledSeconds += 2);
    if (_stalledSeconds >= _stallLimit) _recover();
  }

  /// Reconnects to the live point of the same stream (twice), then moves
  /// on to the channel's next stream.
  void _recover() {
    if (_reconnects < 2) {
      _reconnects++;
      _play(_streamIndex, reconnect: true);
    } else {
      _playNextOrFail(_streamIndex);
    }
  }

  /// Keeps the screen on while the video plays and redraws the
  /// play/pause button when the state changes.
  void _onControllerChanged() {
    final controller = videoPlayerController;
    if (controller == null || !mounted) return;
    if (controller.value.hasError && !_isLoading && !_channelNotFound) {
      // The stream broke: reconnect now rather than waiting for the
      // freeze watchdog.
      _recover();
      return;
    }
    if (_isPlaying != _wakelockOn) {
      _wakelockOn = _isPlaying;
      WakelockPlus.toggle(enable: _wakelockOn);
    }
    setState(() {});
  }

  void _togglePlay() {
    final youtube = _youtube;
    if (youtube != null) {
      _userPaused = youtube.isPlaying;
      _userPaused ? youtube.pause() : youtube.play();
      _showControls();
      return;
    }
    final controller = videoPlayerController;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isPlaying) {
      _userPaused = true;
      controller.pause();
    } else {
      _userPaused = false;
      controller.play();
    }
    _showControls();
  }

  /// Opens the next (+1) or previous (-1) channel of the row or grid this
  /// one was picked from, wrapping around.
  void _switchChannel(int step) {
    final list = widget.channels;
    final index = list.indexWhere((c) => c.key == widget.channel.key);
    if (list.length < 2 || index < 0) return;
    _openChannel(list[(index + step) % list.length]);
  }

  /// Lists the channels of the row or grid to jump to one directly.
  Future<void> _chooseChannel() async {
    _hideTimer?.cancel();
    final list = widget.channels;
    final picked = await showDialog<Channel>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Channels'),
        children: [
          for (final channel in list)
            ListTile(
              autofocus: channel.key == widget.channel.key,
              leading: Icon(channel.key == widget.channel.key
                  ? Icons.play_circle_rounded
                  : Icons.live_tv_rounded),
              title: Text(channel.name),
              subtitle: channel.languages.isEmpty
                  ? null
                  : Text(channel.languages.first),
              onTap: () => Navigator.pop(context, channel),
            ),
        ],
      ),
    );
    if (!mounted) return;
    if (picked != null && picked.key != widget.channel.key) {
      _openChannel(picked);
    } else {
      _showControls(focusPlayPause: Device.isTv);
    }
  }

  /// Replaces this player with one for [channel], keeping the same list.
  void _openChannel(Channel channel) {
    widget.library.markWatched(channel.key);
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        transitionDuration: Duration.zero,
        pageBuilder: (context, _, __) => Player(
            channel: channel,
            library: widget.library,
            channels: widget.channels),
      ),
    );
  }

  /// Lists the channel's sources so the user can pick one; sources that
  /// did not work are marked.
  Future<void> _chooseSource() async {
    _hideTimer?.cancel();
    final streams = widget.channel.streams;
    final picked = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Choose a source'),
        children: [
          for (var i = 0; i < streams.length; i++)
            ListTile(
              autofocus: i == _streamIndex,
              leading: Icon(i == _streamIndex && !_channelNotFound
                  ? Icons.play_circle_rounded
                  : Icons.circle_outlined),
              title: Text('Source ${i + 1} · ${streams[i].label}'),
              subtitle: i == _streamIndex && !_channelNotFound
                  ? Text(_isLoading ? 'Connecting now' : 'Playing now')
                  : _failedNow.contains(i)
                      ? const Text(
                          'Did not work just now · you can still try it')
                      : StreamHealth.isBad(streams[i].url)
                          ? const Text(
                              'Did not work last time · you can still try it')
                          : null,
              onTap: () => Navigator.pop(context, i),
            ),
        ],
      ),
    );
    if (!mounted) return;
    if (picked != null && (picked != _streamIndex || _channelNotFound)) {
      _play(picked);
    } else {
      _showControls(focusPlayPause: Device.isTv);
    }
  }

  Future<void> _nextSize() async {
    setState(() => _size = _size.next);
    _showControls();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_sizeKey, _size.name);
    } catch (_) {
      // Not saved; it still applies until the app closes.
    }
  }

  bool get _onYoutube => widget.channel.streams[_streamIndex].isYoutube;

  /// Opens [stream] (by default the current source) in VLC, or a YouTube
  /// source in the YouTube app.
  Future<void> _openExternal([StreamVariant? stream]) async {
    stream ??= widget.channel.streams[_streamIndex];
    _userPaused = true;
    videoPlayerController?.pause();
    _youtube?.pause();
    final opened = stream.isYoutube
        ? await Device.openUrl(stream.url)
        : await Device.openExternal(stream.url, widget.channel.name);
    if (!opened && mounted) {
      _userPaused = false;
      videoPlayerController?.play();
      _youtube?.play();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(stream.isYoutube
            ? 'YouTube app not found.'
            : 'No video player found. Install VLC from the Play Store.'),
      ));
    }
  }

  void _toggleFullScreen() {
    final wasPlaying = _isPlaying;
    setState(() => _fullScreen = !_fullScreen);
    _applySystemUi();
    _showControls();
    // Some platforms pause the video when its view moves; carry on playing.
    if (wasPlaying) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_isPlaying) videoPlayerController?.play();
      });
    }
  }

  void _applySystemUi() {
    if (_fullScreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      if (!Device.isTv) {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      }
    } else {
      _restoreSystemUi();
    }
  }

  static void _restoreSystemUi() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(const []);
  }

  /// Shows the controls and hides them again after 5 seconds without a
  /// key press or tap, as long as the video plays.
  void _showControls({bool focusPlayPause = false}) {
    _hideTimer?.cancel();
    if (!_controlsVisible) setState(() => _controlsVisible = true);
    if (focusPlayPause) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _playPauseFocus.requestFocus());
    }
    _hideTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted || !_isPlaying) return;
      _hideControls();
    });
  }

  void _hideControls() {
    _hideTimer?.cancel();
    setState(() => _controlsVisible = false);
    _screenFocus.requestFocus();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (_channelUpKeys.contains(key)) {
      _switchChannel(1);
      return KeyEventResult.handled;
    }
    if (_channelDownKeys.contains(key)) {
      _switchChannel(-1);
      return KeyEventResult.handled;
    }
    if (_showOverlay &&
        !_controlsVisible &&
        (key == LogicalKeyboardKey.arrowLeft ||
            key == LogicalKeyboardKey.arrowRight)) {
      _switchChannel(key == LogicalKeyboardKey.arrowRight ? 1 : -1);
      return KeyEventResult.handled;
    }
    if (_channelNotFound && _screenFocus.hasPrimaryFocus) {
      // Nothing is focused on the error screen yet: go to "Try again".
      _retryFocus.requestFocus();
      return KeyEventResult.handled;
    }
    if (_isLoading &&
        _screenFocus.hasPrimaryFocus &&
        widget.channel.streams.length > 1) {
      // Nothing is focused while connecting yet: go to "Next source".
      _nextSourceFocus.requestFocus();
      return KeyEventResult.handled;
    }
    if (_playPauseKeys.contains(event.logicalKey)) {
      _togglePlay();
      return KeyEventResult.handled;
    }
    if (_showOverlay && event.logicalKey == LogicalKeyboardKey.arrowUp) {
      // Up hides the controls; Down brings them back.
      if (_controlsVisible) _hideControls();
      return KeyEventResult.handled;
    }
    if (_showOverlay &&
        !_controlsVisible &&
        _wakeKeys.contains(event.logicalKey)) {
      // First press only reveals the controls, on the play/pause button.
      _showControls(focusPlayPause: true);
      return KeyEventResult.handled;
    }
    if (_controlsVisible) _showControls();
    return KeyEventResult.ignored;
  }

  void _disposeController() {
    videoPlayerController?.removeListener(_onControllerChanged);
    videoPlayerController?.dispose();
    videoPlayerController = null;
    _youtube?.removeListener(_onYoutubeChanged);
    _youtube?.pause();
    _youtube = null;
  }

  @override
  void dispose() {
    _generation++;
    _hideTimer?.cancel();
    _watchdog?.cancel();
    WakelockPlus.disable();
    _wakelockOn = false;
    _disposeController();
    _screenFocus.dispose();
    _retryFocus.dispose();
    _nextSourceFocus.dispose();
    _playPauseFocus.dispose();
    // TVs have no system bars to bring back, and when changing channel the
    // next player has already set its own screen mode.
    if (!Device.isTv) _restoreSystemUi();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Back first hides the controls on TV, and leaves full screen on
    // phones, before it leaves the player.
    final backHidesControls = Device.isTv && _showOverlay && _controlsVisible;
    final backExitsFullScreen = _fullScreen && !Device.isTv;
    return PopScope(
      canPop: !backHidesControls && !backExitsFullScreen,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (backHidesControls) {
          _hideControls();
        } else if (backExitsFullScreen) {
          _toggleFullScreen();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: _fullScreen
            ? null
            : AppBar(
                backgroundColor: Colors.black,
                title: Text(widget.channel.name),
              ),
        body: Focus(
          focusNode: _screenFocus,
          autofocus: true,
          // Only catches remote keys; the arrows never move onto it.
          skipTraversal: true,
          onKeyEvent: _onKey,
          child: _fullScreen
              ? _buildVideoArea()
              : LayoutBuilder(
                  builder: (context, constraints) {
                    // 16:9 across the width, but never more than 60% of the
                    // height so the buttons below stay visible.
                    final height = (constraints.maxWidth * 9 / 16)
                        .clamp(0.0, constraints.maxHeight * 0.6);
                    return Column(
                      children: [
                        SizedBox(height: height, child: _buildVideoArea()),
                        Expanded(child: _buildChannelInfo()),
                      ],
                    );
                  },
                ),
        ),
      ),
    );
  }

  Widget _buildVideoArea() {
    final controller = videoPlayerController;
    final youtubeView = _youtube?.webView;
    final Widget video;
    if (_isLoading) {
      video = youtubeView == null
          ? _buildConnecting()
          // The YouTube page has to be on screen to load; hide it behind
          // the connecting screen until it plays.
          : Stack(
              fit: StackFit.expand,
              children: [
                _youtubePicture(youtubeView),
                ColoredBox(color: Colors.black, child: _buildConnecting()),
              ],
            );
    } else if (youtubeView != null && !_channelNotFound) {
      video = Center(
        child: FractionallySizedBox(
          widthFactor: _size.factor,
          heightFactor: _size.factor,
          child: Center(
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: _youtubePicture(youtubeView),
            ),
          ),
        ),
      );
    } else if (_channelNotFound || controller == null) {
      video = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Channel not available now',
                style: TextStyle(fontSize: 22, color: Colors.white)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              children: [
                _ControlButton(
                  focusNode: _retryFocus,
                  icon: Icons.refresh_rounded,
                  label: 'Try again',
                  onPressed: _retry,
                ),
                if (widget.channel.streams.length > 1)
                  _ControlButton(
                    icon: Icons.list_rounded,
                    label: 'Choose source',
                    onPressed: _chooseSource,
                  ),
                // YouTube's own app may play what its embedded player
                // could not.
                for (final stream
                    in widget.channel.streams.where((s) => s.isYoutube).take(1))
                  _ControlButton(
                    icon: Icons.smart_display_rounded,
                    label: 'Open in YouTube',
                    onPressed: () => _openExternal(stream),
                  ),
                if (widget.channel.streams.any((s) => !s.isYoutube))
                  _ControlButton(
                    icon: Icons.open_in_new_rounded,
                    label: 'Open in VLC',
                    onPressed: () => _openExternal(_onYoutube
                        ? widget.channel.streams.firstWhere((s) => !s.isYoutube)
                        : null),
                  ),
              ],
            ),
          ],
        ),
      );
    } else {
      final ratio = controller.value.aspectRatio;
      // The video is only a picture: the remote and taps go to the
      // controls, never to the native video view.
      final picture = ExcludeFocus(
        child: IgnorePointer(child: VideoPlayer(controller)),
      );
      final videoSize = controller.value.size;
      video = _size == _PictureSize.zoom && !videoSize.isEmpty
          ? ClipRect(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: videoSize.width,
                  height: videoSize.height,
                  child: picture,
                ),
              ),
            )
          : Center(
              child: FractionallySizedBox(
                widthFactor: _size.factor,
                heightFactor: _size.factor,
                child: Center(
                  child: AspectRatio(
                    aspectRatio: ratio > 0 ? ratio : 16 / 9,
                    child: picture,
                  ),
                ),
              ),
            );
    }

    return GestureDetector(
      key: _videoKey,
      behavior: HitTestBehavior.opaque,
      onTap: () => _controlsVisible ? _hideControls() : _showControls(),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: Colors.black, child: video),
          if (_showOverlay && _isStalled)
            const Center(child: CircularProgressIndicator()),
          if (_showOverlay) _buildOverlay(),
        ],
      ),
    );
  }

  /// Like the video, only a picture: the remote stays on the app's buttons.
  Widget _youtubePicture(WebViewController view) => ExcludeFocus(
        child: IgnorePointer(child: WebViewWidget(controller: view)),
      );

  /// Drawn over the video. Full screen: channel name on top and all the
  /// buttons in one row at the bottom. Otherwise just play/pause and the
  /// full-screen button; the rest sits below the video.
  Widget _buildOverlay() {
    return ExcludeFocus(
      excluding: !_controlsVisible,
      child: IgnorePointer(
        ignoring: !_controlsVisible,
        child: AnimatedOpacity(
          opacity: _controlsVisible ? 1 : 0,
          duration: const Duration(milliseconds: 200),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xB3000000),
                  Color(0x00000000),
                  Color(0x00000000),
                  Color(0xCC000000),
                ],
                stops: [0, 0.25, 0.6, 1],
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _fullScreen
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildTitle(),
                          const Spacer(),
                          Row(
                            children: [
                              const _LiveBadge(),
                              const SizedBox(width: 16),
                              Expanded(
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  clipBehavior: Clip.none,
                                  child: Row(
                                    spacing: 10,
                                    children: _buttons(focusPlayPause: true),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          const Spacer(),
                          _playPauseButton(focus: true),
                          const Spacer(),
                          Row(
                            children: [
                              const _LiveBadge(),
                              const Spacer(),
                              _ControlButton(
                                icon: Icons.fullscreen_rounded,
                                label: 'Full screen',
                                onPressed: _toggleFullScreen,
                              ),
                            ],
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Spinner while a source connects, with buttons to skip to another
  /// source instead of waiting.
  Widget _buildConnecting() {
    final streams = widget.channel.streams;
    final stream = streams[_streamIndex];
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Also tells you where channel up/down landed.
          Text(
            widget.channel.name,
            style: const TextStyle(
                fontSize: 28, fontWeight: FontWeight.w700, color: Colors.white),
          ),
          const SizedBox(height: 20),
          const CircularProgressIndicator(),
          const SizedBox(height: 20),
          Text(
            streams.length > 1
                ? 'Connecting to source ${_streamIndex + 1} of '
                    '${streams.length} (${stream.quality ?? 'Auto'})…'
                : 'Connecting…',
            style: const TextStyle(fontSize: 18, color: Colors.white),
          ),
          if (streams.length > 1) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              children: [
                _ControlButton(
                  focusNode: _nextSourceFocus,
                  icon: Icons.skip_next_rounded,
                  label: 'Next source',
                  onPressed: _skipSource,
                ),
                _ControlButton(
                  icon: Icons.list_rounded,
                  label: 'Choose source',
                  onPressed: _chooseSource,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTitle() {
    final stream = widget.channel.streams[_streamIndex];
    return Row(
      children: [
        if (!Device.isTv)
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _ControlButton(
              icon: Icons.arrow_back_rounded,
              // PopScope turns this into "exit full screen" on phones.
              onPressed: () => Navigator.maybePop(context),
            ),
          ),
        Expanded(
          child: Text(
            '${widget.channel.name}  ·  ${stream.quality ?? 'Auto'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  /// [focus]: this copy is the one the remote jumps to when the controls
  /// appear (there can be two on screen, but only one may hold the node).
  Widget _playPauseButton({bool focus = false}) => _ControlButton(
        focusNode: focus ? _playPauseFocus : null,
        icon: _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
        label: _isPlaying ? 'Pause' : 'Play',
        onPressed: _togglePlay,
      );

  /// Every player action as one row of buttons, the same on TV and phone.
  List<Widget> _buttons({required bool focusPlayPause}) {
    final streams = widget.channel.streams;
    return [
      _playPauseButton(focus: focusPlayPause),
      if (widget.channels.length > 1)
        _ControlButton(
          icon: Icons.view_list_rounded,
          label: 'Channels',
          onPressed: _chooseChannel,
        ),
      if (streams.length > 1)
        _ControlButton(
          icon: Icons.high_quality_rounded,
          label: 'Source ${_streamIndex + 1}/${streams.length}',
          onPressed: _chooseSource,
        ),
      _ControlButton(
        icon: Icons.aspect_ratio_rounded,
        label: 'Size: ${_size.label}',
        onPressed: _nextSize,
      ),
      _ControlButton(
        icon: Icons.open_in_new_rounded,
        label: _onYoutube ? 'Open in YouTube' : 'Open in VLC',
        onPressed: () => _openExternal(),
      ),
      ListenableBuilder(
        listenable: widget.library,
        builder: (context, _) {
          final favourite = widget.library.isFavourite(widget.channel.key);
          return _ControlButton(
            icon: favourite ? Icons.star_rounded : Icons.star_border_rounded,
            iconColor: favourite ? const Color(0xFFFFC94D) : Colors.white,
            label: favourite ? 'Favourite' : 'Add favourite',
            onPressed: () {
              widget.library.toggleFavourite(widget.channel.key);
              _showControls();
            },
          );
        },
      ),
      if (!Device.isTv && _fullScreen)
        _ControlButton(
          icon: Icons.fullscreen_exit_rounded,
          label: 'Exit full screen',
          onPressed: _toggleFullScreen,
        ),
    ];
  }

  /// Below the video on phones (not full screen).
  Widget _buildChannelInfo() {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.surface,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(widget.channel.name, style: theme.textTheme.titleLarge),
          if (widget.channel.languages.isNotEmpty)
            Text(widget.channel.languages.join(', '),
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _buttons(focusPlayPause: false),
          ),
        ],
      ),
    );
  }
}

/// A rounded button with an icon and an optional label. Gets a thick white
/// outline when the TV remote is on it.
class _ControlButton extends StatefulWidget {
  final IconData icon;
  final String? label;
  final VoidCallback onPressed;
  final Color iconColor;
  final FocusNode? focusNode;

  const _ControlButton({
    required this.icon,
    required this.onPressed,
    this.label,
    this.iconColor = Colors.white,
    this.focusNode,
  });

  @override
  State<_ControlButton> createState() => _ControlButtonState();
}

class _ControlButtonState extends State<_ControlButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final label = widget.label;
    return InkWell(
      focusNode: widget.focusNode,
      borderRadius: BorderRadius.circular(28),
      focusColor: Colors.transparent,
      onTap: widget.onPressed,
      onFocusChange: (focused) => setState(() => _focused = focused),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: EdgeInsets.symmetric(
            horizontal: label == null ? 10 : 18, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          color: _focused
              ? Colors.white.withValues(alpha: 0.25)
              : Colors.black.withValues(alpha: 0.55),
          border: Border.all(
            color: _focused ? Colors.white : Colors.white24,
            width: _focused ? 3 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(widget.icon, size: 26, color: widget.iconColor),
            if (label != null) ...[
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFE53935),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text(
        'LIVE',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
        ),
      ),
    );
  }
}
