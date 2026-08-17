import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../models/media_item.dart';

typedef CacheDirectoryProvider = Future<Directory> Function();

class ChannelCatalogCache {
  static const int _artworkCacheRevision = 3;

  ChannelCatalogCache({CacheDirectoryProvider? directoryProvider})
      : _directoryProvider =
            directoryProvider ?? getApplicationSupportDirectory;

  final CacheDirectoryProvider _directoryProvider;

  Future<List<MediaItem>> readItems() async {
    try {
      final file = await _catalogFile();
      if (!await file.exists()) {
        return const <MediaItem>[];
      }
      final json = jsonDecode(await file.readAsString());
      if (json is! Map || json['items'] is! List) {
        return const <MediaItem>[];
      }
      final items = (json['items'] as List<dynamic>)
          .whereType<Map>()
          .map((item) => MediaItem.fromJson(Map<String, dynamic>.from(item)))
          .where((item) => item.id.isNotEmpty && item.fileId > 0 && item.size > 0);
      return _deduplicateByMessage(items);
    } on FormatException {
      return const <MediaItem>[];
    } on FileSystemException {
      return const <MediaItem>[];
    }
  }

  Future<Set<int>> readFullyScannedChannels({int legacyRecentLimit = 60}) async {
    try {
      final file = await _catalogFile();
      if (!await file.exists()) {
        return <int>{};
      }
      final json = jsonDecode(await file.readAsString());
      if (json is! Map) {
        return <int>{};
      }
      final explicit = json['fullyScannedChannels'];
      if (explicit is List) {
        return explicit
            .map((value) => int.tryParse(value.toString()))
            .whereType<int>()
            .toSet();
      }

      // Legacy TelePlayer builds did not record whether catalog.json came from
      // the lightweight recent scan or the full Cache operation. A channel
      // with more entries than the old recent-scan limit could only have come
      // from a previous full Cache operation, so preserve that work during
      // migration. A recent-only legacy catalog (at most the limit) gets one
      // safe full scan and is then marked.
      final items = await readItems();
      final counts = <int, int>{};
      for (final item in items) {
        counts.update(item.chatId, (value) => value + 1, ifAbsent: () => 1);
      }
      return counts.entries
          .where((entry) => entry.value > legacyRecentLimit)
          .map((entry) => entry.key)
          .toSet();
    } on FormatException {
      return <int>{};
    } on FileSystemException {
      return <int>{};
    }
  }

  Future<void> writeItems(
    List<MediaItem> items, {
    Set<int> fullyScannedChannels = const <int>{},
  }) async {
    final file = await _catalogFile();
    final normalizedItems = _deduplicateByMessage(items);
    final scannedChannels = fullyScannedChannels.toList(growable: false)..sort();
    final payload = <String, dynamic>{
      'version': 3,
      'savedAt': DateTime.now().toUtc().toIso8601String(),
      'fullyScannedChannels': scannedChannels,
      'items': normalizedItems
          .map((item) => item.toJson())
          .toList(growable: false),
    };
    await file.writeAsString(jsonEncode(payload), flush: true);
  }


  List<MediaItem> _deduplicateByMessage(Iterable<MediaItem> source) {
    final byMessage = <String, MediaItem>{};
    for (final item in source) {
      final key = '${item.chatId}:${item.messageId}';
      final existing = byMessage[key];
      if (existing == null || _prefer(item, existing)) {
        byMessage[key] = item;
      }
    }
    final items = byMessage.values.toList()
      ..sort((left, right) => right.messageId.compareTo(left.messageId));
    return items;
  }

  bool _prefer(MediaItem candidate, MediaItem existing) {
    if (candidate.hasThumbnail != existing.hasThumbnail) {
      return candidate.hasThumbnail;
    }
    if ((candidate.localPath?.isNotEmpty ?? false) !=
        (existing.localPath?.isNotEmpty ?? false)) {
      return candidate.localPath?.isNotEmpty ?? false;
    }
    return candidate.fileId >= existing.fileId;
  }

