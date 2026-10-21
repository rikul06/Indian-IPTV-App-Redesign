import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ip_tv/model/channel_catalog.dart';
import 'package:ip_tv/model/genre.dart';
import 'package:ip_tv/provider/channels_provider.dart';
import 'package:ip_tv/services/stream_health.dart';
import 'package:shared_preferences/shared_preferences.dart';

const playlist = '''#EXTM3U
#EXTINF:-1 tvg-id="9XJhakaas.in@SD",9X Jhakaas (576p)
https://example.com/jhakaas-576/index.m3u8
#EXTINF:-1 tvg-id="9XJhakaas.in@SD",9X Jhakaas (1080p)
https://example.com/jhakaas-1080/index.m3u8
#EXTINF:-1 tvg-id="AajTak.in@SD",Aaj Tak (720p) [Geo-blocked]
https://example.com/aajtak-geo/index.m3u8
#EXTINF:-1 tvg-id="AajTak.in@SD",Aaj Tak (480p)
#EXTVLCOPT:http-referrer=https://www.aajtak.in/
#EXTVLCOPT:http-user-agent=Mozilla/5.0
https://example.com/aajtak/index.m3u8
#EXTINF:-1 tvg-id="" tvg-logo="https://example.com/logo.png" group-title="Movies",Cinema, Classics
https://example.com/classics/index.m3u8
#EXTINF:-1,Pogo Kids TV
https://example.com/pogo/index.m3u8
#EXTINF:-1,Unknown Channel
https://example.com/unknown/index.m3u8
#EXTINF:-1 tvg-id="ZeeTVHD.in@SD",Zee TV HD
https://example.com/zeetv-hd/index.m3u8
#EXTINF:-1 tvg-id="ZeeTV.in@SD",Zee TV (576p)
https://example.com/zeetv/index.m3u8
''';

const popularList = '''# comment
## Entertainment
Zee TV
## News
Aaj Tak
India TV
''';

final meta = <String, dynamic>{
  '9XJhakaas.in': {
    'c': ['music'],
    'lang': ['Marathi'],
    'l': 'https://example.com/9x.png',
  },
  'AajTak.in': {
    'c': ['news'],
    'lang': ['Hindi'],
  },
  'ZeeTVHD.in': {
    'c': ['entertainment'],
    'lang': ['Hindi'],
  },
};

