import 'package:flutter_test/flutter_test.dart';
import 'package:ip_tv/services/stream_health.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('remembers failed streams and the source that last worked', () async {
    SharedPreferences.setMockInitialValues({
      'bad_streams': ['${DateTime.now().millisecondsSinceEpoch}|http://a/dead'],
      'good_streams': ['aajtak|http://a/good'],
    });
    await StreamHealth.load();
    expect(StreamHealth.isBad('http://a/dead'), isTrue);
    expect(StreamHealth.isBad('http://a/good'), isFalse);
    expect(StreamHealth.lastGood('aajtak'), 'http://a/good');

    StreamHealth.markGood('aajtak', 'http://a/dead');
    expect(StreamHealth.isBad('http://a/dead'), isFalse);
    expect(StreamHealth.lastGood('aajtak'), 'http://a/dead');
  });

  test('a failed stream stays marked until it works again', () async {
    final weekAgo =
        DateTime.now().subtract(const Duration(days: 7)).millisecondsSinceEpoch;
    SharedPreferences.setMockInitialValues({
      'bad_streams': ['$weekAgo|http://c/old'],
    });
    await StreamHealth.load();
    expect(StreamHealth.isBad('http://c/old'), isTrue);
  });

  group('source order (Aaj Tak with 3 sources, source 1 failed last time)', () {
    const urls = ['http://s/1', 'http://s/2', 'http://s/3'];

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await StreamHealth.load();
      StreamHealth.markGood('x', 'http://s/2');
      StreamHealth.markGood('x', 'http://s/3');
      StreamHealth.markBad('http://s/1');
    });

    test('opens on source 2', () {
      expect(StreamHealth.firstSource(urls), 1);
    });

    test('opens on the source that worked last time', () {
      expect(StreamHealth.firstSource(urls, lastGood: 'http://s/3'), 2);
    });

    test('source 2 fails: tries 3, then goes back to 1, then gives up', () {
      expect(StreamHealth.nextSource(urls, 1, {1}), 2);
      expect(StreamHealth.nextSource(urls, 2, {1, 2}), 0);
      expect(StreamHealth.nextSource(urls, 0, {0, 1, 2}), isNull);
    });

    test('sources that failed last time come after untried ones', () {
      // From source 3, source 1 is next in the circle but failed last time,
      // so source 2 goes first.
      expect(StreamHealth.nextSource(urls, 2, {2}), 1);
    });

    test('every source failed last time: opens on the first', () {
      StreamHealth.markBad('http://s/2');
      StreamHealth.markBad('http://s/3');
      expect(StreamHealth.firstSource(urls), 0);
    });
  });
}
