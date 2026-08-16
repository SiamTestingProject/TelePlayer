import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../models/media_item.dart';

typedef CacheDirectoryProvider = Future<Directory> Function();

class ChannelCatalogCache {
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
      return (json['items'] as List<dynamic>)
          .whereType<Map>()
          .map((item) => MediaItem.fromJson(Map<String, dynamic>.from(item)))
          .where((item) => item.id.isNotEmpty && item.fileId > 0 && item.size > 0)
          .toList(growable: false);
    } on FormatException {
      return const <MediaItem>[];
    } on FileSystemException {
      return const <MediaItem>[];
    }
  }

  Future<void> writeItems(List<MediaItem> items) async {
    final file = await _catalogFile();
    final payload = <String, dynamic>{
      'version': 1,
      'savedAt': DateTime.now().toUtc().toIso8601String(),
      'items': items.map((item) => item.toJson()).toList(growable: false),
    };
    await file.writeAsString(jsonEncode(payload), flush: true);
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

  Future<File> _catalogFile() async {
    final directory = await _cacheDirectory();
    return File('${directory.path}${Platform.pathSeparator}catalog.json');
  }

  Future<File> _thumbnailFile(int fileId) async {
    final directory = await _cacheDirectory();
    final thumbnails = Directory(
      '${directory.path}${Platform.pathSeparator}thumbnails',
    );
    if (!await thumbnails.exists()) {
      await thumbnails.create(recursive: true);
    }
    return File(
      '${thumbnails.path}${Platform.pathSeparator}$fileId.thumbnail',
    );
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
