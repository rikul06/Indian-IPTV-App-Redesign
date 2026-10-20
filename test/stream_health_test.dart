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

    StreamHealth.markBad('http://b/other');
    expect(StreamHealth.isBad('http://b/other'), isTrue);
  });

  test('forgets failures after 12 hours', () async {
    final old = DateTime.now()
        .subtract(const Duration(hours: 13))
        .millisecondsSinceEpoch;
    SharedPreferences.setMockInitialValues({
      'bad_streams': ['$old|http://c/old'],
    });
    await StreamHealth.load();
    expect(StreamHealth.isBad('http://c/old'), isFalse);
  });
}
