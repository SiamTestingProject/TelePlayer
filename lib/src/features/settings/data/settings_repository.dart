import '../../../core/services/secure_config_store.dart';
import '../models/app_settings.dart';

class SettingsRepository {
  SettingsRepository(this._store);

  final SecureConfigStore _store;

  Future<AppSettings> load() => _store.readSettings();

  Future<void> save(AppSettings settings) => _store.saveSettings(settings);
}
