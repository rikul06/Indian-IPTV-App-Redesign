import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../model/channel.dart';
import '../model/channel_catalog.dart';
import '../model/genre.dart';
import '../model/stream_source.dart';

class ChannelsProvider {
  static const bundledStreamsCatalog = 'data/streams.csv';
  static const channelMetaAsset = 'assets/data/channel_meta.json';
  static const popularityAsset = 'assets/data/popular_channels.txt';

  /// Where the newest data files live: this repo, refreshed weekly by
  /// .github/workflows/refresh-channel-data.yml.
  static const repoDataUrl =
      'https://raw.githubusercontent.com/rikul06/Indian-IPTV-App-Redesign/main/';

  Map<String, dynamic>? _channelMeta;
  Map<String, Map<Genre, int>>? _popularity;

  /// Playlists to choose from, listed in data/streams.csv.
  Future<List<StreamSource>> fetchStreamSources() async =>
      parseStreamSources(await rootBundle.loadString(bundledStreamsCatalog));

  static List<StreamSource> parseStreamSources(String csv) {
    final sources = <StreamSource>[];
    for (final line in const LineSplitter().convert(csv)) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.toLowerCase().startsWith('name,')) {
        continue;
      }

      final commaIndex = trimmed.indexOf(',');
      if (commaIndex == -1) continue;

