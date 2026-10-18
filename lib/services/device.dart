import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Whether the app runs on Android TV / Google TV. Set once at start-up.
class Device {
  static const _channel = MethodChannel('live_tv/device');

  static bool isTv = false;

  static Future<void> detect() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      isTv = await _channel.invokeMethod<bool>('isTv') ?? false;
    } catch (_) {
      isTv = false;
    }
  }
}
