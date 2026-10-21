import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

/// Plays a channel's YouTube live stream in YouTube's own embedded player,
/// without its buttons, so the app's controls work the same as for any
/// other source.
class YoutubeLive extends ChangeNotifier {
  /// Who is embedding the player. YouTube needs to know (error 153 without
  /// it) and refuses its own domain (error 152); apps identify themselves
  /// as https://<application id>.
  static const _origin = 'https://com.nk.live_tv';

  /// Set once the video id is known; the page plays while this is on screen.
  WebViewController? webView;
  final _started = Completer<bool>();
  bool _playing = false;
  bool _failed = false;

  bool get isPlaying => _playing;

  /// YouTube's player state: 1 playing, 2 paused, 3 buffering, -1 unknown.
  int state = -1;

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
    // Play the live video itself when the TV can look it up: YouTube's
    // "channel live stream" embed is refused for some channels running
    // several live streams.
    final video = await liveVideoId(channel);
    debugPrint('YouTube: channel $channel, live video ${video ?? 'not found'}');
    try {
      final webView = WebViewController();
      await webView.setJavaScriptMode(JavaScriptMode.unrestricted);
      await webView.setBackgroundColor(const Color(0xFF000000));
      final platform = webView.platform;
      if (platform is AndroidWebViewController) {
        await platform.setMediaPlaybackRequiresUserGesture(false);
        // Lay the page out 1920 web pixels wide (its viewport tag) and zoom
        // it to fit the screen.
        await platform.setUseWideViewPort(true);
        // Lets chrome://inspect on a computer connected with adb look
        // inside YouTube's player when it does not play.
        await AndroidWebViewController.enableDebugging(true);
      }
      await webView.addJavaScriptChannel('Player',
          onMessageReceived: (message) => _onMessage(message.message));
      await webView.loadHtmlString(
          _page(video ?? 'live_stream?channel=$channel'),
          baseUrl: _origin);
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
      state = int.tryParse(message.substring(6)) ?? -1;
      if (state == 1 && !_started.isCompleted) _started.complete(true);
      if (state != 3) _playing = state == 1;
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

  /// The id of the video [channel] is streaming live now, from its live
  /// page, or null when it is not live or YouTube cannot be reached.
  static Future<String?> liveVideoId(String channel) async {
    try {
      final response = await http.get(
          Uri.parse('https://www.youtube.com/channel/$channel/live'),
          headers: const {
            'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/130.0 Safari/537.36',
            'Accept-Language': 'en-US,en;q=0.9',
            // Skips the cookie consent page shown in some countries.
            'Cookie': 'SOCS=CAI',
          }).timeout(const Duration(seconds: 10));
      return videoIdFromPage(response.body);
    } catch (_) {
      return null;
    }
  }

  /// A live page names its video as the canonical address; an offline
  /// channel's page names the channel instead.
  static String? videoIdFromPage(String html) => RegExp(
          r'<link rel="canonical" href="https://www\.youtube\.com/watch\?v=([\w-]{11})"')
      .firstMatch(html)
      ?.group(1);

  /// The channel id in a `https://www.youtube.com/channel/<id>/live` link.
  static String? channelId(String url) {
    final segments = Uri.tryParse(url)?.pathSegments ?? const [];
    final index = segments.indexOf('channel');
    return index >= 0 && index + 1 < segments.length
        ? segments[index + 1]
        : null;
  }

  /// YouTube's embedded player for [embed] (a video id, or
  /// `live_stream?channel=<id>`), reporting its state to the app.
  static String _page(String embed) => '''
<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=1920, user-scalable=no">
<style>
  html, body { margin: 0; height: 100%; background: #000; overflow: hidden; }
  /* YouTube picks the quality from the player's size, and a TV's web view
     is only about 960x540 web pixels: lay the player out at 1920x1080 and
     fit it to the screen, so YouTube plays full HD when the network
     allows. The viewport tag does the fitting on Android; fit() below
     covers web views that ignore it. */
  #box { position: absolute; left: 0; top: 0; width: 1920px; height: 1080px;
         transform-origin: 0 0; }
  iframe { width: 1920px; height: 1080px; border: 0; pointer-events: none; }
</style>
</head>
<body>
<div id="box">
<iframe id="player" allow="autoplay; encrypted-media"
  referrerpolicy="strict-origin-when-cross-origin"
  src="https://www.youtube.com/embed/$embed${embed.contains('?') ? '&' : '?'}enablejsapi=1&autoplay=1&controls=0&disablekb=1&fs=0&rel=0&iv_load_policy=3&playsinline=1&origin=$_origin&widget_referrer=$_origin&vq=hd1080"></iframe>
</div>
<script>
  function fit() {
    var width = document.documentElement.clientWidth;
    var height = document.documentElement.clientHeight;
    if (!width || !height) return;
    var scale = Math.min(width / 1920, height / 1080);
    document.getElementById('box').style.transform =
        'translate(' + (width - 1920 * scale) / 2 + 'px,' +
        (height - 1080 * scale) / 2 + 'px) scale(' + scale + ')';
  }
  // The page can load before the app gives it its final size.
  addEventListener('resize', fit);
  setInterval(fit, 1000);
  fit();

  var player;
  function onYouTubeIframeAPIReady() {
    player = new YT.Player('player', {
      events: {
        onReady: function (e) {
          e.target.setPlaybackQuality('hd1080');
          e.target.playVideo();
        },
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