void main() {
  final channels = ChannelsProvider.parseM3U(playlist, meta,
      popularity: ChannelsProvider.parsePopularity(popularList));
  final byName = {for (final c in channels) c.name: c};

  test('merges qualities of one channel into a single entry', () {
    expect(channels.map((c) => c.name), [
      'Aaj Tak',
      'Zee TV',
      '9X Jhakaas',
      'Cinema, Classics',
      'Pogo Kids TV',
      'Unknown Channel',
    ]);
    expect(
        byName['9X Jhakaas']!.streams.map((s) => s.quality), ['1080p', '576p']);
  });

  test('adds a YouTube live stream as the first source', () {
    final withYoutube = ChannelsProvider.parseM3U('''$playlist
#EXTINF:-1 tvg-id="AajTak.in" tvg-language="Hindi" group-title="News",Aaj Tak
https://www.youtube.com/@aajtak/live
#EXTINF:-1 tvg-id="DDKisan.in" tvg-language="Hindi",DD Kisan
https://www.youtube.com/@DDKisan/live
''', meta);
    final aajTak = withYoutube.firstWhere((c) => c.name == 'Aaj Tak');
    expect(aajTak.streams.first.isYoutube, isTrue);
    expect(aajTak.streams.first.label, 'YouTube');
    expect(aajTak.streams.skip(1).any((s) => s.isYoutube), isFalse);
    final kisan = withYoutube.firstWhere((c) => c.name == 'DD Kisan');
    expect(kisan.languages, ['Hindi']);
  });

  test('the bundled YouTube list parses', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final text = await rootBundle.loadString(ChannelsProvider.youtubeLiveAsset);
    final list = ChannelsProvider.parseM3U(text, const {});
    expect(list.length, greaterThan(20));
    expect(list.every((c) => c.streams.single.isYoutube), isTrue);
  });

  test('merges the SD and HD versions of a channel', () {
    final zee = byName['Zee TV']!;
    expect(zee.streams.map((s) => s.quality), ['HD', '576p']);
    expect(zee.isHd, isTrue);
  });

  test('sorts popular channels first, top of each genre before the rest', () {
    expect(byName['Zee TV']!.ranks, {Genre.entertainment: 0});
    expect(byName['Aaj Tak']!.ranks, {Genre.news: 0});
    expect(byName['9X Jhakaas']!.ranks, isEmpty);
    expect(ChannelCatalog(channels).popular().map((c) => c.name),
        ['Zee TV', 'Aaj Tak']);
  });

  test('tries streams that are not geo-blocked first', () {
    final aajTak = byName['Aaj Tak']!;
    expect(aajTak.streams.first.url, 'https://example.com/aajtak/index.m3u8');
    expect(aajTak.streams.last.geoBlocked, isTrue);
    expect(aajTak.streams.first.headers,
        {'Referer': 'https://www.aajtak.in/', 'User-Agent': 'Mozilla/5.0'});
    expect(aajTak.streams.last.headers, isEmpty);
  });

  test('takes genre, language and logo from channel metadata', () {
    final jhakaas = byName['9X Jhakaas']!;
    expect(jhakaas.genres, {Genre.music});
    expect(jhakaas.languages, ['Marathi']);
    expect(jhakaas.logoUrl, 'https://example.com/9x.png');
  });

  test('uses group-title and tvg-logo from the playlist', () {
    final classics = byName['Cinema, Classics']!;
    expect(classics.genres, {Genre.movies});
    expect(classics.logoUrl, 'https://example.com/logo.png');
  });

  test('guesses the genre from the name when nothing else is known', () {
    expect(byName['Pogo Kids TV']!.genres, {Genre.kids});
    expect(byName['Unknown Channel']!.genres, isEmpty);
  });

  test('catalog filters by genre and language', () {
    final catalog = ChannelCatalog(channels);
    expect(catalog.filter(genre: Genre.news).map((c) => c.name), ['Aaj Tak']);
    expect(
        catalog.filter(language: 'Marathi').map((c) => c.name), ['9X Jhakaas']);
    expect(catalog.filter(genre: Genre.others).map((c) => c.name),
        ['Unknown Channel']);
    expect(
        catalog.genresWithChannels(),
        [
          Genre.entertainment,
          Genre.news,
          Genre.kids,
          Genre.music,
          Genre.movies,
          Genre.others,
        ]..sort((a, b) => a.index.compareTo(b.index)));
    expect(catalog.search('hindi').map((c) => c.name), ['Aaj Tak', 'Zee TV']);
    expect(catalog.search('aaj').map((c) => c.name), ['Aaj Tak']);
    expect(catalog.hdOnly.channels.map((c) => c.name),
        ['Aaj Tak', 'Zee TV', '9X Jhakaas']);
  });

  test('channels whose sources all failed go to the end of a genre', () async {
    SharedPreferences.setMockInitialValues({});
    await StreamHealth.load();
    final music = ChannelsProvider.parseM3U('''#EXTM3U
#EXTINF:-1 group-title="Music",Alpha Music
https://example.com/alpha.m3u8
#EXTINF:-1 group-title="Music",Beta Music
https://example.com/beta.m3u8
''', const {});
    final catalog = ChannelCatalog(music);
    expect(catalog.filter(genre: Genre.music).map((c) => c.name),
        ['Alpha Music', 'Beta Music']);

    StreamHealth.markBad('https://example.com/alpha.m3u8');
    expect(catalog.filter(genre: Genre.music).map((c) => c.name),
        ['Beta Music', 'Alpha Music']);
    expect(music.first.notWorking, isTrue);
  });

  group('data files', () {
    const asset = ChannelsProvider.popularityAsset;
    String same(String text) => text;
    Future<String> offline() async => throw Exception('offline');

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
    });

    test('uses the downloaded copy and saves it', () async {
      expect(
          await ChannelsProvider.latestData(asset, same,
              download: () async => 'new'),
          'new');
      expect(await ChannelsProvider.latestData(asset, same, download: offline),
          'new');
    });

    test('ignores a bad download', () async {
      SharedPreferences.setMockInitialValues({asset: 'saved'});
      String rejectBad(String text) =>
          text == 'bad' ? throw const FormatException() : text;
      expect(
          await ChannelsProvider.latestData(asset, rejectBad,
              download: () async => 'bad'),
          'saved');
    });

    test('falls back to the copy built into the app', () async {
      final text =
          await ChannelsProvider.latestData(asset, same, download: offline);
      expect(text, contains('## Entertainment'));
    });
  });
}
