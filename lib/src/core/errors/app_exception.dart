enum AppErrorCode {
  noInternet,
  telegramInitialization,
  telegramAuthFailed,
  expiredSession,
  deletedMessage,
  deletedMedia,
  privateChannel,
  invalidMedia,
  unsupportedCodec,
  playbackFailure,
  networkInterrupted,
  telegramApi,
  rateLimited,
  missingThumbnail,
  missingConfiguration,
  cacheUnavailable,
  unknown,
}

class AppException implements Exception {
  const AppException(
    this.code, {
    this.message,
    this.cause,
    this.retryAfter,
  });

  final AppErrorCode code;
  final String? message;
  final Object? cause;
  final Duration? retryAfter;

  @override
  String toString() => 'AppException($code, $message)';
}
