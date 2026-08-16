import 'app_exception.dart';

class FriendlyError {
  const FriendlyError({
    required this.title,
    required this.body,
    this.actionLabel,
  });

  final String title;
  final String body;
  final String? actionLabel;
}

class ErrorMessageMapper {
  const ErrorMessageMapper();

  FriendlyError map(Object error) {
    final appError = _normalize(error);
    switch (appError.code) {
      case AppErrorCode.noInternet:
        return const FriendlyError(
          title: 'No internet connection',
          body: 'Check your connection and try again.',
          actionLabel: 'Retry',
        );
      case AppErrorCode.telegramInitialization:
        return FriendlyError(
          title: 'Telegram engine could not start',
          body: appError.message ??
              'The Telegram library could not be loaded. Reinstall the app and try again.',
          actionLabel: 'Retry',
        );
      case AppErrorCode.telegramAuthFailed:
        return FriendlyError(
          title: 'Telegram sign-in failed',
          body: appError.message ??
              'Check the phone number, code, or two-step verification password.',
        );
      case AppErrorCode.expiredSession:
        return const FriendlyError(
          title: 'Session expired',
          body: 'Please sign in to Telegram again to refresh this device session.',
          actionLabel: 'Sign in',
        );
      case AppErrorCode.deletedMessage:
        return const FriendlyError(
          title: 'Message was deleted',
          body: 'This Telegram message is no longer available.',
        );
      case AppErrorCode.deletedMedia:
        return const FriendlyError(
          title: 'Media was deleted',
          body: 'The media file attached to this message is no longer available.',
        );
      case AppErrorCode.privateChannel:
        return const FriendlyError(
          title: 'Channel is private',
          body: 'You do not have access to this channel, or the session lost permission.',
        );
      case AppErrorCode.invalidMedia:
        return const FriendlyError(
          title: 'Invalid media',
          body: 'This item does not contain a playable video or document.',
        );
      case AppErrorCode.unsupportedCodec:
        return const FriendlyError(
          title: 'Unsupported format',
          body: 'This device cannot play the codec used by this file.',
        );
      case AppErrorCode.playbackFailure:
        return const FriendlyError(
          title: 'Playback failed',
          body: 'The player could not start this stream.',
          actionLabel: 'Try again',
        );
      case AppErrorCode.networkInterrupted:
        return const FriendlyError(
          title: 'Stream interrupted',
          body: 'The network dropped while streaming. Playback can resume when the connection returns.',
          actionLabel: 'Resume',
        );
      case AppErrorCode.telegramApi:
        return FriendlyError(
          title: 'Telegram is unavailable',
          body: appError.message ?? 'Telegram returned an error. Please try again shortly.',
        );
      case AppErrorCode.rateLimited:
        final wait = appError.retryAfter;
        return FriendlyError(
          title: 'Too many requests',
          body: wait == null
              ? 'Telegram is asking us to slow down. Try again soon.'
              : 'Telegram is asking us to slow down. Try again in ${wait.inSeconds} seconds.',
        );
      case AppErrorCode.missingThumbnail:
        return const FriendlyError(
          title: 'Thumbnail unavailable',
          body: 'This item can still be played, but Telegram did not provide a thumbnail.',
        );
      case AppErrorCode.missingConfiguration:
        return const FriendlyError(
          title: 'Configuration needed',
          body: 'Add your Telegram API ID and API hash in Settings before signing in.',
        );
      case AppErrorCode.cacheUnavailable:
        return const FriendlyError(
          title: 'Cache unavailable',
          body: 'The local cache could not prepare this media range for playback.',
        );
      case AppErrorCode.unknown:
        return const FriendlyError(
          title: 'Something went wrong',
          body: 'Please try again. If it keeps happening, refresh your Telegram session.',
        );
    }
  }

  AppException _normalize(Object error) {
    if (error is AppException) {
      return error;
    }
    final text = error.toString().toLowerCase();
    if (text.contains('network') || text.contains('socket') || text.contains('connection')) {
      return AppException(AppErrorCode.noInternet, cause: error);
    }
    if (text.contains('flood') || text.contains('too many')) {
      return AppException(AppErrorCode.rateLimited, cause: error);
    }
    if (text.contains('unauthorized') || text.contains('auth')) {
      return AppException(AppErrorCode.expiredSession, cause: error);
    }
    if (text.contains('codec') || text.contains('format')) {
      return AppException(AppErrorCode.unsupportedCodec, cause: error);
    }
    return AppException(AppErrorCode.unknown, cause: error);
  }
}
