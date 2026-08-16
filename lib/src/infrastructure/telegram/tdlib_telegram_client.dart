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

typedef ApplicationSupportDirectoryProvider = Future<io.Directory> Function();

class TdlibTelegramClient implements TelegramClient {
  TdlibTelegramClient(
    this._gateway, {
    ApplicationSupportDirectoryProvider? applicationSupportDirectory,
  }) : _applicationSupportDirectory =
            applicationSupportDirectory ?? getApplicationSupportDirectory;

  final TdlibGateway _gateway;
  final ApplicationSupportDirectoryProvider _applicationSupportDirectory;
  final _authSteps = StreamController<AuthStep>.broadcast();
  final _errors = StreamController<AppException>.broadcast();
  final _fileDownloadQueues = <int, Completer<void>>{};

  AppSettings? _settings;
  StreamSubscription<Map<String, dynamic>>? _updatesSub;
  Future<void>? _tdlibParametersFuture;

  @override
  Stream<AuthStep> get authSteps => _authSteps.stream;

  @override
  Stream<AppException> get errors => _errors.stream;

  @override
  Future<void> initialize(AppSettings settings) async {
    if (!settings.hasTelegramConfiguration) {
      _emitAuth(const AuthStep(AuthStepKind.needsConfiguration));
      throw const AppException(AppErrorCode.missingConfiguration);
    }
    _settings = settings;
    await _updatesSub?.cancel();
    _updatesSub = _gateway.updates.listen(
      _handleUpdate,
      onError: (Object error, StackTrace stackTrace) {
        _emitError(_normalizeError(error));
      },
    );
    final startingNewClient = !_gateway.isInitialized;
    await _gateway.initialize(tdjsonPath: settings.windowsTdjsonPath);
    if (startingNewClient) {
      _tdlibParametersFuture = null;
    }
    await _refreshAuthorizationState();
  }

  @override
  Future<void> submitPhoneNumber(String phoneNumber) async {
    final normalized = phoneNumber.replaceAll(RegExp(r'[\s()\-]'), '');
    if (!RegExp(r'^\+[1-9]\d{5,14}$').hasMatch(normalized)) {
      throw const AppException(
        AppErrorCode.telegramAuthFailed,
        message: 'Enter a phone number in international format, for example +15551234567.',
      );
    }
    await _sendAuthenticationRequest(
      td.SetAuthenticationPhoneNumber(phoneNumber: normalized),
    );
  }

  @override
  Future<void> submitCode(String code) async {
    final normalized = code.trim();
    if (normalized.isEmpty) {
      throw const AppException(
        AppErrorCode.telegramAuthFailed,
        message: 'Enter the login code sent by Telegram.',
      );
    }
    await _sendAuthenticationRequest(td.CheckAuthenticationCode(code: normalized));
  }

  @override
  Future<void> submitPassword(String password) async {
    if (password.isEmpty) {
      throw const AppException(
        AppErrorCode.telegramAuthFailed,
        message: 'Enter your Telegram two-step verification password.',
      );
    }
    await _sendAuthenticationRequest(
      td.CheckAuthenticationPassword(password: password),
    );
  }

  Future<void> _sendAuthenticationRequest(td.TdFunction request) async {
    try {
      await _gateway.send(
        request,
        timeout: const Duration(seconds: 45),
      );
      await _refreshAuthorizationState();
    } on AppException catch (error) {
      if (error.code == AppErrorCode.telegramApi ||
          error.code == AppErrorCode.expiredSession) {
        throw AppException(
          AppErrorCode.telegramAuthFailed,
          message: _authenticationErrorMessage(error.message),
          cause: error,
        );
      }
      rethrow;
    }
  }

