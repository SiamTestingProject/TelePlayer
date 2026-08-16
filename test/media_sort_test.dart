import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_media_player/src/features/library/models/media_item.dart';

void main() {
  test('sorts explicitly by newest message or alphabetically', () {
    const olderAlpha = MediaItem(
      id: 'older-alpha',
      chatId: -1001,
      messageId: 10,
      fileId: 1,
      title: 'alpha',
      fileName: 'alpha.mp3',
      mimeType: 'audio/mpeg',
      size: 100,
      kind: MediaKind.audio,
      dateEpochSeconds: 100,
    );
    const newerZulu = MediaItem(
      id: 'newer-zulu',
      chatId: -1001,
      messageId: 20,
      fileId: 2,
      title: 'Zulu',
      fileName: 'zulu.mp3',
      mimeType: 'audio/mpeg',
      size: 100,
      kind: MediaKind.audio,
      dateEpochSeconds: 200,
    );

    final newest = <MediaItem>[olderAlpha, newerZulu]
      ..sort(
        (left, right) =>
            compareMediaItems(left, right, MediaSortOrder.newest),
      );
    final alphabetical = <MediaItem>[olderAlpha, newerZulu]
      ..sort(
        (left, right) =>
            compareMediaItems(left, right, MediaSortOrder.alphabetical),
      );

    expect(
      newest.map((item) => item.id).toList(),
      <String>['newer-zulu', 'older-alpha'],
    );
    expect(
      alphabetical.map((item) => item.id).toList(),
      <String>['older-alpha', 'newer-zulu'],
    );
  });
}
