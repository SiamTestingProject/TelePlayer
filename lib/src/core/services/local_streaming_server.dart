import 'dart:async';
import 'dart:io';

import '../../features/library/models/media_item.dart';
import '../../infrastructure/telegram/telegram_client.dart';
import '../errors/app_exception.dart';
import '../utils/byte_range.dart';

class LocalStreamingServer {
  LocalStreamingServer(this._telegramClient);

  final TelegramClient _telegramClient;
  final _items = <String, MediaItem>{};
  HttpServer? _server;

  Future<Uri> register(MediaItem item) async {
    await start();
    _items[item.id] = item;
    final port = _server!.port;
    return Uri.parse(
      'http://127.0.0.1:$port/media/${Uri.encodeComponent(item.id)}/${Uri.encodeComponent(item.fileName)}',
    );
  }

  Future<void> start() async {
    if (_server != null) {
      return;
    }
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0, shared: true);
    unawaited(_server!.listen(_handleRequest).asFuture<void>());
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _items.clear();
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      if (request.method != 'GET' && request.method != 'HEAD') {
        request.response.statusCode = HttpStatus.methodNotAllowed;
        await request.response.close();
        return;
      }
      final segments = request.uri.pathSegments;
      if (segments.length < 2 || segments.first != 'media') {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      final id = Uri.decodeComponent(segments[1]);
      final item = _items[id];
      if (item == null) {
        request.response.statusCode = HttpStatus.gone;
        request.response.write('This media link expired. Open the item again.');
        await request.response.close();
        return;
      }
      final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
      final range = ByteRange.parse(rangeHeader, item.size);
      final rangeWasRequested = rangeHeader?.trim().isNotEmpty == true;
      request.response.persistentConnection = true;
      request.response.headers
        ..set(HttpHeaders.contentTypeHeader, item.mimeType)
        ..set('accept-ranges', 'bytes')
        ..set(HttpHeaders.contentLengthHeader, range.length)
        ..set(HttpHeaders.cacheControlHeader, 'no-store')
        ..set(HttpHeaders.contentDispositionHeader, 'inline');
      if (rangeWasRequested) {
        request.response.statusCode = HttpStatus.partialContent;
        request.response.headers.set('content-range', range.contentRange);
      }
      if (request.method == 'HEAD') {
        await request.response.close();
        return;
      }
      await _writeRange(request.response, item, range);
      await request.response.close();
    } on FormatException {
      request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      await request.response.close();
    } on AppException catch (error) {
      request.response.statusCode = _statusForError(error);
      request.response.write(error.message ?? 'Unable to stream this media.');
      await request.response.close();
    } catch (_) {
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.write('Unable to stream this media.');
      await request.response.close();
    }
  }

  Future<void> _writeRange(HttpResponse response, MediaItem item, ByteRange range) async {
    // Keep the first reads small so the native player receives enough bytes to
    // identify the codec without waiting for a multi-megabyte Telegram download.
    // Subsequent reads remain sequential and TDLib can reuse its local cache.
    const chunkSize = 128 * 1024;
    var cursor = range.start;
    while (cursor <= range.end) {
      final boundary = _partBoundaryEnd(item, cursor);
      final chunkEnd = [cursor + chunkSize - 1, range.end, boundary].reduce((a, b) => a < b ? a : b);
      final bytes = await _telegramClient.readFileRange(item, cursor, chunkEnd);
      response.add(bytes);
      await response.flush();
      cursor = chunkEnd + 1;
    }
  }

  int _partBoundaryEnd(MediaItem item, int absoluteStart) {
    if (item.parts.isEmpty) {
      return item.size - 1;
    }
    var offset = 0;
    for (final part in item.parts) {
      final end = offset + part.size - 1;
      if (absoluteStart >= offset && absoluteStart <= end) {
        return end;
      }
      offset += part.size;
    }
    return item.size - 1;
  }

  int _statusForError(AppException error) {
    return switch (error.code) {
      AppErrorCode.deletedMessage || AppErrorCode.deletedMedia => HttpStatus.gone,
      AppErrorCode.privateChannel || AppErrorCode.expiredSession => HttpStatus.unauthorized,
      AppErrorCode.invalidMedia || AppErrorCode.unsupportedCodec => HttpStatus.unsupportedMediaType,
      AppErrorCode.rateLimited => HttpStatus.tooManyRequests,
      _ => HttpStatus.serviceUnavailable,
    };
  }
}
