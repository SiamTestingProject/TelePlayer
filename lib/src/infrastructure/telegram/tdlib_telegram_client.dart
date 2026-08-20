import 'dart:async';
import 'dart:io' as io;
import 'dart:math';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:tdlib/td_api.dart' as td;

import '../../core/errors/app_exception.dart';
import '../../core/utils/embedded_artwork.dart';
import '../../core/utils/file_name_utils.dart';
import '../../features/auth/models/auth_models.dart';
import '../../features/library/models/media_item.dart';
import '../../features/settings/models/app_settings.dart';
import 'tdlib_gateway.dart';
import 'telegram_client.dart';

typedef ApplicationSupportDirectoryProvider = Future<io.Directory> Function();

class TdlibTelegramClient
    implements
        TelegramClient,
        EmbeddedArtworkProvider,
        AudioTechnicalMetadataProvider,
        PlaybackCacheCleaner,
        FullCacheCleaner,
        IncrementalMediaScanner,
        DirectPlaybackFileProvider {
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
  final _fullDownloadRequests = <int>{};
  final Map<int, String> _chatTitles = <int, String>{};

  AppSettings? _settings;
  StreamSubscription<Map<String, dynamic>>? _updatesSub;
  Future<void>? _tdlibParametersFuture;
  Future<void>? _tdlibParameterRecoveryFuture;

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
      final response = await _sendAuthorized(
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
    items.sort((left, right) => right.messageId.compareTo(left.messageId));
    return items;
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
        final response = await _sendAuthorized(
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
    items.sort((left, right) => right.messageId.compareTo(left.messageId));
    return items;
  }

  @override
  Future<List<MediaItem>> listMediaSince({
    required List<int> channelIds,
    required Map<int, int> afterMessageIdByChannel,
    required void Function(MediaScanProgress progress) onProgress,
  }) async {
    await _ensureChatsAvailable(channelIds);
    final items = <MediaItem>[];
    var scannedMessages = 0;

    for (final chatId in channelIds) {
      final afterMessageId = afterMessageIdByChannel[chatId] ?? 0;
      var fromMessageId = 0;
      final seenMessageIds = <int>{};
      var reachedBoundary = false;

      while (!reachedBoundary) {
        final response = await _sendAuthorized(
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
          if (afterMessageId > 0 && messageId <= afterMessageId) {
            reachedBoundary = true;
            break;
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

        if (reachedBoundary || newMessages == 0) {
          break;
        }
        final oldestMessageId = messages
            .map((message) =>
                int.tryParse(message['id']?.toString() ?? '') ?? 0)
            .where((id) => id > 0)
            .fold<int>(
              0,
              (oldest, id) => oldest == 0 || id < oldest ? id : oldest,
            );
        if (oldestMessageId == 0 || oldestMessageId == fromMessageId) {
          break;
        }
        fromMessageId = oldestMessageId;
      }
    }

    items.sort((left, right) => right.messageId.compareTo(left.messageId));
    return items;
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
        final response = await _sendAuthorized(
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
        final chat = await _sendAuthorized(td.GetChat(chatId: chatId));
        final title = chat['title']?.toString().trim() ?? '';
        if (title.isNotEmpty) {
          _chatTitles[chatId] = title;
        }
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
    final response = await _sendAuthorized(
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
      final response = await _sendAuthorized(
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
        // Once playback has proven that this file is valid, ask TDLib to keep
        // downloading the remainder in its native file manager. This lets the
        // player transition from range-by-range network reads to local disk as
        // the track progresses, which is substantially more reliable while
        // Android is backgrounded or the network briefly enters Doze.
        _requestFullFileDownload(fileId);
        return result;
      } finally {
        await handle.close();
      }
    });
  }

  void _requestFullFileDownload(int fileId) {
    if (!_fullDownloadRequests.add(fileId)) {
      return;
    }
    unawaited(_downloadFullFileInBackground(fileId));
  }

  Future<void> _downloadFullFileInBackground(int fileId) async {
    try {
      await _sendAuthorized(
        td.DownloadFile(
          fileId: fileId,
          priority: 32,
          offset: 0,
          limit: 0,
          synchronous: false,
        ),
        timeout: const Duration(seconds: 30),
      );
    } catch (_) {
      // Allow a later range read to retry the full prefetch. Playback itself
      // continues to use the synchronous high-priority range request.
      _fullDownloadRequests.remove(fileId);
    }
  }

  @override
  Future<Uri?> prepareDirectPlaybackUri(MediaItem item) async {
    if (item.kind != MediaKind.audio || item.isSplit || item.fileId <= 0) {
      return null;
    }

    var currentItem = item;
    try {
      currentItem = await refreshMedia(item);
    } catch (_) {
      // The cached TDLib file ID is still worth trying when GetMessage is
      // temporarily unavailable.
    }
    if (currentItem.isSplit || currentItem.fileId <= 0) {
      return null;
    }

    final fileId = currentItem.fileId;
    // Do not serialize this whole-file wait behind the range-read lock. If the
    // user changes songs, clearPlaybackCache must be able to cancel this TDLib
    // download immediately instead of waiting for a large FLAC file to finish.
    final response = await _sendAuthorized(
      td.DownloadFile(
        fileId: fileId,
        priority: 32,
        offset: 0,
        limit: 0,
        synchronous: true,
      ),
      timeout: const Duration(minutes: 5),
    );
    final file = _extractFile(response);
    final path = file.localPath;
    if (path == null || path.isEmpty) {
      return null;
    }
    final localFile = io.File(path);
    if (!await localFile.exists()) {
      return null;
    }
    final complete = file.isDownloadingCompleted ||
        (file.downloadedSize >= currentItem.size && currentItem.size > 0);
    if (!complete) {
      return null;
    }
    _fullDownloadRequests.add(fileId);
    return Uri.file(path);
  }

  @override
  Future<void> clearPlaybackCache(MediaItem item) async {
    var currentItem = item;
    try {
      currentItem = await refreshMedia(item);
    } catch (_) {
      // The last known file IDs are still useful if the message cannot be
      // refreshed while the device is offline.
    }
    final fileIds = <int>{
      if (currentItem.fileId > 0) currentItem.fileId,
      ...currentItem.parts
          .map((part) => part.fileId)
          .where((fileId) => fileId > 0),
    };

    for (final fileId in fileIds) {
      await _withFileDownloadLock(fileId, () async {
        _fullDownloadRequests.remove(fileId);
        try {
          await _sendAuthorized(
            td.CancelDownloadFile(
              fileId: fileId,
              onlyIfPending: false,
            ),
            timeout: const Duration(seconds: 10),
          );
        } catch (_) {
          // The full-file prefetch may already have completed. Deleting the
          // cached file below is still the important cleanup step.
        }
        try {
          await _sendAuthorized(
            td.DeleteFile(fileId: fileId),
            timeout: const Duration(seconds: 15),
          );
        } catch (_) {
          // Playback cleanup is best-effort. A failed deletion must never make
          // the next track unavailable; TDLib can retry cleanup later.
        }
      });
    }
  }

  @override
  Future<void> clearAllCachedFiles(Iterable<MediaItem> items) async {
    final activeDownloads = _fullDownloadRequests.toSet();
    _fullDownloadRequests.clear();
    final mediaFileIds = <int>{};
    final thumbnailFileIds = <int>{};
    for (final item in items) {
      if (item.fileId > 0) {
        mediaFileIds.add(item.fileId);
      }
      final thumbnailId = item.thumbnailFileId;
      if (thumbnailId != null && thumbnailId > 0) {
        thumbnailFileIds.add(thumbnailId);
      }
      mediaFileIds.addAll(
        item.parts.map((part) => part.fileId).where((fileId) => fileId > 0),
      );
    }

    for (final fileId in activeDownloads) {
      try {
        await _sendAuthorized(
          td.CancelDownloadFile(fileId: fileId, onlyIfPending: false),
          timeout: const Duration(seconds: 10),
        );
      } catch (_) {
        // The download may already have completed.
      }
    }

    var optimized = false;
    try {
      await _sendAuthorized(
        const td.OptimizeStorage(
          size: 0,
          ttl: 0,
          count: 0,
          immunityDelay: 0,
          fileTypes: <td.FileType>[],
          chatIds: <int>[],
          excludeChatIds: <int>[],
          returnDeletedFileStatistics: false,
          chatLimit: 0,
        ),
        timeout: const Duration(minutes: 1),
      );
      optimized = true;
    } catch (_) {
      // Fall back to deleting each known media file below.
    }

    // With an empty file-type filter TDLib's storage optimizer removes normal
    // downloaded media but deliberately leaves some thumbnail-like file types.
    // Delete TelePlayer's known song thumbnails explicitly. If the optimizer
    // failed, also delete every known song/part file as a fallback.
    final fileIdsToDelete = <int>{
      ...thumbnailFileIds,
      if (!optimized) ...mediaFileIds,
    };
    for (final fileId in fileIdsToDelete) {
      await _withFileDownloadLock(fileId, () async {
        try {
          await _sendAuthorized(
            td.DeleteFile(fileId: fileId),
            timeout: const Duration(seconds: 15),
          );
        } catch (_) {
          // Continue cleaning the rest of the cache even if one TDLib file
          // cannot be removed immediately.
        }
      });
    }
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
  Future<Uint8List?> loadEmbeddedArtwork(MediaItem item) async {
    final prefix = await _loadAudioPrefix(item, 2 * 1024 * 1024);
    if (prefix == null || prefix.isEmpty) {
      return null;
    }
    return EmbeddedArtwork.extract(
      prefix,
      fileName: item.fileName,
      mimeType: item.mimeType,
    );
  }

  @override
  Future<AudioTechnicalMetadata?> loadTechnicalMetadata(MediaItem item) async {
    final prefix = await _loadAudioPrefix(item, 256 * 1024);
    if (prefix == null || prefix.isEmpty) {
      return null;
    }
    return EmbeddedArtwork.technicalMetadata(
      prefix,
      fileName: item.fileName,
      mimeType: item.mimeType,
    );
  }

  Future<Uint8List?> _loadAudioPrefix(MediaItem item, int maximumBytes) async {
    final firstPart = item.parts.isEmpty ? null : item.parts.first;
    final fileId = firstPart?.fileId ?? item.fileId;
    final fileSize = firstPart?.size ?? item.size;
    if (fileId <= 0 || fileSize <= 0) {
      return null;
    }
    final probeBytes = min(fileSize, maximumBytes);

    return _withFileDownloadLock(fileId, () async {
      final response = await _sendAuthorized(
        td.DownloadFile(
          fileId: fileId,
          priority: 18,
          offset: 0,
          limit: probeBytes,
          synchronous: true,
        ),
        timeout: const Duration(minutes: 2),
      );
      final file = _extractFile(response);
      final path = file.localPath;
      if (path == null || path.isEmpty || !await io.File(path).exists()) {
        return null;
      }

      final handle = await io.File(path).open();
      try {
        await handle.setPosition(0);
        final bytes = BytesBuilder(copy: false);
        while (bytes.length < probeBytes) {
          final chunk = await handle.read(
            min(256 * 1024, probeBytes - bytes.length),
          );
          if (chunk.isEmpty) {
            break;
          }
          bytes.add(chunk);
        }
        final prefix = bytes.takeBytes();
        return prefix.isEmpty ? null : prefix;
      } finally {
        await handle.close();
      }
    });
  }

  @override
  Future<Uint8List?> loadThumbnail(MediaItem item) async {
    final thumbnailId = item.thumbnailFileId;
    if (thumbnailId == null) {
      return null;
    }
    final response = await _sendAuthorized(
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

  Future<Map<String, dynamic>> _sendAuthorized(
    td.TdFunction request, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    try {
      return await _gateway.send(request, timeout: timeout);
    } on AppException catch (error) {
      if (!_needsTdlibParameters(error)) {
        rethrow;
      }
      await _recoverTdlibParameters();
      return _gateway.send(request, timeout: timeout);
    }
  }

  bool _needsTdlibParameters(AppException error) {
    final message = error.message?.toLowerCase() ?? '';
    return message.contains('initialization parameters are needed') ||
        message.contains('settdlibparameters');
  }

  Future<void> _recoverTdlibParameters() async {
    final pending = _tdlibParameterRecoveryFuture;
    if (pending != null) {
      await pending;
      return;
    }

    final operation = _refreshTdlibParametersAfterRestart();
    _tdlibParameterRecoveryFuture = operation;
    try {
      await operation;
    } finally {
      if (identical(_tdlibParameterRecoveryFuture, operation)) {
        _tdlibParameterRecoveryFuture = null;
      }
    }
  }

  Future<void> _refreshTdlibParametersAfterRestart() async {
    final settings = _settings;
    if (settings == null || !settings.hasTelegramConfiguration) {
      throw const AppException(AppErrorCode.missingConfiguration);
    }
    await _gateway.initialize(tdjsonPath: settings.windowsTdjsonPath);
    // A completed future belongs to the previous native TDLib initialization
    // cycle. The recreated client must receive its own parameters.
    _tdlibParametersFuture = null;
    await _refreshAuthorizationState();
  }

  Future<void> _refreshAuthorizationState() async {
    for (var attempt = 0; attempt < 40; attempt++) {
      final state = await _gateway.send(const td.GetAuthorizationState());
      final needsRefresh = await _processAuthorizationState(state);
      if (!needsRefresh) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw const AppException(
      AppErrorCode.telegramInitialization,
      message: 'Telegram did not finish preparing its authorization state. Please try again.',
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
        applicationVersion: '1.4.35',
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
      return 'TelePlayer';
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
    final MediaKind sourceKind;
    if (contentType == 'messageAudio') {
      media = _asMap(contentMap['audio']);
      sourceKind = MediaKind.audio;
    } else if (contentType == 'messageDocument') {
      media = _asMap(contentMap['document']);
      sourceKind = MediaKind.document;
    } else {
      return null;
    }
    if (media == null) {
      return null;
    }
    final file = _asMap(media['audio']) ?? _asMap(media['document']);
    if (file == null) {
      return null;
    }
    final mimeType = _mimeTypeForMedia(media, sourceKind);
    final fileName = _fileNameForMedia(media, sourceKind, mimeType);
    final isAudio = sourceKind == MediaKind.audio ||
        mimeType.startsWith('audio/') ||
        FileNameUtils.isSupportedAudioName(fileName);
    if (!isAudio) {
      return null;
    }
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
    final id = '$chatId:${message['id'] ?? 0}:$fileId';
    return MediaItem(
      id: id,
      chatId: chatId,
      messageId: int.tryParse(message['id']?.toString() ?? '') ?? 0,
      fileId: fileId,
      title: _titleForMedia(media, fileName),
      fileName: fileName,
      mimeType: mimeType,
      size: fileSize,
      kind: MediaKind.audio,
      dateEpochSeconds:
          int.tryParse(message['date']?.toString() ?? '') ?? 0,
      artist: _artistForMedia(media),
      album: _albumForMedia(media),
      sourceName: _chatTitles[chatId],
      durationSeconds: int.tryParse(media['duration']?.toString() ?? ''),
      thumbnailFileId: _thumbnailFileId(media),
      inlineThumbnailBase64: _inlineThumbnailBase64(media),
      localPath: _asMap(file['local'])?['path']?.toString(),
    );
  }

  _TdFile _extractFile(Map<String, dynamic> json) {
    if (json['@type'] != 'file') {
      throw AppException(AppErrorCode.telegramApi, message: json['message']?.toString());
    }
    final local = _asMap(json['local']);
    return _TdFile(
      localPath: local?['path']?.toString(),
      isDownloadingCompleted: local?['is_downloading_completed'] == true,
      downloadedSize:
          int.tryParse(local?['downloaded_size']?.toString() ?? '') ?? 0,
    );
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

  String? _inlineThumbnailBase64(Map<String, dynamic> media) {
    for (final key in const <String>[
      'album_cover_minithumbnail',
      'minithumbnail',
    ]) {
      final thumbnail = _asMap(media[key]);
      final data = thumbnail?['data']?.toString().trim() ?? '';
      if (data.isNotEmpty) {
        return data;
      }
    }
    return null;
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
    final baseName = title.isEmpty ? 'Telegram audio' : title;
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

  String? _albumForMedia(Map<String, dynamic> media) {
    for (final key in const <String>['album', 'album_title', 'album_name']) {
      final value = media[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) {
        return value;
      }
    }
    return null;
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
    _fullDownloadRequests.clear();
    await _updatesSub?.cancel();
    await _authSteps.close();
    await _errors.close();
    await _gateway.close();
  }
}

class _TdFile {
  const _TdFile({
    this.localPath,
    this.isDownloadingCompleted = false,
    this.downloadedSize = 0,
  });

  final String? localPath;
  final bool isDownloadingCompleted;
  final int downloadedSize;
}

class _ThumbnailCandidate {
  const _ThumbnailCandidate({required this.fileId, required this.score});

  final int fileId;
  final int score;
}