  Future<Uint8List?> readThumbnail(int fileId) async {
    try {
      final file = await _thumbnailFile(fileId);
      if (!await file.exists()) {
        return null;
      }
      final bytes = await file.readAsBytes();
      return bytes.isEmpty ? null : bytes;
    } on FileSystemException {
      return null;
    }
  }

  Future<void> writeThumbnail(int fileId, Uint8List bytes) async {
    if (bytes.isEmpty) {
      return;
    }
    final file = await _thumbnailFile(fileId);
    await file.writeAsBytes(bytes, flush: true);
  }

  Future<Uint8List?> readArtwork(MediaItem item) async {
    try {
      final file = await _artworkFile(item);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        return bytes.isEmpty ? null : bytes;
      }

      // TDLib file IDs are local database identifiers and may change after an
      // app restart/re-login. Older TelePlayer builds included fileId in the
      // artwork filename, so the same Telegram message could no longer find its
      // high-resolution cover after reopening the app. Migrate any legacy
      // <chat>_<message>_<file>.artwork entry to the stable message-based key.
      return await _migrateLegacyArtwork(item, file);
    } on FileSystemException {
      return null;
    }
  }

  Future<void> writeArtwork(MediaItem item, Uint8List bytes) async {
    if (bytes.isEmpty) {
      return;
    }
    final file = await _artworkFile(item);
    await file.writeAsBytes(bytes, flush: true);
  }

  Future<Uint8List?> _migrateLegacyArtwork(
    MediaItem item,
    File stableFile,
  ) async {
    final artwork = await _artworkDirectory();
    final prefix = '${item.chatId}_${item.messageId}_';
    File? bestLegacy;
    var bestLength = 0;

    await for (final entity in artwork.list(followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      final name = entity.path.split(Platform.pathSeparator).last;
      if (!name.startsWith(prefix) || !name.endsWith('.artwork')) {
        continue;
      }
      try {
        final length = await entity.length();
        if (length > bestLength) {
          bestLength = length;
          bestLegacy = entity;
        }
      } on FileSystemException {
        // Ignore a single unreadable legacy entry and keep looking.
      }
    }

    if (bestLegacy == null || bestLength <= 0) {
      return null;
    }

    final bytes = await bestLegacy.readAsBytes();
    if (bytes.isEmpty) {
      return null;
    }
    await stableFile.writeAsBytes(bytes, flush: true);
    return bytes;
  }

  Future<void> clearAll() async {
    final support = await _directoryProvider();
    final directory = Directory(
      '${support.path}${Platform.pathSeparator}channel-catalog-cache',
    );
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  Future<File> _catalogFile() async {
    final directory = await _cacheDirectory();
    return File('${directory.path}${Platform.pathSeparator}catalog.json');
  }

  Future<File> _thumbnailFile(int fileId) async {
    final directory = await _cacheDirectory();
    final thumbnails = Directory(
      '${directory.path}${Platform.pathSeparator}thumbnails-v$_artworkCacheRevision',
    );
    if (!await thumbnails.exists()) {
      await thumbnails.create(recursive: true);
    }
    return File(
      '${thumbnails.path}${Platform.pathSeparator}$fileId.thumbnail',
    );
  }

  Future<File> _artworkFile(MediaItem item) async {
    final artwork = await _artworkDirectory();
    // chatId + messageId is Telegram's stable identity for this song. Never use
    // TDLib fileId here: it can change when TDLib rebuilds its local database,
    // which previously made cached covers appear blurry after an app restart.
    final key = '${item.chatId}_${item.messageId}';
    return File(
      '${artwork.path}${Platform.pathSeparator}$key.artwork',
    );
  }

  Future<Directory> _artworkDirectory() async {
    final directory = await _cacheDirectory();
    final artwork = Directory(
      '${directory.path}${Platform.pathSeparator}artwork-v$_artworkCacheRevision',
    );
    if (!await artwork.exists()) {
      await artwork.create(recursive: true);
    }
    return artwork;
  }

  Future<Directory> _cacheDirectory() async {
    final support = await _directoryProvider();
    final directory = Directory(
      '${support.path}${Platform.pathSeparator}channel-catalog-cache',
    );
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }
}
