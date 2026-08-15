import '../../../core/services/local_streaming_server.dart';
import '../../../infrastructure/telegram/telegram_client.dart';
import '../../settings/models/app_settings.dart';
import '../models/media_item.dart';

class MediaRepository {
  MediaRepository({
    required TelegramClient telegramClient,
    required LocalStreamingServer streamingServer,
  })  : _telegramClient = telegramClient,
        _streamingServer = streamingServer;

  final TelegramClient _telegramClient;
  final LocalStreamingServer _streamingServer;

  Future<List<MediaItem>> loadRecent(AppSettings settings) {
    return _telegramClient.listRecentMedia(
      channelIds: settings.channelIds,
      limitPerChannel: 60,
    );
  }

  Future<Uri> streamUriFor(MediaItem item) {
    return _streamingServer.register(item);
  }
}
