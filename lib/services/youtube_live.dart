import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

/// Plays a channel's YouTube live stream in YouTube's own embedded player,
/// without its buttons, so the app's controls work the same as for any
/// other source.
class YoutubeLive extends ChangeNotifier {
  /// Where the player page claims to come from; YouTube's embed refuses to
  /// play without one.
  static const _origin = 'https://www.youtube.com';

  /// Set once the video id is known; the page plays while this is on screen.
  WebViewController? webView;
  final _started = Completer<bool>();
  bool _playing = false;
  bool _failed = false;

  bool get isPlaying => _playing;

  /// Why the stream did not play, in words, or null.
  String? problem;

  /// The stream stopped with an error after it had started.
  bool get failed => _failed;

  /// Opens the live stream of the channel in [url]
  /// (`https://www.youtube.com/channel/<id>/live`). Completes with true once
  /// the video plays, false if it cannot (for example when the channel is
  /// not live).
  Future<bool> start(String url) async {
    final channel = channelId(url);
    if (channel == null) {
      problem = 'no YouTube channel in the link';
      return false;
    }
    try {
      final webView = WebViewController();
      await webView.setJavaScriptMode(JavaScriptMode.unrestricted);
      await webView.setBackgroundColor(const Color(0xFF000000));
      final platform = webView.platform;
      if (platform is AndroidWebViewController) {
        await platform.setMediaPlaybackRequiresUserGesture(false);
        // Lets chrome://inspect on a computer connected with adb look
        // inside YouTube's player when it does not play.
        await AndroidWebViewController.enableDebugging(true);
      }
      await webView.addJavaScriptChannel('Player',
          onMessageReceived: (message) => _onMessage(message.message));
      await webView.loadHtmlString(_page(channel), baseUrl: _origin);
      this.webView = webView;
      notifyListeners();
    } catch (_) {
      problem = 'this device cannot show YouTube inside the app';
      return false;
    }
    return _started.future;
  }

  void play() => webView?.runJavaScript('player.playVideo()');

  void pause() => webView?.runJavaScript('player.pauseVideo()');

  void _onMessage(String message) {
    if (message.startsWith('error')) {
      problem = describeError(int.tryParse(message.substring(6)) ?? -1);
      debugPrint('YouTube: $problem');
      if (!_started.isCompleted) _started.complete(false);
      _failed = true;
      _playing = false;
    } else if (message.startsWith('state:')) {
      // 1 = playing, 2 = paused, 3 = buffering.
      final state = message.substring(6);
      if (state == '1' && !_started.isCompleted) _started.complete(true);
      if (state != '3') _playing = state == '1';
    }
    notifyListeners();
  }

  /// YouTube's player error codes in words.
  static String describeError(int code) => switch (code) {
        100 => 'the channel is not live right now (error 100)',
        101 ||
        150 =>
          'the channel does not allow its live stream in other apps '
              '(error $code)',
        152 || 153 => 'YouTube\'s player would not start in this app '
            '(error $code)',
        _ => 'YouTube\'s player reported error $code',
      };

  /// The channel id in a `https://www.youtube.com/channel/<id>/live` link.
  static String? channelId(String url) {
    final segments = Uri.tryParse(url)?.pathSegments ?? const [];
    final index = segments.indexOf('channel');
    return index >= 0 && index + 1 < segments.length
        ? segments[index + 1]
        : null;
  }

  /// YouTube's embedded player showing a channel's current live stream,
  /// reporting its state to the app.
  static String _page(String channel) => '''
<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
  html, body { margin: 0; height: 100%; background: #000; overflow: hidden; }
  iframe { position: absolute; width: 100%; height: 100%; border: 0; pointer-events: none; }
</style>
</head>
<body>
<iframe id="player" allow="autoplay; encrypted-media"
  src="https://www.youtube.com/embed/live_stream?channel=$channel&enablejsapi=1&autoplay=1&controls=0&disablekb=1&fs=0&rel=0&iv_load_policy=3&playsinline=1&origin=$_origin"></iframe>
<script>
  var player;
  function onYouTubeIframeAPIReady() {
    player = new YT.Player('player', {
      events: {
        onReady: function (e) { e.target.playVideo(); },
        onStateChange: function (e) { Player.postMessage('state:' + e.data); },
        onError: function (e) { Player.postMessage('error:' + e.data); }
      }
    });
  }
</script>
<script src="https://www.youtube.com/iframe_api"></script>
</body>
</html>
''';
}
