import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_media_player/src/core/utils/file_name_utils.dart';

void main() {
  test('detects Telegram split media suffixes', () {
    final info = FileNameUtils.parseSplitInfo('Movie.Name.2026.1080p.mkv.002');
    expect(info, isNotNull);
    expect(info!.partNumber, 2);
    expect(info.displayName, 'Movie.Name.2026.1080p.mkv');
  });

  test('ignores ordinary multipart-looking names', () {
    final info = FileNameUtils.parseSplitInfo('Movie.Part.02.mkv');
    expect(info, isNull);
  });

  test('recognizes supported direct video names', () {
    expect(FileNameUtils.isSupportedVideoName('clip.webm'), isTrue);
    expect(FileNameUtils.isSupportedVideoName('archive.zip'), isFalse);
  });

  test('recognizes Telegram audio file names', () {
    expect(FileNameUtils.isSupportedAudioName('Example Track.mp3'), isTrue);
    expect(FileNameUtils.isSupportedAudioName('lossless.FLAC'), isTrue);
    expect(FileNameUtils.isSupportedAudioName('cover.jpg'), isFalse);
  });
}
