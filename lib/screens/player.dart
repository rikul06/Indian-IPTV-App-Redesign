import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../model/channel.dart';
import '../services/device.dart';
import '../services/library_store.dart';

/// Remote and keyboard keys that toggle play/pause.
final _playPauseKeys = {
  LogicalKeyboardKey.mediaPlayPause,
  LogicalKeyboardKey.mediaPlay,
  LogicalKeyboardKey.mediaPause,
  LogicalKeyboardKey.space,
};

/// Keys that only bring the controls back while they are hidden.
final _wakeKeys = {
  LogicalKeyboardKey.select,
  LogicalKeyboardKey.enter,
  LogicalKeyboardKey.arrowUp,
  LogicalKeyboardKey.arrowDown,
  LogicalKeyboardKey.arrowLeft,
  LogicalKeyboardKey.arrowRight,
};

class Player extends StatefulWidget {
  final Channel channel;
  final LibraryStore library;

  const Player({super.key, required this.channel, required this.library});

  @override
  State<Player> createState() => _PlayerState();
}

class _PlayerState extends State<Player> {
  VideoPlayerController? videoPlayerController;
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

  /// Keeps the video widget alive when it moves between the normal and
  /// full-screen layouts.
  final GlobalKey _videoKey = GlobalKey();

  bool get _isPlaying => videoPlayerController?.value.isPlaying ?? false;

  @override
  void initState() {
    super.initState();
    if (_fullScreen) _applySystemUi();
    _play(0);
  }

