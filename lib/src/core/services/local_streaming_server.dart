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
        ..set('content-disposition', 'inline');
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
    } on SocketException {
      await _closeQuietly(request.response);
    } on HttpException {
      await _closeQuietly(request.response);
    } on FormatException {
      await _sendError(
        request.response,
        HttpStatus.requestedRangeNotSatisfiable,
        'The requested media range is unavailable.',
      );
    } on AppException catch (error) {
      await _sendError(
        request.response,
        _statusForError(error),
        error.message ?? 'Unable to stream this media.',
      );
    } catch (_) {
      await _sendError(
        request.response,
        HttpStatus.internalServerError,
        'Unable to stream this media.',
      );
    }
  }

  Future<void> _sendError(
    HttpResponse response,
    int statusCode,
    String message,
  ) async {
    try {
      response.statusCode = statusCode;
      response.write(message);
    } catch (_) {
      // Headers may already be committed for an interrupted range response.
    }
    await _closeQuietly(response);
  }

  Future<void> _closeQuietly(HttpResponse response) async {
    try {
      await response.close();
    } catch (_) {
      // The player may close an obsolete range request after seeking.
    }
  }

  Future<void> _writeRange(HttpResponse response, MediaItem item, ByteRange range) async {
    // Use fewer native/Dart round trips while maintaining prompt flushes on a
    // slower connection. The concurrent TDLib whole-file request takes over
    // once enough data is available for direct file playback.
    const chunkSize = 512 * 1024;
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
