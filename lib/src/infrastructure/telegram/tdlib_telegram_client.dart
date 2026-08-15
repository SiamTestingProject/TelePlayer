import 'dart:async';
import 'dart:io' as io;
import 'dart:math';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:tdlib/td_api.dart' as td;

import '../../core/errors/app_exception.dart';
import '../../core/utils/file_name_utils.dart';
import '../../features/auth/models/auth_models.dart';
import '../../features/library/models/media_item.dart';
import '../../features/settings/models/app_settings.dart';
import 'tdlib_gateway.dart';
import 'telegram_client.dart';

class TdlibTelegramClient implements TelegramClient {
  TdlibTelegramClient(this._gateway);

  final TdlibGateway _gateway;
  final _authSteps = StreamController<AuthStep>.broadcast();

  AppSettings? _settings;
  StreamSubscription<Map<String, dynamic>>? _updatesSub;

  @override
  Stream<AuthStep> get authSteps => _authSteps.stream;

  @override
  Future<void> initialize(AppSettings settings) async {
    if (!settings.hasTelegramConfiguration) {
      _emitAuth(const AuthStep(AuthStepKind.needsConfiguration));
      throw const AppException(AppErrorCode.missingConfiguration);
    }
    _settings = settings;
    await _updatesSub?.cancel();
    _updatesSub = _gateway.updates.listen(_handleUpdate);
    await _gateway.initialize(tdjsonPath: settings.windowsTdjsonPath);
  }

  @override
  Future<void> submitPhoneNumber(String phoneNumber) {
    return _gateway.send(td.SetAuthenticationPhoneNumber(phoneNumber: phoneNumber));
  }

  @override
  Future<void> submitCode(String code) {
    return _gateway.send(td.CheckAuthenticationCode(code: code));
  }

  @override
  Future<void> submitPassword(String password) {
    return _gateway.send(td.CheckAuthenticationPassword(password: password));
  }

