import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../model/channel.dart';
import '../services/device.dart';
import '../services/library_store.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class Player extends StatefulWidget {
  final Channel channel;
  final LibraryStore library;

  const Player({super.key, required this.channel, required this.library});

  @override
  State<Player> createState() => _PlayerState();
}

class _PlayerState extends State<Player> {
  VideoPlayerController? videoPlayerController;
  ChewieController? chewieController;
  bool _isLoading = true;
  bool _channelNotFound = false;

  /// Index of the stream variant being played.
  int _streamIndex = 0;

  /// Bumped on every stream switch so late callbacks from an old stream
  /// are ignored.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _play(0);
  }

  Future<void> _play(int index) async {
    final generation = ++_generation;
    _disposeControllers();
    setState(() {
      _streamIndex = index;
      _isLoading = true;
      _channelNotFound = false;
    });

    final controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.channel.streams[index].url));
    videoPlayerController = controller;

    // Keep the screen on while the video plays.
    controller.addListener(() {
      if (controller.value.isPlaying) {
        WakelockPlus.enable();
      } else {
        WakelockPlus.disable();
      }
    });

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

    setState(() {
      chewieController = ChewieController(
        videoPlayerController: controller,
        autoInitialize: true,
        isLive: true,
        autoPlay: true,
        aspectRatio: controller.value.aspectRatio > 0
            ? controller.value.aspectRatio
            : 16 / 9,
        showOptions: false,
        // A TV remote cannot use the on-screen controls; live TV needs none.
        showControls: !Device.isTv,
        customControls: const MaterialDesktopControls(
          showPlayButton: false,
        ),
      );
      _isLoading = false;
    });
  }

  void _disposeControllers() {
    chewieController?.dispose();
    videoPlayerController?.dispose();
    chewieController = null;
    videoPlayerController = null;
  }

  @override
  void dispose() {
    _generation++;
    WakelockPlus.disable();
    _disposeControllers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final streams = widget.channel.streams;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.channel.name),
        actions: [
          ListenableBuilder(
            listenable: widget.library,
            builder: (context, _) {
              final favourite = widget.library.isFavourite(widget.channel.key);
              return IconButton(
                tooltip:
                    favourite ? 'Remove from favourites' : 'Add to favourites',
                icon: Icon(
                  favourite ? Icons.star_rounded : Icons.star_border_rounded,
                  color: favourite ? const Color(0xFFFFC94D) : null,
                ),
                onPressed: () =>
                    widget.library.toggleFavourite(widget.channel.key),
              );
            },
          ),
          if (streams.length > 1)
            PopupMenuButton<int>(
              tooltip: 'Quality',
              icon: const Icon(Icons.high_quality_rounded),
              onSelected: _play,
              itemBuilder: (context) => [
                for (var i = 0; i < streams.length; i++)
                  CheckedPopupMenuItem(
                    value: i,
                    checked: i == _streamIndex,
                    child: Text(streams[i].label),
                  ),
              ],
            ),
        ],
      ),
      body: Center(
        child: _isLoading
            ? const CircularProgressIndicator()
            : _channelNotFound
                ? const Text('Channel not available now',
                    style: TextStyle(fontSize: 24.0))
                : SizedBox(
                    // Full screen on TV, half the screen on phones.
                    height: MediaQuery.of(context).size.height *
                        (Device.isTv ? 1 : 0.5),
                    child: Chewie(
                      controller: chewieController!,
                    ),
                  ),
      ),
    );
  }
}
