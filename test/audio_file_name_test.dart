import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_media_player/src/core/utils/file_name_utils.dart';

void main() {
  test('recognizes Telegram audio file names', () {
    expect(FileNameUtils.isSupportedAudioName('Example Track.mp3'), isTrue);
    expect(FileNameUtils.isSupportedAudioName('lossless.FLAC'), isTrue);
    expect(FileNameUtils.isSupportedAudioName('voice.opus'), isTrue);
    expect(FileNameUtils.isSupportedAudioName('cover.jpg'), isFalse);
    expect(FileNameUtils.isSupportedAudioName('ignored-video.mp4'), isFalse);
  });
}
