import '../services/stream_health.dart';
import 'genre.dart';

/// One playable URL of a channel. Playlists often list the same channel
/// several times at different qualities; those become variants of one channel.
class StreamVariant {
  final String url;

  /// HTTP headers the stream needs (Referer, User-Agent), from the
  /// playlist's #EXTVLCOPT lines. Usually empty.
  final Map<String, String> headers;

  /// Resolution from the playlist name, such as "1080p". May be null.
  final String? quality;
  final bool geoBlocked;
  final bool notAlwaysOn;

  StreamVariant({
    required this.url,
    this.headers = const {},
    this.quality,
    this.geoBlocked = false,
    this.notAlwaysOn = false,
  });

  /// A YouTube live stream, played in YouTube's own player.
  bool get isYoutube =>
      url.contains('youtube.com/') || url.contains('youtu.be/');

  /// Vertical resolution in lines, 0 when unknown; an "HD" feed counts as 720.
  int get lines => quality == 'HD'
      ? 720
      : int.tryParse(quality?.replaceAll(RegExp(r'[^0-9]'), '') ?? '') ?? 0;

  String get label {
    final parts = [
      quality ?? 'Auto',
      if (geoBlocked) 'geo-blocked',
      if (notAlwaysOn) 'not 24/7',
    ];
    return parts.join(' · ');
  }
}

/// Lower-case name without spaces, punctuation or a trailing HD/SD, used to
/// merge the SD and HD versions of a channel and to look up its popularity:
/// "Zee TV HD" and "Zee TV" both become "zeetv", "&TV" becomes "andtv".
String normalizeChannelName(String name) {
  final compact = name
      .toLowerCase()
      .replaceAll('&', 'and')
      .replaceAll(RegExp(r'[^a-z0-9]'), '');
  final stripped = compact.replaceFirst(RegExp(r'(hd|sd)$'), '');
  return stripped.isEmpty ? compact : stripped;
}

class Channel {
  /// Stable id used for favourites and recently watched.
  final String key;
  final String name;

  /// Network logo URL, or null to draw the channel's initials.
  final String? logoUrl;
  final List<StreamVariant> streams;
  final Set<Genre> genres;
  final List<String> languages;

  /// Position in each genre's popularity list (0 = most watched). Empty
  /// when the channel is not in the list.
  final Map<Genre, int> ranks;

  Channel({
    required this.key,
    required this.name,
    required this.logoUrl,
    required this.streams,
    required this.genres,
    required this.languages,
    this.ranks = const {},
  });

  /// Best position in any genre's popularity list, or null if unranked.
  int? get bestRank =>
      ranks.isEmpty ? null : ranks.values.reduce((a, b) => a < b ? a : b);

  String get streamUrl => streams.first.url;

  bool get isHd => streams.any((s) => s.lines >= 720);

  /// None of the sources worked last time the channel was opened.
  bool get notWorking => StreamHealth.allBad(streams.map((s) => s.url));

  String get initials {
    final words = name
        .split(RegExp(r'[\s\-_]+'))
        .map((w) => w.replaceAll(RegExp(r'[^A-Za-z0-9]'), ''))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return 'TV';
    if (words.length == 1) {
      final word = words.first;
      return word.substring(0, word.length < 2 ? word.length : 2).toUpperCase();
    }
    return (words[0][0] + words[1][0]).toUpperCase();
  }

  /// The genre the channel is shown under first.
  Genre get primaryGenre => genres.isEmpty ? Genre.others : genres.first;
}
