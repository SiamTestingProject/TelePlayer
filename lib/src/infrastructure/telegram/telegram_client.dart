import 'dart:typed_data';

import '../../core/errors/app_exception.dart';
import '../../features/auth/models/auth_models.dart';
import '../../features/library/models/media_item.dart';
import '../../features/settings/models/app_settings.dart';

class MediaScanProgress {
  const MediaScanProgress({
    required this.scannedMessages,
    required this.mediaCount,
  });

  final int scannedMessages;
  final int mediaCount;
}

abstract interface class TelegramClient {
  Stream<AuthStep> get authSteps;
  Stream<AppException> get errors;

  Future<void> initialize(AppSettings settings);
  Future<void> submitPhoneNumber(String phoneNumber);
  Future<void> submitCode(String code);
  Future<void> submitPassword(String password);
  Future<void> close();

  Future<List<MediaItem>> listRecentMedia({
    required List<int> channelIds,
    required int limitPerChannel,
  });

  Future<List<MediaItem>> listAllMedia({
    required List<int> channelIds,
    required void Function(MediaScanProgress progress) onProgress,
  });

  Future<MediaItem> refreshMedia(MediaItem item);
  Future<Uint8List> readFileRange(MediaItem item, int start, int end);
  Future<Uint8List?> loadThumbnail(MediaItem item);
}
