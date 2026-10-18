import 'package:flutter/material.dart';

/// The genres the channel browser groups channels into, in display order.
///
/// Each genre lists the iptv-org categories (https://github.com/iptv-org/database)
/// that belong to it, and a few name keywords used when a channel has no
/// category at all.
enum Genre {
  entertainment(
    'Entertainment',
    Icons.live_tv_rounded,
    Color(0xFFE5397F),
    {'entertainment', 'general', 'comedy', 'series', 'family', 'classic'},
    ['entertainment', ' gec'],
  ),
  movies(
    'Movies',
    Icons.movie_rounded,
    Color(0xFFF2994A),
    {'movies'},
    ['movie', 'cinema', 'cineplex', 'films', 'picture'],
  ),
  news(
    'News',
    Icons.newspaper_rounded,
    Color(0xFF2F80ED),
    {'news', 'business', 'legislative', 'weather', 'public'},
    ['news', 'samachar', 'khabar', 'sansad', 'aaj tak', 'times now'],
  ),
  sports(
    'Sports',
    Icons.sports_cricket_rounded,
    Color(0xFF27AE60),
    {'sports', 'outdoor'},
    ['sport', 'cricket', 'football', 'kabaddi'],
  ),
  kids(
    'Kids',
    Icons.child_care_rounded,
    Color(0xFFF2C94C),
    {'kids', 'animation'},
    ['kids', 'cartoon', 'toon', 'pogo', 'chhota', 'junior'],
  ),
  music(
    'Music',
    Icons.music_note_rounded,
    Color(0xFFBB6BD9),
    {'music'},
    ['music', 'songs', 'beats', 'mtv', ' 9x', 'b4u', 'zoom'],
  ),
  devotional(
    'Devotional',
    Icons.self_improvement_rounded,
    Color(0xFFFF8A3D),
    {'religious'},
    [
      'bhakti',
      'aastha',
      'sanskar',
      'satsang',
      'gurbani',
      'devotional',
      'dharm',
      'jinvani',
      'peace tv',
      'god tv',
      'church',
      'quran',
      'madani'
    ],
  ),
  infotainment(
    'Infotainment',
    Icons.explore_rounded,
    Color(0xFF2DBEB1),
    {
      'documentary',
      'education',
      'science',
      'travel',
      'culture',
      'lifestyle',
      'cooking',
      'auto',
      'relax',
      'interactive',
    },
    [
      'discovery',
      'history',
      'geographic',
      'food',
      'travel',
      'education',
      'gyan',
      'vidya'
    ],
  ),
  shopping(
    'Shopping',
    Icons.shopping_bag_rounded,
    Color(0xFF9B51E0),
    {'shop'},
    ['shop'],
  ),
  others(
    'Others',
    Icons.apps_rounded,
    Color(0xFF828282),
    {},
    [],
  );

  const Genre(
      this.label, this.icon, this.color, this.categories, this.keywords);

  final String label;
  final IconData icon;
  final Color color;
  final Set<String> categories;
  final List<String> keywords;

  /// Genres for a list of iptv-org category ids or playlist group titles
  /// ("Entertainment", "Movies;Series", "news"...). Empty if none match.
  static Set<Genre> fromCategories(Iterable<String> categories) {
    final genres = <Genre>{};
    for (final raw in categories) {
      for (final part in raw.split(';')) {
        final category = part.trim().toLowerCase();
        for (final genre in values) {
          if (genre.categories.contains(category) ||
              genre.label.toLowerCase() == category) {
            genres.add(genre);
          }
        }
      }
    }
    return genres;
  }

  /// Best guess from the channel name, for channels with no category.
  static Set<Genre> guessFromName(String name) {
    final padded = ' ${name.toLowerCase()} ';
    for (final genre in values) {
      if (genre.keywords.any(padded.contains)) return {genre};
    }
    return {};
  }
}