      final name = trimmed.substring(0, commaIndex).trim();
      final streamUrl = trimmed.substring(commaIndex + 1).trim();
      if (name.isNotEmpty && streamUrl.isNotEmpty) {
        sources.add(StreamSource(name: name, streamUrl: streamUrl));
      }
    }
    return sources;
  }

  Future<ChannelCatalog> fetchCatalog(StreamSource source) async {
    final response = await http.get(Uri.parse(source.streamUrl));
    if (response.statusCode != 200) {
      throw Exception('Failed to load M3U file');
    }
    final meta = await _loadChannelMeta();
    final popularity = await _loadPopularity();
    return ChannelCatalog(parseM3U(
        utf8.decode(response.bodyBytes, allowMalformed: true), meta,
        popularity: popularity));
  }

  Future<Map<String, Map<Genre, int>>> _loadPopularity() async {
    if (_popularity != null) return _popularity!;
    try {
      _popularity = await latestData(popularityAsset, (text) {
        final ranks = parsePopularity(text);
        if (ranks.isEmpty) throw const FormatException('No channels');
        return ranks;
      });
    } catch (_) {
      _popularity = {};
    }
    return _popularity!;
  }

  /// Reads assets/data/popular_channels.txt into
  /// normalized name -> genre -> position in that genre's section.
  static Map<String, Map<Genre, int>> parsePopularity(String text) {
    final ranks = <String, Map<Genre, int>>{};
    Genre? section;
    var position = 0;
    for (final rawLine in const LineSplitter().convert(text)) {
      final line = rawLine.trim();
      if (line.startsWith('##')) {
        final label = line.substring(2).trim().toLowerCase();
        section = Genre.values
            .where((g) => g.label.toLowerCase() == label)
            .firstOrNull;
        position = 0;
      } else if (section != null && line.isNotEmpty && !line.startsWith('#')) {
        ranks
            .putIfAbsent(normalizeChannelName(line), () => {})
            .putIfAbsent(section, () => position);
        position++;
      }
    }
    return ranks;
  }

  /// The newest copy of a data file, so genres, logos and popularity update
  /// without a new APK: downloaded from this repo, else the copy saved last
  /// time, else the one built into the app. [parse] rejects a bad copy by
  /// throwing.
  static Future<T> latestData<T>(String asset, T Function(String) parse,
      {Future<String> Function()? download}) async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {
      // No saved copies.
    }
    try {
      final text = await (download ?? () => _download(asset))();
      final data = parse(text);
      await prefs?.setString(asset, text);
      return data;
    } catch (_) {
      // Offline or GitHub unreachable.
    }
    final saved = prefs?.getString(asset);
    if (saved != null) {
      try {
        return parse(saved);
      } catch (_) {
        // Fall back to the built-in copy.
      }
    }
    return parse(await rootBundle.loadString(asset));
  }

  static Future<String> _download(String asset) async {
    final response = await http
        .get(Uri.parse('$repoDataUrl$asset'))
        .timeout(const Duration(seconds: 5));
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }
    return utf8.decode(response.bodyBytes);
  }

  Future<Map<String, dynamic>> _loadChannelMeta() async {
    if (_channelMeta != null) return _channelMeta!;
    try {
      _channelMeta = await latestData(
          channelMetaAsset, (text) => jsonDecode(text) as Map<String, dynamic>);
    } catch (_) {
      _channelMeta = {};
    }
    return _channelMeta!;
  }

  static final _attribute = RegExp(r'([\w-]+)="([^"]*)"');
  static final _quality = RegExp(r'\((\d{3,4}[pi])\)');
  static final _tag = RegExp(r'\[([^\]]*)\]');

  /// Parses an M3U playlist into channels. Entries with the same name (the
  /// same channel at different qualities, or its SD and HD versions) become
  /// one channel with several stream variants. [meta] maps iptv-org channel
  /// ids to their categories ("c"), languages ("lang") and logo ("l").
  /// Channels are sorted most popular first by [popularity], then by name.
  static List<Channel> parseM3U(String text, Map<String, dynamic> meta,
      {Map<String, Map<Genre, int>> popularity = const {}}) {
    final builders = <String, _ChannelBuilder>{};
    Map<String, String>? attributes;
    String? title;
    var headers = <String, String>{};

    for (final rawLine in const LineSplitter().convert(text)) {
      final line = rawLine.trim();
      if (line.startsWith('#EXTINF:')) {
        attributes = {
          for (final m in _attribute.allMatches(line)) m.group(1)!: m.group(2)!
        };
        title = _extractTitle(line);
        headers = {};
      } else if (line.startsWith('#EXTVLCOPT:http-referrer=')) {
        // Some streams only play when they look like they come from the
        // channel's website or a browser.
        headers['Referer'] = line.substring(line.indexOf('=') + 1);
      } else if (line.startsWith('#EXTVLCOPT:http-user-agent=')) {
        headers['User-Agent'] = line.substring(line.indexOf('=') + 1);
      } else if (line.isNotEmpty && !line.startsWith('#')) {
        if (title != null && title.isNotEmpty) {
          _addEntry(
              builders, attributes ?? const {}, title, line, headers, meta);
        }
        attributes = null;
        title = null;
        headers = {};
      }
    }

    // Popular channels first, then by name, ignoring leading symbols so
    // "&TV" sorts under T.
    String sortKey(Channel c) =>
        c.name.toLowerCase().replaceAll(RegExp(r'^[^a-z0-9]+'), '');
    final channels = builders.values
        .map((b) => b.build(popularity[b.key] ?? const {}))
        .toList()
      ..sort((a, b) {
        final byRank = (a.bestRank ?? 1 << 30).compareTo(b.bestRank ?? 1 << 30);
        return byRank != 0 ? byRank : sortKey(a).compareTo(sortKey(b));
      });
    return channels;
  }

  /// The display title is everything after the first comma that follows the
  /// attributes, so names containing commas survive.
  static String _extractTitle(String line) {
    final lastQuote = line.lastIndexOf('"');
    final comma = line.indexOf(',', lastQuote == -1 ? 0 : lastQuote);
    return comma == -1 ? '' : line.substring(comma + 1).trim();
  }

  static void _addEntry(
    Map<String, _ChannelBuilder> builders,
    Map<String, String> attributes,
    String title,
    String url,
    Map<String, String> headers,
    Map<String, dynamic> meta,
  ) {
    final quality = _quality.firstMatch(title)?.group(1);
    final tags =
        _tag.allMatches(title).map((m) => m.group(1)!.toLowerCase()).toList();
    final name = title
        .replaceAll(_quality, '')
        .replaceAll(_tag, '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (name.isEmpty) return;

    final tvgId = attributes['tvg-id'] ?? '';
    final baseId = tvgId.split('@').first;
    final key = normalizeChannelName(name);
    final isHdName = RegExp(r'\bHD$', caseSensitive: false).hasMatch(name);

    final builder = builders.putIfAbsent(key, () {
      final info = meta[baseId] as Map<String, dynamic>? ?? const {};
      final logo = attributes['tvg-logo'];
      final groups = (attributes['group-title'] ?? '')
          .split(';')
          .where((g) => g.isNotEmpty && g.toLowerCase() != 'undefined');
      final categories = [
        ...((info['c'] as List?)?.cast<String>() ?? const <String>[]),
        ...groups,
      ];
      var genres = Genre.fromCategories(categories);
      if (genres.isEmpty) genres = Genre.guessFromName(name);
      return _ChannelBuilder(
        key: key,
        name: name,
        logoUrl: (logo != null && logo.startsWith('http'))
            ? logo
            : info['l'] as String?,
        genres: genres,
        languages: (info['lang'] as List?)?.cast<String>() ??
            _splitLanguages(attributes['tvg-language']),
      );
    });

    // Show "Zee TV" rather than "Zee TV HD" when both are in the playlist.
    if (name.length < builder.name.length) builder.name = name;
    builder.logoUrl ??= attributes['tvg-logo'] ??
        (meta[baseId] as Map<String, dynamic>?)?['l'] as String?;

    if (builder.streams.any((s) => s.url == url)) return;
    builder.streams.add(StreamVariant(
      url: url,
      headers: headers,
      quality: quality ?? (isHdName ? 'HD' : null),
      geoBlocked: tags.contains('geo-blocked'),
      notAlwaysOn: tags.contains('not 24/7'),
    ));
  }

  static List<String> _splitLanguages(String? value) => (value ?? '')
      .split(';')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
}

class _ChannelBuilder {
  final String key;
  String name;
  String? logoUrl;
  final Set<Genre> genres;
  final List<String> languages;
  final streams = <StreamVariant>[];

  _ChannelBuilder({
    required this.key,
    required this.name,
    required this.logoUrl,
    required this.genres,
    required this.languages,
  });

  Channel build(Map<Genre, int> ranks) {
    // Try streams that are reachable from anywhere first, best quality first.
    final ordered = [...streams]..sort((a, b) {
        if (a.geoBlocked != b.geoBlocked) return a.geoBlocked ? 1 : -1;
        if (a.notAlwaysOn != b.notAlwaysOn) return a.notAlwaysOn ? 1 : -1;
        return b.lines.compareTo(a.lines);
      });
    return Channel(
      key: key,
      name: name,
      logoUrl: logoUrl,
      streams: ordered,
      // A channel listed under a genre in the popularity list belongs to it.
      genres: {...genres, ...ranks.keys},
      languages: languages,
      ranks: ranks,
    );
  }
}