  String _authenticationErrorMessage(String? message) {
    final normalized = message?.toUpperCase() ?? '';
    if (normalized.contains('PHONE_NUMBER_INVALID')) {
      return 'Telegram rejected this phone number. Check the country code and number.';
    }
    if (normalized.contains('PHONE_NUMBER_BANNED')) {
      return 'Telegram has restricted this phone number from signing in.';
    }
    if (normalized.contains('PHONE_CODE_EXPIRED')) {
      return 'The Telegram login code has expired. Request a new code.';
    }
    if (normalized.contains('PHONE_CODE_INVALID')) {
      return 'The Telegram login code is incorrect.';
    }
    if (normalized.contains('PASSWORD_HASH_INVALID')) {
      return 'The Telegram two-step verification password is incorrect.';
    }
    return message?.trim().isNotEmpty == true
        ? message!.trim()
        : 'Telegram could not continue sign-in. Please try again.';
  }

  @override
  Future<List<MediaItem>> listRecentMedia({
    required List<int> channelIds,
    required int limitPerChannel,
  }) async {
    await _ensureChatsAvailable(channelIds);
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
  Future<List<MediaItem>> listAllMedia({
    required List<int> channelIds,
    required void Function(MediaScanProgress progress) onProgress,
  }) async {
    await _ensureChatsAvailable(channelIds);
    final items = <MediaItem>[];
    var scannedMessages = 0;

    for (final chatId in channelIds) {
      var fromMessageId = 0;
      final seenMessageIds = <int>{};
      while (true) {
        final response = await _gateway.send(
          td.GetChatHistory(
            chatId: chatId,
            fromMessageId: fromMessageId,
            offset: 0,
            limit: 100,
            onlyLocal: false,
          ),
          timeout: const Duration(minutes: 2),
        );
        final messages =
            (response['messages'] as List<dynamic>? ?? const <dynamic>[])
                .whereType<Map>()
                .map((message) => Map<String, dynamic>.from(message))
                .toList(growable: false);
        if (messages.isEmpty) {
          break;
        }

        var newMessages = 0;
        for (final message in messages) {
          final messageId = int.tryParse(message['id']?.toString() ?? '') ?? 0;
          if (messageId <= 0 || !seenMessageIds.add(messageId)) {
            continue;
          }
          newMessages += 1;
          final item = _mediaFromMessage(chatId, message);
          if (item != null) {
            items.add(item);
          }
        }
        scannedMessages += newMessages;
        onProgress(
          MediaScanProgress(
            scannedMessages: scannedMessages,
            mediaCount: items.length,
          ),
        );

        if (newMessages == 0) {
          break;
        }
        final oldestMessageId = messages
            .map((message) =>
                int.tryParse(message['id']?.toString() ?? '') ?? 0)
            .where((id) => id > 0)
            .fold<int>(0, (oldest, id) => oldest == 0 || id < oldest ? id : oldest);
        if (oldestMessageId == 0 || oldestMessageId == fromMessageId) {
          break;
        }
        fromMessageId = oldestMessageId;
      }
    }
    return _mergeSplitParts(items);
  }

  Future<void> _ensureChatsAvailable(List<int> channelIds) async {
    final unresolved = channelIds.toSet();
    await _removeAvailableChats(unresolved);
    if (unresolved.isEmpty) {
      return;
    }

    const chatLists = <td.ChatList?>[
      null,
      td.ChatListArchive(),
    ];
    for (final chatList in chatLists) {
      for (var batch = 0; batch < 20 && unresolved.isNotEmpty; batch++) {
        final response = await _gateway.send(
          td.LoadChats(chatList: chatList, limit: 100),
        );
        await _removeAvailableChats(unresolved);
        if (response['@type'] == 'error') {
          break;
        }
      }
      if (unresolved.isEmpty) {
        return;
      }
    }

    final formattedIds = unresolved.join(', ');
    throw AppException(
      AppErrorCode.privateChannel,
      message: 'Telegram could not find channel ID $formattedIds for this '
          'account. Confirm that the signed-in account has joined the channel '
          'and that the numeric ID is correct.',
    );
  }

  Future<void> _removeAvailableChats(Set<int> unresolved) async {
    for (final chatId in unresolved.toList(growable: false)) {
      try {
        await _gateway.send(td.GetChat(chatId: chatId));
        unresolved.remove(chatId);
      } on AppException catch (error) {
        if (error.code != AppErrorCode.privateChannel) {
          rethrow;
        }
      }
    }
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
    if (item.isSplit) {
      return refreshed.copyWith(size: item.size, parts: item.parts);
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
    return _withFileDownloadLock(fileId, () async {
      final response = await _gateway.send(
        td.DownloadFile(
          fileId: fileId,
          priority: 32,
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
        final bytes = BytesBuilder(copy: false);
        while (bytes.length < limit) {
          final chunk = await handle.read(limit - bytes.length);
          if (chunk.isEmpty) {
            break;
          }
          bytes.add(chunk);
        }
        final result = bytes.takeBytes();
        if (result.length != limit) {
          throw const AppException(
            AppErrorCode.cacheUnavailable,
            message: 'Telegram did not finish preparing the requested media range.',
          );
        }
        return result;
      } finally {
        await handle.close();
      }
    });
  }

  Future<T> _withFileDownloadLock<T>(
    int fileId,
    Future<T> Function() operation,
  ) async {
    final previous = _fileDownloadQueues[fileId]?.future ?? Future<void>.value();
    final turn = Completer<void>();
    _fileDownloadQueues[fileId] = turn;
    await previous;
    try {
      return await operation();
    } finally {
      turn.complete();
      if (identical(_fileDownloadQueues[fileId], turn)) {
        _fileDownloadQueues.remove(fileId);
      }
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
    final rawState = update['authorization_state'];
    if (rawState is! Map) {
      _emitError(
        const AppException(
          AppErrorCode.telegramApi,
          message: 'Telegram sent an invalid authorization update.',
        ),
      );
      return;
    }
    final state = Map<String, dynamic>.from(rawState);
    unawaited(_handleAuthorizationUpdate(state));
  }

  Future<void> _handleAuthorizationUpdate(Map<String, dynamic> state) async {
    try {
      await _processAuthorizationState(state);
    } catch (error) {
      _emitError(_normalizeError(error));
    }
  }

  Future<void> _refreshAuthorizationState() async {
    for (var attempt = 0; attempt < 4; attempt++) {
      final state = await _gateway.send(const td.GetAuthorizationState());
      final needsRefresh = await _processAuthorizationState(state);
      if (!needsRefresh) {
        return;
      }
    }
    throw const AppException(
      AppErrorCode.telegramInitialization,
      message: 'Telegram did not finish preparing the sign-in screen. Please try again.',
    );
  }

  Future<bool> _processAuthorizationState(Map<String, dynamic> state) async {
    switch (state['@type']) {
      case 'authorizationStateWaitTdlibParameters':
        await _ensureTdlibParameters();
        return true;
      case 'authorizationStateWaitPhoneNumber':
        _emitAuth(const AuthStep(AuthStepKind.needsPhone));
        return false;
      case 'authorizationStateWaitCode':
        _emitAuth(const AuthStep(AuthStepKind.needsCode));
        return false;
      case 'authorizationStateWaitPassword':
        _emitAuth(const AuthStep(AuthStepKind.needsPassword));
        return false;
      case 'authorizationStateReady':
        _emitAuth(const AuthStep(AuthStepKind.ready));
        return false;
      case 'authorizationStateClosed':
      case 'authorizationStateClosing':
      case 'authorizationStateLoggingOut':
        _emitAuth(const AuthStep(AuthStepKind.expired));
        return false;
      case 'authorizationStateWaitEmailAddress':
      case 'authorizationStateWaitEmailCode':
        throw const AppException(
          AppErrorCode.telegramAuthFailed,
          message: 'Telegram requires email verification for this account. Complete sign-in in an official Telegram app, then try again.',
        );
      case 'authorizationStateWaitOtherDeviceConfirmation':
        throw const AppException(
          AppErrorCode.telegramAuthFailed,
          message: 'Telegram requires confirmation from another signed-in device. Approve the login there, then retry.',
        );
      case 'authorizationStateWaitRegistration':
        throw const AppException(
          AppErrorCode.telegramAuthFailed,
          message: 'This phone number needs a new Telegram account. Register it in an official Telegram app first.',
        );
      default:
        throw AppException(
          AppErrorCode.telegramApi,
          message: 'Unsupported Telegram authorization state: ${state['@type'] ?? 'unknown'}.',
        );
    }
  }

  Future<void> _ensureTdlibParameters() async {
    final pending = _tdlibParametersFuture;
    if (pending != null) {
      await pending;
      return;
    }
    final operation = _sendTdlibParameters();
    _tdlibParametersFuture = operation;
    try {
      await operation;
    } catch (_) {
      if (identical(_tdlibParametersFuture, operation)) {
        _tdlibParametersFuture = null;
      }
      rethrow;
    }
  }

  Future<void> _sendTdlibParameters() async {
    final settings = _settings;
    if (settings == null || !settings.hasTelegramConfiguration) {
      _emitAuth(const AuthStep(AuthStepKind.needsConfiguration));
      return;
    }
    final baseDir = await _applicationSupportDirectory();
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
        applicationVersion: '1.2.0',
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
    final Map<String, dynamic>? media;
    final MediaKind initialKind;
    if (contentType == 'messageVideo') {
      media = _asMap(contentMap['video']);
      initialKind = MediaKind.video;
    } else if (contentType == 'messageAudio') {
      media = _asMap(contentMap['audio']);
      initialKind = MediaKind.audio;
    } else if (contentType == 'messageDocument') {
      media = _asMap(contentMap['document']);
      initialKind = MediaKind.document;
    } else {
      return null;
    }
    if (media == null) {
      return null;
    }
    final file = _asMap(media['video']) ??
        _asMap(media['audio']) ??
        _asMap(media['document']);
    if (file == null) {
      return null;
    }
    final mimeType = _mimeTypeForMedia(media, initialKind);
    final fileName = _fileNameForMedia(media, initialKind, mimeType);
    final isAudio = initialKind == MediaKind.audio ||
        mimeType.startsWith('audio/') ||
        FileNameUtils.isSupportedAudioName(fileName);
    final isVideo = mimeType.startsWith('video/') ||
        FileNameUtils.isSupportedVideoName(fileName);
    if (!isAudio && !isVideo) {
      return null;
    }
    final kind = isAudio ? MediaKind.audio : initialKind;
    final fileId = int.tryParse(file['id']?.toString() ?? '') ?? 0;
    if (fileId <= 0) {
      return null;
    }
    final declaredSize = int.tryParse(file['size']?.toString() ?? '') ?? 0;
    final expectedSize =
        int.tryParse(file['expected_size']?.toString() ?? '') ?? 0;
    final fileSize = declaredSize > 0 ? declaredSize : expectedSize;
    if (fileSize <= 0) {
      return null;
    }
    final split = FileNameUtils.parseSplitInfo(fileName);
    final id = '$chatId:${message['id'] ?? 0}:$fileId';
    return MediaItem(
      id: id,
      chatId: chatId,
      messageId: int.tryParse(message['id']?.toString() ?? '') ?? 0,
      fileId: fileId,
      title: _titleForMedia(media, split?.displayName ?? fileName),
      fileName: fileName,
      mimeType: mimeType,
      size: fileSize,
      kind: split == null ? kind : MediaKind.splitVideo,
      artist: _artistForMedia(media),
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
        final groupKey = '${item.chatId}:${split.groupKey}';
        grouped.putIfAbsent(groupKey, () => <MediaItem>[]).add(item);
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
    _ThumbnailCandidate? best;

    void consider(Object? value) {
      if (value is List) {
        for (final entry in value) {
          consider(entry);
        }
        return;
      }
      if (value is! Map) {
        return;
      }
      final thumbnail = Map<String, dynamic>.from(value);
      final file = _asMap(thumbnail['file']);
      final fileId = int.tryParse(file?['id']?.toString() ?? '') ?? 0;
      if (fileId > 0) {
        final width = int.tryParse(thumbnail['width']?.toString() ?? '') ?? 0;
        final height = int.tryParse(thumbnail['height']?.toString() ?? '') ?? 0;
        final size = int.tryParse(file?['size']?.toString() ?? '') ?? 0;
        final candidate = _ThumbnailCandidate(
          fileId: fileId,
          score: (width * height * 1000000) + size,
        );
        if (best == null || candidate.score > best!.score) {
          best = candidate;
        }
      }
      for (final key in const <String>['small', 'medium', 'big', 'thumbnail']) {
        consider(thumbnail[key]);
      }
    }

    consider(media['thumbnail']);
    consider(media['album_cover_thumbnail']);
    consider(media['external_album_covers']);
    return best?.fileId;
  }

  String _mimeTypeForMedia(Map<String, dynamic> media, MediaKind kind) {
    final mimeType = media['mime_type']?.toString().trim() ?? '';
    if (mimeType.isNotEmpty) {
      return mimeType;
    }
    return kind == MediaKind.audio ? 'audio/mpeg' : 'application/octet-stream';
  }

  String _fileNameForMedia(
    Map<String, dynamic> media,
    MediaKind kind,
    String mimeType,
  ) {
    final fileName = media['file_name']?.toString().trim() ?? '';
    if (fileName.isNotEmpty) {
      return fileName;
    }
    final title = media['title']?.toString().trim() ?? '';
    final baseName = title.isEmpty
        ? (kind == MediaKind.audio ? 'Telegram audio' : 'Telegram media')
        : title;
    final extension = switch (mimeType.toLowerCase()) {
      'audio/mpeg' => '.mp3',
      'audio/mp4' || 'audio/x-m4a' => '.m4a',
      'audio/aac' => '.aac',
      'audio/flac' => '.flac',
      'audio/ogg' => '.ogg',
      'audio/opus' => '.opus',
      'audio/wav' || 'audio/x-wav' => '.wav',
      _ => '',
    };
    return '$baseName$extension';
  }

  String _titleForMedia(Map<String, dynamic> media, String fallback) {
    final title = media['title']?.toString().trim() ?? '';
    return title.isEmpty ? fallback : title;
  }

  String? _artistForMedia(Map<String, dynamic> media) {
    final performer = media['performer']?.toString().trim() ?? '';
    return performer.isEmpty ? null : performer;
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

  void _emitError(AppException error) {
    if (!_errors.isClosed) {
      _errors.add(error);
    }
  }

  AppException _normalizeError(Object error) {
    if (error is AppException) {
      return error;
    }
    final normalized = error.toString().toLowerCase();
    if (normalized.contains('socket') ||
        normalized.contains('network') ||
        normalized.contains('connection')) {
      return AppException(AppErrorCode.noInternet, cause: error);
    }
    if (normalized.contains('dynamiclibrary') ||
        normalized.contains('shared object') ||
        normalized.contains('tdjson') ||
        normalized.contains('symbol')) {
      return AppException(
        AppErrorCode.telegramInitialization,
        message: 'The Telegram library could not be loaded on this device.',
        cause: error,
      );
    }
    return AppException(
      AppErrorCode.telegramApi,
      message: 'Telegram sign-in stopped unexpectedly. Please try again.',
      cause: error,
    );
  }

  @override
  Future<void> close() async {
    await _updatesSub?.cancel();
    await _authSteps.close();
    await _errors.close();
    await _gateway.close();
  }
}

class _TdFile {
  const _TdFile({this.localPath});

  final String? localPath;
}

class _ThumbnailCandidate {
  const _ThumbnailCandidate({required this.fileId, required this.score});

  final int fileId;
  final int score;
}
