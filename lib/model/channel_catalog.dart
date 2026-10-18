import 'channel.dart';
import 'genre.dart';

/// All channels of one playlist, indexed by genre and language.
class ChannelCatalog {
  final List<Channel> channels;
  late final Map<String, Channel> byKey = {for (final c in channels) c.key: c};

  /// Languages in the playlist, most common first.
  late final List<String> languages = _languagesByCount();

  /// Position of each channel in [channels], to keep sorts stable.
  late final Map<Channel, int> _position = {
    for (var i = 0; i < channels.length; i++) channels[i]: i
  };

  ChannelCatalog(this.channels);

  /// The same catalog with only HD and Full HD channels.
  late final ChannelCatalog hdOnly =
      ChannelCatalog(channels.where((c) => c.isHd).toList());

  /// Channels of [genre] (all genres when null) in [language] (all
  /// languages when null). Within a genre, the genre's most watched
  /// channels come first, then the rest A to Z.
  List<Channel> filter({Genre? genre, String? language}) {
    final result = channels.where((c) {
      if (genre != null) {
        final inGenre = genre == Genre.others
            ? c.genres.isEmpty || c.genres.contains(Genre.others)
            : c.genres.contains(genre);
        if (!inGenre) return false;
      }
      return language == null || c.languages.contains(language);
    }).toList();
    if (genre != null) {
      const unranked = 1 << 30;
      result.sort((a, b) {
        final byRank =
            (a.ranks[genre] ?? unranked).compareTo(b.ranks[genre] ?? unranked);
        if (byRank != 0) return byRank;
        if (a.ranks[genre] == null) {
          // Unranked: A to Z rather than by their rank in another genre.
          final byName = _sortName(a).compareTo(_sortName(b));
          if (byName != 0) return byName;
        }
        return _position[a]!.compareTo(_position[b]!);
      });
    }
    return result;
  }

  static String _sortName(Channel c) =>
      c.name.toLowerCase().replaceAll(RegExp(r'^[^a-z0-9]+'), '');

  /// Genres that have at least one channel in [language], in display order.
  List<Genre> genresWithChannels({String? language}) => Genre.values
      .where((g) => filter(genre: g, language: language).isNotEmpty)
      .toList();

  /// Genres the "Top channels" row takes turns from; Entertainment, the
  /// most watched genre, gets two turns per round.
  static const _topRotation = [
    Genre.entertainment,
    Genre.news,
    Genre.movies,
    Genre.entertainment,
    Genre.sports,
    Genre.kids,
    Genre.music,
  ];

  /// The most watched channels in [language]: the top of each main genre
  /// in turn, so no single genre fills the row.
  List<Channel> popular({String? language, int limit = 20}) {
    final queues = {
      for (final genre in _topRotation.toSet())
        genre: filter(genre: genre, language: language)
            .where((c) => c.ranks.containsKey(genre))
            .toList(),
    };
    final picked = <Channel>[];
    var progress = true;
    while (picked.length < limit && progress) {
      progress = false;
      for (final genre in _topRotation) {
        final queue = queues[genre]!;
        while (queue.isNotEmpty && picked.contains(queue.first)) {
          queue.removeAt(0);
        }
        if (queue.isEmpty) continue;
        picked.add(queue.removeAt(0));
        progress = true;
        if (picked.length == limit) break;
      }
    }
    return picked;
  }

  List<Channel> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final words = q.split(RegExp(r'\s+'));
    final results = channels.where((c) {
      final haystack = [
        c.name,
        ...c.languages,
        ...c.genres.map((g) => g.label),
      ].join(' ').toLowerCase();
      return words.every(haystack.contains);
    }).toList();
    // Names starting with the query first, then the rest; each group keeps
    // the catalog's popularity order (List.sort is not stable, so compare
    // positions explicitly).
    results.sort((a, b) {
      final aStarts = a.name.toLowerCase().startsWith(q) ? 0 : 1;
      final bStarts = b.name.toLowerCase().startsWith(q) ? 0 : 1;
      if (aStarts != bStarts) return aStarts.compareTo(bStarts);
      return _position[a]!.compareTo(_position[b]!);
    });
    return results;
  }

  List<String> _languagesByCount() {
    final counts = <String, int>{};
    for (final c in channels) {
      for (final l in c.languages) {
        counts[l] = (counts[l] ?? 0) + 1;
      }
    }
    return counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
  }
}
