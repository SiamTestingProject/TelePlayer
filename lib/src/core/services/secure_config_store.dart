import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../features/settings/models/app_settings.dart';

class SecureConfigStore {
  SecureConfigStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  static const _apiIdKey = 'telegram_api_id';
  static const _apiHashKey = 'telegram_api_hash';
  static const _channelsKey = 'telegram_channel_ids';
  static const _cacheLimitKey = 'cache_limit_mb';
  static const _preferWifiKey = 'prefer_wifi';
  static const _windowsTdjsonPathKey = 'windows_tdjson_path';

  final FlutterSecureStorage _storage;

  Future<AppSettings> readSettings() async {
    final rawApiId = await _storage.read(key: _apiIdKey);
    final rawChannels = await _storage.read(key: _channelsKey);
    final rawCacheLimit = await _storage.read(key: _cacheLimitKey);
    final rawPreferWifi = await _storage.read(key: _preferWifiKey);
    return AppSettings(
      apiId: int.tryParse(rawApiId ?? ''),
      apiHash: await _storage.read(key: _apiHashKey),
      channelIds: _parseChannelIds(rawChannels ?? ''),
      cacheLimitMb: int.tryParse(rawCacheLimit ?? '') ?? 4096,
      preferWifi: rawPreferWifi == null ? true : rawPreferWifi == 'true',
      windowsTdjsonPath: await _storage.read(key: _windowsTdjsonPathKey),
    );
  }

  Future<void> saveSettings(AppSettings settings) async {
    if (settings.apiId == null) {
      await _storage.delete(key: _apiIdKey);
    } else {
      await _storage.write(key: _apiIdKey, value: settings.apiId.toString());
    }
    if (settings.apiHash == null || settings.apiHash!.trim().isEmpty) {
      await _storage.delete(key: _apiHashKey);
    } else {
      await _storage.write(key: _apiHashKey, value: settings.apiHash!.trim());
    }
    await _storage.write(
      key: _channelsKey,
      value: settings.channelIds.map((id) => id.toString()).join(','),
    );
    await _storage.write(key: _cacheLimitKey, value: settings.cacheLimitMb.toString());
    await _storage.write(key: _preferWifiKey, value: settings.preferWifi.toString());
    final tdjsonPath = settings.windowsTdjsonPath?.trim();
    if (tdjsonPath == null || tdjsonPath.isEmpty) {
      await _storage.delete(key: _windowsTdjsonPathKey);
    } else {
      await _storage.write(key: _windowsTdjsonPathKey, value: tdjsonPath);
    }
  }

  Future<void> clearTelegramSecrets() async {
    await _storage.delete(key: _apiHashKey);
  }

  List<int> _parseChannelIds(String value) {
    return value
        .split(',')
        .map((part) => int.tryParse(part.trim()))
        .whereType<int>()
        .toList(growable: false);
  }
}
