import '../../../core/errors/app_exception.dart';
import '../../../infrastructure/telegram/telegram_client.dart';
import '../../settings/models/app_settings.dart';
import '../models/auth_models.dart';

class AuthRepository {
  AuthRepository(this._client);

  final TelegramClient _client;

  Stream<AuthStep> get authSteps => _client.authSteps;

  Future<void> initialize(AppSettings settings) async {
    if (!settings.hasTelegramConfiguration) {
      throw const AppException(AppErrorCode.missingConfiguration);
    }
    await _client.initialize(settings);
  }

  Future<void> submitPhoneNumber(String phoneNumber) => _client.submitPhoneNumber(phoneNumber);

  Future<void> submitCode(String code) => _client.submitCode(code);

  Future<void> submitPassword(String password) => _client.submitPassword(password);
}
