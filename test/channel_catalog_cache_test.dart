import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_media_player/src/features/library/data/channel_catalog_cache.dart';
import 'package:telegram_media_player/src/features/library/models/media_item.dart';

void main() {
  test('persists complete media metadata and thumbnail bytes', () async {
    final directory = await Directory.systemTemp.createTemp(
      'teleplayer-catalog-cache-test-',
    );
    final cache = ChannelCatalogCache(
      directoryProvider: () async => directory,
    );
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    const item = MediaItem(
      id: '-1001:42:77',
      chatId: -1001,
      messageId: 42,
      fileId: 77,
      title: 'Lossless Track',
      fileName: 'Lossless Track.flac',
      mimeType: 'audio/flac',
      size: 44200000,
      kind: MediaKind.audio,
      dateEpochSeconds: 123456,
      artist: 'Example Artist',
      durationSeconds: 178,
      thumbnailFileId: 88,
      parts: <MediaPart>[
        MediaPart(
          chatId: -1001,
          messageId: 42,
          fileId: 77,
          partNumber: 1,
          size: 44200000,
        ),
      ],
    );

    await cache.writeItems(const <MediaItem>[item]);
    await cache.writeThumbnail(88, Uint8List.fromList(<int>[1, 2, 3, 4]));

    final restored = await cache.readItems();
    final thumbnail = await cache.readThumbnail(88);

    expect(restored, hasLength(1));
    expect(restored.single.id, item.id);
    expect(restored.single.title, item.title);
    expect(restored.single.artist, item.artist);
    expect(restored.single.durationSeconds, item.durationSeconds);
    expect(restored.single.dateEpochSeconds, item.dateEpochSeconds);
    expect(restored.single.parts, hasLength(1));
    expect(restored.single.parts.single.partNumber, 1);
    expect(thumbnail, <int>[1, 2, 3, 4]);
  });
}
