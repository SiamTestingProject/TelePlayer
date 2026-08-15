import 'package:flutter/foundation.dart';

import '../../../core/errors/app_exception.dart';
import '../data/settings_repository.dart';
import '../models/app_settings.dart';

class SettingsController extends ChangeNotifier {
  SettingsController(this._repository);

  final SettingsRepository _repository;

  AppSettings _settings = AppSettings.empty();
  bool _isLoading = true;
  Object? _error;

  AppSettings get settings => _settings;
  bool get isLoading => _isLoading;
  Object? get error => _error;

  Future<void> load() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _settings = await _repository.load();
    } catch (error) {
      _error = AppException(AppErrorCode.missingConfiguration, cause: error);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> save(AppSettings settings) async {
    _error = null;
    notifyListeners();
    try {
      await _repository.save(settings);
      _settings = settings;
    } catch (error) {
      _error = AppException(AppErrorCode.missingConfiguration, cause: error);
    } finally {
      notifyListeners();
    }
  }
}
