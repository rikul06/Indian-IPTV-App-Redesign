import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Favourite and recently watched channels, saved on the device by channel key.
class LibraryStore extends ChangeNotifier {
  static const _favouritesKey = 'favourites';
  static const _recentKey = 'recent';
  static const maxRecent = 20;

  List<String> _favourites = [];
  List<String> _recent = [];

  List<String> get favourites => List.unmodifiable(_favourites);
  List<String> get recent => List.unmodifiable(_recent);

  bool isFavourite(String key) => _favourites.contains(key);

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _favourites = prefs.getStringList(_favouritesKey) ?? [];
      _recent = prefs.getStringList(_recentKey) ?? [];
      notifyListeners();
    } catch (_) {
      // Storage unavailable: start empty.
    }
  }

  /// Adds or removes [key]; returns true if it is now a favourite.
  Future<bool> toggleFavourite(String key) async {
    final added = !_favourites.remove(key);
    if (added) _favourites.insert(0, key);
    notifyListeners();
    await _save(_favouritesKey, _favourites);
    return added;
  }

  Future<void> markWatched(String key) async {
    _recent
      ..remove(key)
      ..insert(0, key);
    if (_recent.length > maxRecent) {
      _recent.removeRange(maxRecent, _recent.length);
    }
    notifyListeners();
    await _save(_recentKey, _recent);
  }

  Future<void> _save(String name, List<String> value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(name, value);
    } catch (_) {
      // Keep the in-memory list even if it cannot be saved.
    }
  }
}
