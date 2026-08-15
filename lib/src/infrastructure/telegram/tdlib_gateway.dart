import 'dart:async';
import 'dart:io' as io;

import 'package:tdlib/td_api.dart';
import 'package:tdlib/td_client.dart';
import 'package:tdlib/tdlib.dart';

import '../../core/errors/app_exception.dart';

class TdlibGateway {
  final _updates = StreamController<Map<String, dynamic>>.broadcast();
  final _responses = <String, Completer<Map<String, dynamic>>>{};

  int? _clientId;
  Timer? _pollTimer;
  int _nextExtra = 0;

  Stream<Map<String, dynamic>> get updates => _updates.stream;
  int get clientId => _clientId ?? (throw StateError('TDLib has not been initialized.'));

  Future<void> initialize({String? tdjsonPath}) async {
    if (_clientId != null) {
      return;
    }
    final libraryPath = _resolveLibraryPath(tdjsonPath);
    await TdPlugin.initialize(libraryPath);
    _clientId = tdJsonClientCreate();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 100), (_) => _drainUpdates());
  }

  String? _resolveLibraryPath(String? tdjsonPath) {
    final configured = tdjsonPath?.trim();
    if (configured != null && configured.isNotEmpty) {
      return configured;
    }
    if (io.Platform.isWindows) {
      return 'tdjson.dll';
    }
    return null;
  }

  Future<Map<String, dynamic>> send(
    TdFunction request, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    await initialize();
    final extra = 'request-${_nextExtra++}';
    final completer = Completer<Map<String, dynamic>>();
    _responses[extra] = completer;
    tdJsonClientSend(clientId, request, extra);
    final response = await completer.future.timeout(timeout, onTimeout: () {
      _responses.remove(extra);
      throw const AppException(
        AppErrorCode.telegramApi,
        message: 'Telegram did not respond in time.',
      );
    });
    _throwIfError(response);
    return response;
  }

  void _drainUpdates() {
    if (_clientId == null) {
      return;
    }
    while (true) {
      final object = tdJsonClientReceive(clientId, 0.01);
      if (object == null) {
        break;
      }
      final json = Map<String, dynamic>.from(object.toJson());
      final extra = json['@extra']?.toString();
      if (extra != null && _responses.containsKey(extra)) {
        final completer = _responses.remove(extra)!;
        if (!completer.isCompleted) {
          completer.complete(json);
        }
      } else if (!_updates.isClosed) {
        _updates.add(json);
      }
    }
  }

  void _throwIfError(Map<String, dynamic> response) {
    if (response['@type'] != 'error') {
      return;
    }
    final message = response['message']?.toString() ?? 'Telegram returned an error.';
    final code = int.tryParse(response['code']?.toString() ?? '');
    if (message.toUpperCase().contains('FLOOD_WAIT')) {
      final seconds = int.tryParse(RegExp(r'\d+').firstMatch(message)?.group(0) ?? '');
      throw AppException(
        AppErrorCode.rateLimited,
        message: message,
        retryAfter: seconds == null ? null : Duration(seconds: seconds),
      );
    }
    if (code == 401 || message.toLowerCase().contains('unauthorized')) {
      throw AppException(AppErrorCode.expiredSession, message: message);
    }
    if (code == 404 || message.toLowerCase().contains('not found')) {
      throw AppException(AppErrorCode.deletedMessage, message: message);
    }
    throw AppException(AppErrorCode.telegramApi, message: message);
  }

  Future<void> close() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    final id = _clientId;
    _clientId = null;
    if (id != null) {
      tdJsonClientDestroy(id);
    }
    for (final completer in _responses.values) {
      if (!completer.isCompleted) {
        completer.completeError(
          const AppException(AppErrorCode.expiredSession, message: 'TDLib client closed.'),
        );
      }
    }
    _responses.clear();
    await _updates.close();
  }
}
