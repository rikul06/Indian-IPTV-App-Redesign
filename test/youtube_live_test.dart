import 'package:flutter_test/flutter_test.dart';
import 'package:ip_tv/services/youtube_live.dart';

void main() {
  test('reads the channel id from a channel live link', () {
    expect(
        YoutubeLive.channelId(
            'https://www.youtube.com/channel/UC7wXt18f2iA3EDXeqAVuKng/live'),
        'UC7wXt18f2iA3EDXeqAVuKng');
  });

  test('other links have no channel id', () {
    expect(
        YoutubeLive.channelId('https://www.youtube.com/@aajtak/live'), isNull);
  });

  test('explains why YouTube refused to play', () {
    expect(YoutubeLive.describeError(150), contains('other apps'));
    expect(YoutubeLive.describeError(100), contains('not live'));
  });
}
