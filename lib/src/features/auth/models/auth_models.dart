enum AuthStepKind {
  unknown,
  needsConfiguration,
  needsPhone,
  needsCode,
  needsPassword,
  ready,
  expired,
}

class AuthStep {
  const AuthStep(this.kind, {this.message});

  final AuthStepKind kind;
  final String? message;

  bool get isReady => kind == AuthStepKind.ready;
}

class TelegramCredentials {
  const TelegramCredentials({
    required this.apiId,
    required this.apiHash,
    required this.phoneNumber,
  });

  final int apiId;
  final String apiHash;
  final String phoneNumber;
}
