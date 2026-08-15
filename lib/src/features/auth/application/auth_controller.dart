import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/errors/app_exception.dart';
import '../../settings/application/settings_controller.dart';
import '../data/auth_repository.dart';
import '../models/auth_models.dart';

class AuthController extends ChangeNotifier {
  AuthController({
    required AuthRepository repository,
    required SettingsController settingsController,
  })  : _repository = repository,
        _settingsController = settingsController {
    _authSubscription = _repository.authSteps.listen((step) {
      _step = step;
      _error = null;
      notifyListeners();
    });
  }

  final AuthRepository _repository;
  final SettingsController _settingsController;
  late final StreamSubscription<AuthStep> _authSubscription;

  AuthStep _step = const AuthStep(AuthStepKind.unknown);
  bool _isBusy = false;
  Object? _error;

  AuthStep get step => _step;
  bool get isBusy => _isBusy;
  Object? get error => _error;
  bool get isReady => _step.isReady;

  Future<void> initialize() async {
    _isBusy = true;
    _error = null;
    notifyListeners();
    try {
      await _repository.initialize(_settingsController.settings);
    } catch (error) {
      _error = error is AppException
          ? error
          : AppException(AppErrorCode.telegramAuthFailed, cause: error);
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<void> submitPhone(String phoneNumber) => _run(() => _repository.submitPhoneNumber(phoneNumber));

  Future<void> submitCode(String code) => _run(() => _repository.submitCode(code));

  Future<void> submitPassword(String password) => _run(() => _repository.submitPassword(password));

  Future<void> _run(Future<void> Function() action) async {
    _isBusy = true;
    _error = null;
    notifyListeners();
    try {
      await action();
    } catch (error) {
      _error = error is AppException
          ? error
          : AppException(AppErrorCode.telegramAuthFailed, cause: error);
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
  }
}
