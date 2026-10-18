import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Whether the app runs on Android TV / Google TV. Set once at start-up.
class Device {
  static const _channel = MethodChannel('live_tv/device');

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
}
