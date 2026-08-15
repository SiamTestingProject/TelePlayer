import 'dart:typed_data';

import '../../features/auth/models/auth_models.dart';
import '../../features/library/models/media_item.dart';
import '../../features/settings/models/app_settings.dart';

abstract interface class TelegramClient {
  Stream<AuthStep> get authSteps;

  Future<void> initialize(AppSettings settings);
  Future<void> submitPhoneNumber(String phoneNumber);
  Future<void> submitCode(String code);
  Future<void> submitPassword(String password);
  Future<void> close();

  Future<List<MediaItem>> listRecentMedia({
    required List<int> channelIds,
    required int limitPerChannel,
  });

  Future<MediaItem> refreshMedia(MediaItem item);
  Future<Uint8List> readFileRange(MediaItem item, int start, int end);
  Future<Uint8List?> loadThumbnail(MediaItem item);
}