  Future<void> _play(int index) async {
    final generation = ++_generation;
    _disposeController();
    setState(() {
      _streamIndex = index;
      _isLoading = true;
      _channelNotFound = false;
    });

    final controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.channel.streams[index].url));
    videoPlayerController = controller;
    controller.addListener(_onControllerChanged);

    try {
      await controller.initialize();
    } catch (_) {
      if (!mounted || generation != _generation) return;
      // This stream is down: try the next quality, if any.
      if (index + 1 < widget.channel.streams.length) {
        _play(index + 1);
      } else {
        setState(() {
          _isLoading = false;
          _channelNotFound = true;
        });
      }
      return;
    }
    if (!mounted || generation != _generation) return;

    await controller.play();
    setState(() => _isLoading = false);
    _showControls();
  }

  /// Keeps the screen on while the video plays and redraws the
  /// play/pause button when the state changes.
  void _onControllerChanged() {
    final playing = _isPlaying;
    if (playing) {
      WakelockPlus.enable();
    } else {
      WakelockPlus.disable();
    }
    if (mounted) setState(() {});
  }

  void _togglePlay() {
    final controller = videoPlayerController;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isPlaying) {
      controller.pause();
    } else {
      controller.play();
    }
    _showControls();
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

  /// Shows the controls and hides them again after a few seconds of
  /// playback without input.
  void _showControls({bool focusPlayPause = false}) {
    _hideTimer?.cancel();
    if (!_controlsVisible) setState(() => _controlsVisible = true);
    if (focusPlayPause) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _playPauseFocus.requestFocus());
    }
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted || !_isPlaying) return;
      setState(() => _controlsVisible = false);
      _screenFocus.requestFocus();
    });
  }

  void _hideControls() {
    _hideTimer?.cancel();
    setState(() => _controlsVisible = false);
    _screenFocus.requestFocus();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (_playPauseKeys.contains(event.logicalKey)) {
      _togglePlay();
      return KeyEventResult.handled;
    }
    if (!_controlsVisible && _wakeKeys.contains(event.logicalKey)) {
      // First press only reveals the controls, on the play/pause button.
      _showControls(focusPlayPause: true);
      return KeyEventResult.handled;
    }
    _showControls();
    return KeyEventResult.ignored;
  }

  void _disposeController() {
    videoPlayerController?.removeListener(_onControllerChanged);
    videoPlayerController?.dispose();
    videoPlayerController = null;
  }

  @override
  void dispose() {
    _generation++;
    _hideTimer?.cancel();
    WakelockPlus.disable();
    _disposeController();
    _screenFocus.dispose();
    _playPauseFocus.dispose();
    _restoreSystemUi();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // On phones, Back leaves full screen before it leaves the player.
    final backExitsFullScreen = _fullScreen && !Device.isTv;
    return PopScope(
      canPop: !backExitsFullScreen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && backExitsFullScreen) _toggleFullScreen();
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
          onKeyEvent: _onKey,
          child: _fullScreen
              ? _buildVideoArea()
              : LayoutBuilder(
                  builder: (context, constraints) {
                    // 16:9 across the width, but never more than 60% of the
                    // height so the details below stay visible.
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
    final Widget video;
    if (_isLoading) {
      video = const Center(child: CircularProgressIndicator());
    } else if (_channelNotFound || controller == null) {
      video = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Channel not available now',
                style: TextStyle(fontSize: 22, color: Colors.white)),
            const SizedBox(height: 16),
            FilledButton.icon(
              autofocus: true,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
              onPressed: () => _play(0),
            ),
          ],
        ),
      );
    } else {
      final ratio = controller.value.aspectRatio;
      video = Center(
        child: AspectRatio(
          aspectRatio: ratio > 0 ? ratio : 16 / 9,
          child: VideoPlayer(controller),
        ),
      );
    }

    final showOverlay = !_isLoading && !_channelNotFound;
    return GestureDetector(
      key: _videoKey,
      behavior: HitTestBehavior.opaque,
      onTap: () => _controlsVisible ? _hideControls() : _showControls(),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: Colors.black, child: video),
          if (showOverlay) _buildControls(),
        ],
      ),
    );
  }

  /// Title bar, big play/pause button and full-screen toggle drawn over the
  /// video. Hidden controls cannot take focus.
  Widget _buildControls() {
    final streams = widget.channel.streams;
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
                  Color(0xB3000000),
                ],
                stops: [0, 0.3, 0.7, 1],
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    if (_fullScreen)
                      Row(
                        children: [
                          _ControlButton(
                            icon: Icons.arrow_back_rounded,
                            tooltip: 'Back',
                            // On phones PopScope turns this into "exit
                            // full screen"; on TV it closes the player.
                            onPressed: () => Navigator.maybePop(context),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              widget.channel.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          _favouriteButton(),
                          if (streams.length > 1) _qualityButton(),
                        ],
                      ),
                    const Spacer(),
                    _ControlButton(
                      focusNode: _playPauseFocus,
                      icon: _isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      tooltip: _isPlaying ? 'Pause' : 'Play',
                      size: 72,
                      onPressed: _togglePlay,
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        const _LiveBadge(),
                        const Spacer(),
                        if (!Device.isTv)
                          _ControlButton(
                            icon: _fullScreen
                                ? Icons.fullscreen_exit_rounded
                                : Icons.fullscreen_rounded,
                            tooltip: _fullScreen
                                ? 'Exit full screen'
                                : 'Full screen',
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

  Widget _favouriteButton() => ListenableBuilder(
        listenable: widget.library,
        builder: (context, _) {
          final favourite = widget.library.isFavourite(widget.channel.key);
          return _ControlButton(
            icon: favourite ? Icons.star_rounded : Icons.star_border_rounded,
            color: favourite ? const Color(0xFFFFC94D) : Colors.white,
            tooltip: favourite ? 'Remove from favourites' : 'Add to favourites',
            onPressed: () {
              widget.library.toggleFavourite(widget.channel.key);
              _showControls();
            },
          );
        },
      );

  Widget _qualityButton() {
    final streams = widget.channel.streams;
    return PopupMenuButton<int>(
      tooltip: 'Quality',
      onOpened: _hideTimer?.cancel,
      onSelected: _play,
      itemBuilder: (context) => [
        for (var i = 0; i < streams.length; i++)
          CheckedPopupMenuItem(
            value: i,
            checked: i == _streamIndex,
            child: Text(streams[i].label),
          ),
      ],
      child: const Padding(
        padding: EdgeInsets.all(10),
        child: Icon(Icons.high_quality_rounded, color: Colors.white, size: 28),
      ),
    );
  }

  /// Below the video on phones (not full screen): favourite and quality.
  Widget _buildChannelInfo() {
    final streams = widget.channel.streams;
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
          const SizedBox(height: 12),
          Row(
            children: [
              _favouriteButton(),
              if (streams.length > 1) _qualityButton(),
              const Spacer(),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.fullscreen_rounded),
                label: const Text('Full screen'),
                onPressed: _toggleFullScreen,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A round icon button for the video overlay with a clear outline when the
/// TV remote is on it.
class _ControlButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final double size;
  final Color color;
  final FocusNode? focusNode;

  const _ControlButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = 28,
    this.color = Colors.white,
    this.focusNode,
  });

  @override
  State<_ControlButton> createState() => _ControlButtonState();
}

class _ControlButtonState extends State<_ControlButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final large = widget.size > 40;
    return Tooltip(
      message: widget.tooltip,
      child: InkWell(
        focusNode: widget.focusNode,
        customBorder: const CircleBorder(),
        focusColor: Colors.transparent,
        onTap: widget.onPressed,
        onFocusChange: (focused) => setState(() => _focused = focused),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: EdgeInsets.all(large ? 14 : 10),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: large || _focused
                ? Colors.black.withValues(alpha: 0.45)
                : Colors.transparent,
            border: Border.all(
              color: _focused ? Colors.white : Colors.transparent,
              width: 3,
            ),
          ),
          child: Icon(widget.icon, size: widget.size, color: widget.color),
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
