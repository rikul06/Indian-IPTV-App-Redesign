import 'package:shared_preferences/shared_preferences.dart';

/// Remembers which stream URLs did not work and which source last worked
/// for each channel, so a channel opens on a working source instead of
/// waiting on a dead one. A failed URL stays marked until it plays again.
/// Loaded once at start-up.
class StreamHealth {
  static const _badKey = 'bad_streams';
  static const _goodKey = 'good_streams';
  static const _youtubeResetKey = 'youtube_marks_reset';

  /// Failed stream URL -> when it failed (milliseconds since epoch).
  static final Map<String, int> _bad = {};

  /// Channel key -> URL of the stream that last played.
  static final Map<String, String> _good = {};

  static Future<void> load() async {
    _bad.clear();
    _good.clear();
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
      // Every YouTube source failed until the app identified itself to
      // YouTube (error 152); forget those marks once.
      if (prefs.getBool(_youtubeResetKey) != true) {
        _bad.removeWhere((url, _) => url.contains('youtube.com/'));
        await prefs.setBool(_youtubeResetKey, true);
        await _save();
      }
    } catch (_) {
      // Start without history.
    }
  }

  /// Whether [url] did not work last time (and has not worked since).
  static bool isBad(String url) => _bad.containsKey(url);

  static String? lastGood(String channelKey) => _good[channelKey];

  /// Whether none of [urls] (a channel's sources) worked last time.
  static bool allBad(Iterable<String> urls) => urls.every(isBad);

  static void markBad(String url) {
    _bad[url] = DateTime.now().millisecondsSinceEpoch;
    _save();
  }

  static void markGood(String channelKey, String url) {
    _bad.remove(url);
    _good[channelKey] = url;
    _save();
  }

  /// The source to open a channel on: the one that worked last time, else
  /// the first one not marked as failed, else the first.
  static int firstSource(List<String> urls, {String? lastGood}) {
    final good = urls.indexOf(lastGood ?? '');
    if (good >= 0 && !isBad(urls[good])) return good;
    final unmarked = urls.indexWhere((url) => !isBad(url));
    return unmarked >= 0 ? unmarked : 0;
  }

  /// The source to try after [current] fails: the next one (wrapping around)
  /// not yet tried in [failedNow], preferring sources not marked as failed
  /// last time. Null when every source has been tried.
  static int? nextSource(List<String> urls, int current, Set<int> failedNow) {
    final order = [
      for (var step = 1; step < urls.length; step++)
        (current + step) % urls.length,
    ].where((i) => !failedNow.contains(i) && i != current);
    return order.where((i) => !isBad(urls[i])).firstOrNull ?? order.firstOrNull;
  }

  static Future<void> _save() async {
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
