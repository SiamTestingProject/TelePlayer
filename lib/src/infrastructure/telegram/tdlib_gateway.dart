import 'dart:async';
import 'dart:io' as io;

import 'package:tdlib/td_api.dart';
import 'package:tdlib/td_client.dart';
import 'package:tdlib/tdlib.dart';

import '../../core/errors/app_exception.dart';

String? resolveTdjsonLibraryPath({
  required String? configuredPath,
  required String operatingSystem,
}) {
  final configured = configuredPath?.trim();
  if (configured != null && configured.isNotEmpty) {
    return configured;
  }
  return switch (operatingSystem) {
    'android' || 'linux' => 'libtdjson.so',
    'windows' => 'tdjson.dll',
    'macos' => 'libtdjson.dylib',
    _ => null,
  };
}

Map<String, dynamic> tdObjectToJsonWithMetadata(TdObject object) {
  final json = Map<String, dynamic>.from(object.toJson());
  if (object.extra != null) {
    json['@extra'] = object.extra;
  }
  if (object.clientId != null) {
    json['@client_id'] = object.clientId;
  }
  return json;
}

class TdlibGateway {
  final _updates = StreamController<Map<String, dynamic>>.broadcast();
  final _responses = <String, Completer<Map<String, dynamic>>>{};

  int? _clientId;
  Timer? _pollTimer;
  int _nextExtra = 0;

  Stream<Map<String, dynamic>> get updates => _updates.stream;
  bool get isInitialized => _clientId != null;
  int get clientId => _clientId ?? (throw StateError('TDLib has not been initialized.'));

  Future<void> initialize({String? tdjsonPath}) async {
    if (_clientId != null) {
      return;
    }
    final libraryPath = resolveTdjsonLibraryPath(
      configuredPath: tdjsonPath,
      operatingSystem: io.Platform.operatingSystem,
    );
    try {
      await TdPlugin.initialize(libraryPath);
      final createdClientId = tdJsonClientCreate();
      if (createdClientId == 0) {
        throw StateError('TDLib returned an invalid client handle.');
      }
      _clientId = createdClientId;
      _pollTimer = Timer.periodic(
        const Duration(milliseconds: 100),
        (_) => _drainUpdates(),
      );
    } catch (error, stackTrace) {
      _clientId = null;
      _pollTimer?.cancel();
      _pollTimer = null;
      Error.throwWithStackTrace(_initializationException(error), stackTrace);
    }
  }

  Future<Map<String, dynamic>> send(
    TdFunction request, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    await initialize();
    final extra = 'request-${_nextExtra++}';
    final completer = Completer<Map<String, dynamic>>();
    _responses[extra] = completer;
    try {
      tdJsonClientSend(clientId, request, extra);
    } catch (error, stackTrace) {
      _responses.remove(extra);
      final exception = _initializationException(error);
      _invalidateClient(exception, stackTrace, emitError: false);
      Error.throwWithStackTrace(exception, stackTrace);
    }
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
    try {
      while (true) {
        final object = tdJsonClientReceive(clientId, 0.01);
        if (object == null) {
          break;
        }
        final json = tdObjectToJsonWithMetadata(object);
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
    } catch (error, stackTrace) {
      final exception = _initializationException(error);
      _invalidateClient(exception, stackTrace);
    }
  }

  void _invalidateClient(
    AppException exception,
    StackTrace stackTrace, {
    bool emitError = true,
  }) {
    _pollTimer?.cancel();
    _pollTimer = null;
    final failedClientId = _clientId;
    _clientId = null;
    if (failedClientId != null) {
      try {
        tdJsonClientDestroy(failedClientId);
      } catch (_) {
        // The native library is already unusable; cleanup is best effort.
      }
    }
    for (final completer in _responses.values) {
      if (!completer.isCompleted) {
        completer.completeError(exception, stackTrace);
      }
    }
    _responses.clear();
    if (emitError && !_updates.isClosed) {
      _updates.addError(exception, stackTrace);
    }
  }

  AppException _initializationException(Object error) {
    if (error is AppException) {
      return error;
    }
    final message = switch (io.Platform.operatingSystem) {
      'android' =>
        'The bundled Telegram library could not be loaded. Reinstall the APK that matches this device and try again.',
      'windows' =>
        'tdjson.dll could not be loaded. Reinstall the complete Windows package or select a valid TDLib DLL in Settings.',
      _ => 'The Telegram native library could not be loaded on this device.',
    };
    return AppException(
      AppErrorCode.telegramInitialization,
      message: message,
      cause: error,
    );
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
