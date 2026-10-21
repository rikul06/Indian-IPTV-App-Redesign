import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Talks to the Android side: TV detection and external players.
class Device {
  static const _channel = MethodChannel('live_tv/device');

  /// Whether the app runs on Android TV / Google TV. Set once at start-up.
  static bool isTv = false;

  /// `--dart-define=FORCE_TV=true` makes any build behave like the TV app,
  /// for testing the TV layout on a computer.
  static const _forceTv = bool.fromEnvironment('FORCE_TV');

  static Future<void> detect() async {
    if (_forceTv) {
      isTv = true;
      return;
    }
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      isTv = await _channel.invokeMethod<bool>('isTv') ?? false;
    } catch (_) {
      isTv = false;
    }
  }

  /// Opens [url] in VLC, or in another video app when VLC is not
  /// installed. Returns false when there is no video app at all.
  static Future<bool> openExternal(String url, String title) async {
    try {
      return await _channel.invokeMethod<bool>(
              'openExternal', {'url': url, 'title': title}) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Opens [url] in the app that handles it, such as YouTube. Returns false
  /// when no app can.
  static Future<bool> openUrl(String url) async {
    try {
      return await _channel.invokeMethod<bool>('openUrl', {'url': url}) ??
          false;
    } catch (_) {
      return false;
    }
  }
}
