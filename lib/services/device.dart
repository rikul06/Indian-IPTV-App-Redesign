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

  /// Opens [url] in another video app (VLC, MX Player...). Returns false
  /// when no such app is installed.
  static Future<bool> openExternal(String url) async {
    try {
      return await _channel.invokeMethod<bool>('openExternal', {'url': url}) ??
          false;
    } catch (_) {
      return false;
    }
  }
}
