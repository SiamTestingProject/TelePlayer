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
    _authErrorSubscription = _repository.errors.listen((error) {
      _error = error;
      _isBusy = false;
      notifyListeners();
    });
  }

  final AuthRepository _repository;
  final SettingsController _settingsController;
  late final StreamSubscription<AuthStep> _authSubscription;
  late final StreamSubscription<AppException> _authErrorSubscription;

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
      _error = _normalizeError(
        error,
        fallback: AppErrorCode.telegramInitialization,
      );
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
      _error = _normalizeError(
        error,
        fallback: AppErrorCode.telegramAuthFailed,
      );
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  AppException _normalizeError(
    Object error, {
    required AppErrorCode fallback,
  }) {
    if (error is AppException) {
      return error;
    }
    final text = error.toString();
    final normalized = text.toLowerCase();
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
    return AppException(fallback, cause: error);
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    _authErrorSubscription.cancel();
    super.dispose();
  }
}
