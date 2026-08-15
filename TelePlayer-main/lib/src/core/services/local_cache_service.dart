import 'dart:io';

import 'package:path_provider/path_provider.dart';

class LocalCacheService {
  Future<Directory> cacheDirectory() async {
    final directory = await getTemporaryDirectory();
    final cache = Directory('${directory.path}/telegram-media-player');
    if (!await cache.exists()) {
      await cache.create(recursive: true);
    }
    return cache;
  }

  Future<int> sizeBytes() async {
    final cache = await cacheDirectory();
    var total = 0;
    await for (final entity in cache.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        total += await entity.length();
      }
    }
    return total;
  }

  Future<void> trimToLimit(int maxBytes) async {
    final cache = await cacheDirectory();
    final files = <File>[];
    await for (final entity in cache.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        files.add(entity);
      }
    }
    files.sort((a, b) => a.statSync().modified.compareTo(b.statSync().modified));
    var currentSize = 0;
    for (final file in files) {
      currentSize += await file.length();
    }
    for (final file in files) {
      if (currentSize <= maxBytes) {
        break;
      }
      final length = await file.length();
      await file.delete();
      currentSize -= length;
    }
  }
}
