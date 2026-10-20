import 'package:shared_preferences/shared_preferences.dart';

/// Remembers which stream URLs failed recently and which source last worked
/// for each channel, so a channel opens on a working source instead of
/// waiting on a dead one. Loaded once at start-up.
class StreamHealth {
  static const _badKey = 'bad_streams';
  static const _goodKey = 'good_streams';

  /// How long a failed stream is skipped. Free streams often come back.
  static const _badFor = Duration(hours: 12);

  /// Failed stream URL -> when it failed (milliseconds since epoch).
  static final Map<String, int> _bad = {};

  /// Channel key -> URL of the stream that last played.
  static final Map<String, String> _good = {};

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final entry in prefs.getStringList(_badKey) ?? const <String>[]) {
        final split = entry.indexOf('|');
        if (split <= 0) continue;
        final time = int.tryParse(entry.substring(0, split));
        if (time != null) _bad[entry.substring(split + 1)] = time;
      }
      for (final entry in prefs.getStringList(_goodKey) ?? const <String>[]) {
        final split = entry.indexOf('|');
        if (split <= 0) continue;
        _good[entry.substring(0, split)] = entry.substring(split + 1);
      }
    } catch (_) {
      // Start without history.
    }
  }

  static bool isBad(String url) {
    final failedAt = _bad[url];
    return failedAt != null &&
        DateTime.now().millisecondsSinceEpoch - failedAt <
            _badFor.inMilliseconds;
  }

  static String? lastGood(String channelKey) => _good[channelKey];

  static void markBad(String url) {
    _bad[url] = DateTime.now().millisecondsSinceEpoch;
    _save();
  }

  static void markGood(String channelKey, String url) {
    _bad.remove(url);
    _good[channelKey] = url;
    _save();
  }

  static Future<void> _save() async {
    _bad.removeWhere((url, _) => !isBad(url));
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
          _badKey, [for (final e in _bad.entries) '${e.value}|${e.key}']);
      await prefs.setStringList(
          _goodKey, [for (final e in _good.entries) '${e.key}|${e.value}']);
    } catch (_) {
      // Kept in memory for this session.
    }
  }
}