  @override
  Future<List<MediaItem>> listRecentMedia({
    required List<int> channelIds,
    required int limitPerChannel,
  }) async {
    final items = <MediaItem>[];
    for (final chatId in channelIds) {
      final response = await _gateway.send(
        td.GetChatHistory(
          chatId: chatId,
          fromMessageId: 0,
          offset: 0,
          limit: limitPerChannel.clamp(1, 100).toInt(),
          onlyLocal: false,
        ),
      );
      final messages = (response['messages'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map>()
          .map((message) => Map<String, dynamic>.from(message));
      for (final message in messages) {
        final item = _mediaFromMessage(chatId, message);
        if (item != null) {
          items.add(item);
        }
      }
    }
    return _mergeSplitParts(items);
  }

  @override
  Future<MediaItem> refreshMedia(MediaItem item) async {
    final response = await _gateway.send(
      td.GetMessage(chatId: item.chatId, messageId: item.messageId),
    );
    final refreshed = _mediaFromMessage(item.chatId, response);
    if (refreshed == null) {
      throw const AppException(AppErrorCode.invalidMedia);
    }
    return refreshed;
  }

  @override
  Future<Uint8List> readFileRange(MediaItem item, int start, int end) async {
    final target = _partForRange(item, start);
    final localStart = target == null ? start : start - _cumulativeOffset(item, target);
    final localEnd = target == null ? end : min(target.size - 1, end - _cumulativeOffset(item, target));
    final fileId = target?.fileId ?? item.fileId;
    final limit = localEnd - localStart + 1;
    final response = await _gateway.send(
      td.DownloadFile(
        fileId: fileId,
        priority: 30,
        offset: localStart,
        limit: limit,
        synchronous: true,
      ),
      timeout: const Duration(minutes: 3),
    );
    final file = _extractFile(response);
    final path = file.localPath;
    if (path == null || path.isEmpty || !await io.File(path).exists()) {
      throw const AppException(AppErrorCode.cacheUnavailable);
    }
    final handle = await io.File(path).open();
    try {
      await handle.setPosition(localStart);
      return Uint8List.fromList(await handle.read(limit));
    } finally {
      await handle.close();
    }
  }

  @override
  Future<Uint8List?> loadThumbnail(MediaItem item) async {
    final thumbnailId = item.thumbnailFileId;
    if (thumbnailId == null) {
      return null;
    }
    final response = await _gateway.send(
      td.DownloadFile(
        fileId: thumbnailId,
        priority: 20,
        offset: 0,
        limit: 0,
        synchronous: true,
      ),
      timeout: const Duration(seconds: 45),
    );
    final file = _extractFile(response);
    final path = file.localPath;
    if (path == null || path.isEmpty || !await io.File(path).exists()) {
      throw const AppException(AppErrorCode.missingThumbnail);
    }
    return io.File(path).readAsBytes();
  }

  void _handleUpdate(Map<String, dynamic> update) {
    if (update['@type'] != 'updateAuthorizationState') {
      return;
    }
    final state = Map<String, dynamic>.from(update['authorization_state'] as Map);
    switch (state['@type']) {
      case 'authorizationStateWaitTdlibParameters':
        unawaited(_sendTdlibParameters());
        break;
      case 'authorizationStateWaitPhoneNumber':
        _emitAuth(const AuthStep(AuthStepKind.needsPhone));
        break;
      case 'authorizationStateWaitCode':
        _emitAuth(const AuthStep(AuthStepKind.needsCode));
        break;
      case 'authorizationStateWaitPassword':
        _emitAuth(const AuthStep(AuthStepKind.needsPassword));
        break;
      case 'authorizationStateReady':
        _emitAuth(const AuthStep(AuthStepKind.ready));
        break;
      case 'authorizationStateClosed':
      case 'authorizationStateClosing':
      case 'authorizationStateLoggingOut':
        _emitAuth(const AuthStep(AuthStepKind.expired));
        break;
      default:
        _emitAuth(const AuthStep(AuthStepKind.unknown));
    }
  }

  Future<void> _sendTdlibParameters() async {
    final settings = _settings;
    if (settings == null || !settings.hasTelegramConfiguration) {
      _emitAuth(const AuthStep(AuthStepKind.needsConfiguration));
      return;
    }
    final baseDir = await getApplicationSupportDirectory();
    final databaseDir = io.Directory('${baseDir.path}/tdlib-db');
    final filesDir = io.Directory('${baseDir.path}/tdlib-files');
    await databaseDir.create(recursive: true);
    await filesDir.create(recursive: true);
    await _gateway.send(
      td.SetTdlibParameters(
        useTestDc: false,
        databaseDirectory: databaseDir.path,
        filesDirectory: filesDir.path,
        databaseEncryptionKey: settings.apiHash ?? '',
        useFileDatabase: true,
        useChatInfoDatabase: true,
        useMessageDatabase: true,
        useSecretChats: false,
        apiId: settings.apiId!,
        apiHash: settings.apiHash!,
        systemLanguageCode: 'en',
        deviceModel: _deviceModel(),
        systemVersion: _systemVersion(),
        applicationVersion: '1.0.0',
        enableStorageOptimizer: true,
        ignoreFileNames: false,
      ),
    );
  }

  String _deviceModel() {
    if (io.Platform.isWindows) {
      return 'Windows PC';
    }
    if (io.Platform.isAndroid) {
      return 'Flutter Android';
    }
    return 'Flutter ${io.Platform.operatingSystem}';
  }

  String _systemVersion() {
    if (io.Platform.isWindows) {
      return io.Platform.operatingSystemVersion;
    }
    if (io.Platform.isAndroid) {
      return 'Android';
    }
    return io.Platform.operatingSystemVersion;
  }

  MediaItem? _mediaFromMessage(int chatId, Map<String, dynamic> message) {
    final content = message['content'];
    if (content is! Map) {
      return null;
    }
    final contentMap = Map<String, dynamic>.from(content);
    final contentType = contentMap['@type']?.toString();
    Map<String, dynamic>? media;
    MediaKind kind;
    if (contentType == 'messageVideo') {
      media = _asMap(contentMap['video']);
      kind = MediaKind.video;
    } else if (contentType == 'messageDocument') {
      media = _asMap(contentMap['document']);
      kind = MediaKind.document;
    } else {
      return null;
    }
    if (media == null) {
      throw const AppException(AppErrorCode.deletedMedia);
    }
    final file = _asMap(media['video']) ?? _asMap(media['document']);
    if (file == null) {
      return null;
    }
    final fileName = (media['file_name'] ?? 'Telegram media').toString();
    final mimeType = (media['mime_type'] ?? 'application/octet-stream').toString();
    if (!FileNameUtils.isSupportedVideoName(fileName) && !mimeType.startsWith('video/')) {
      return null;
    }
    final fileId = int.tryParse(file['id']?.toString() ?? '') ?? 0;
    final fileSize = int.tryParse(file['size']?.toString() ?? '') ??
        int.tryParse(file['expected_size']?.toString() ?? '') ??
        0;
    final split = FileNameUtils.parseSplitInfo(fileName);
    final id = '$chatId:${message['id'] ?? 0}:$fileId';
    return MediaItem(
      id: id,
      chatId: chatId,
      messageId: int.tryParse(message['id']?.toString() ?? '') ?? 0,
      fileId: fileId,
      title: split?.displayName ?? fileName,
      fileName: fileName,
      mimeType: mimeType,
      size: fileSize,
      kind: split == null ? kind : MediaKind.splitVideo,
      durationSeconds: int.tryParse(media['duration']?.toString() ?? ''),
      thumbnailFileId: _thumbnailFileId(media),
      localPath: _asMap(file['local'])?['path']?.toString(),
    );
  }

  List<MediaItem> _mergeSplitParts(List<MediaItem> items) {
    final grouped = <String, List<MediaItem>>{};
    final normal = <MediaItem>[];
    for (final item in items) {
      final split = FileNameUtils.parseSplitInfo(item.fileName);
      if (split == null) {
        normal.add(item);
      } else {
        grouped.putIfAbsent(split.groupKey, () => <MediaItem>[]).add(item);
      }
    }
    final merged = <MediaItem>[...normal];
    for (final entry in grouped.entries) {
      final sorted = [...entry.value]
        ..sort((a, b) {
          final left = FileNameUtils.parseSplitInfo(a.fileName)?.partNumber ?? 0;
          final right = FileNameUtils.parseSplitInfo(b.fileName)?.partNumber ?? 0;
          return left.compareTo(right);
        });
      final first = sorted.first;
      final parts = sorted.map((item) {
        final split = FileNameUtils.parseSplitInfo(item.fileName);
        return MediaPart(
          chatId: item.chatId,
          messageId: item.messageId,
          fileId: item.fileId,
          partNumber: split?.partNumber ?? 0,
          size: item.size,
        );
      }).toList(growable: false);
      merged.add(first.copyWith(
        size: parts.fold<int>(0, (total, part) => total + part.size),
        parts: parts,
      ));
    }
    merged.sort((a, b) => b.messageId.compareTo(a.messageId));
    return merged;
  }

  _TdFile _extractFile(Map<String, dynamic> json) {
    if (json['@type'] != 'file') {
      throw AppException(AppErrorCode.telegramApi, message: json['message']?.toString());
    }
    final local = _asMap(json['local']);
    return _TdFile(localPath: local?['path']?.toString());
  }

  MediaPart? _partForRange(MediaItem item, int absoluteStart) {
    var offset = 0;
    for (final part in item.parts) {
      if (absoluteStart >= offset && absoluteStart < offset + part.size) {
        return part;
      }
      offset += part.size;
    }
    return null;
  }

  int _cumulativeOffset(MediaItem item, MediaPart target) {
    var offset = 0;
    for (final part in item.parts) {
      if (part.fileId == target.fileId && part.messageId == target.messageId) {
        return offset;
      }
      offset += part.size;
    }
    return 0;
  }

  int? _thumbnailFileId(Map<String, dynamic> media) {
    final thumbnail = _asMap(media['thumbnail']);
    final file = _asMap(thumbnail?['file']);
    return int.tryParse(file?['id']?.toString() ?? '');
  }

  Map<String, dynamic>? _asMap(Object? value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return null;
  }

  void _emitAuth(AuthStep step) {
    if (!_authSteps.isClosed) {
      _authSteps.add(step);
    }
  }

  @override
  Future<void> close() async {
    await _updatesSub?.cancel();
    await _authSteps.close();
    await _gateway.close();
  }
}

class _TdFile {
  const _TdFile({this.localPath});

  final String? localPath;
}
