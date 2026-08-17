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
      inlineThumbnailBase64: 'AQIDBA==',
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
    expect(
      restored.single.inlineThumbnailBase64,
      item.inlineThumbnailBase64,
    );
    expect(restored.single.parts, hasLength(1));
    expect(restored.single.parts.single.partNumber, 1);
    expect(thumbnail, <int>[1, 2, 3, 4]);
  });

  test('deduplicates the same Telegram message before restoring the catalog', () async {
    final directory = await Directory.systemTemp.createTemp(
      'teleplayer-catalog-dedup-test-',
    );
    final cache = ChannelCatalogCache(
      directoryProvider: () async => directory,
    );
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    const stale = MediaItem(
      id: '-1001:50:4',
      chatId: -1001,
      messageId: 50,
      fileId: 4,
      title: 'Duplicate Track',
      fileName: 'duplicate.flac',
      mimeType: 'audio/flac',
      size: 1000,
      kind: MediaKind.audio,
    );
    const current = MediaItem(
      id: '-1001:50:9',
      chatId: -1001,
      messageId: 50,
      fileId: 9,
      title: 'Duplicate Track',
      fileName: 'duplicate.flac',
      mimeType: 'audio/flac',
      size: 1000,
      kind: MediaKind.audio,
      thumbnailFileId: 10,
    );

    await cache.writeItems(const <MediaItem>[stale, current]);
    final restored = await cache.readItems();

    expect(restored, hasLength(1));
    expect(restored.single.messageId, 50);
    expect(restored.single.fileId, 9);
    expect(restored.single.thumbnailFileId, 10);
  });

  test('persists fully scanned channel markers for incremental sync', () async {
    final directory = await Directory.systemTemp.createTemp(
      'teleplayer-catalog-sync-state-test-',
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
      id: '-1001:60:77',
      chatId: -1001,
      messageId: 60,
      fileId: 77,
      title: 'Synced Track',
      fileName: 'synced.flac',
      mimeType: 'audio/flac',
      size: 1000,
      kind: MediaKind.audio,
    );

    await cache.writeItems(
      const <MediaItem>[item],
      fullyScannedChannels: const <int>{-1001},
    );

    expect(await cache.readFullyScannedChannels(), contains(-1001));
  });


  test('keeps high-resolution artwork when TDLib file id changes after restart', () async {
    final directory = await Directory.systemTemp.createTemp(
      'teleplayer-artwork-stable-key-test-',
    );
    final cache = ChannelCatalogCache(
      directoryProvider: () async => directory,
    );
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    const original = MediaItem(
      id: '-1001:70:77',
      chatId: -1001,
      messageId: 70,
      fileId: 77,
      title: 'Stable Artwork Track',
      fileName: 'stable.flac',
      mimeType: 'audio/flac',
      size: 1000,
      kind: MediaKind.audio,
    );
    const reopened = MediaItem(
      id: '-1001:70:991',
      chatId: -1001,
      messageId: 70,
      fileId: 991,
      title: 'Stable Artwork Track',
      fileName: 'stable.flac',
      mimeType: 'audio/flac',
      size: 1000,
      kind: MediaKind.audio,
    );
    final artwork = Uint8List.fromList(<int>[9, 8, 7, 6, 5]);

    await cache.writeArtwork(original, artwork);

    expect(
      await cache.readArtwork(reopened),
      orderedEquals(artwork),
    );
  });

  test('migrates legacy file-id artwork cache to the stable message key', () async {
    final directory = await Directory.systemTemp.createTemp(
      'teleplayer-artwork-legacy-migration-test-',
    );
    final cache = ChannelCatalogCache(
      directoryProvider: () async => directory,
    );
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    const reopened = MediaItem(
      id: '-1001:80:999',
      chatId: -1001,
      messageId: 80,
      fileId: 999,
      title: 'Migrated Artwork Track',
      fileName: 'migrated.flac',
      mimeType: 'audio/flac',
      size: 1000,
      kind: MediaKind.audio,
    );
    final legacyDirectory = Directory(
      '${directory.path}${Platform.pathSeparator}channel-catalog-cache'
      '${Platform.pathSeparator}artwork-v3',
    );
    await legacyDirectory.create(recursive: true);
    final legacyArtwork = Uint8List.fromList(<int>[1, 3, 5, 7, 9, 11]);
    await File(
      '${legacyDirectory.path}${Platform.pathSeparator}-1001_80_77.artwork',
    ).writeAsBytes(legacyArtwork, flush: true);

    expect(
      await cache.readArtwork(reopened),
      orderedEquals(legacyArtwork),
    );
    expect(
      await File(
        '${legacyDirectory.path}${Platform.pathSeparator}-1001_80.artwork',
      ).exists(),
      isTrue,
    );
  });

}
