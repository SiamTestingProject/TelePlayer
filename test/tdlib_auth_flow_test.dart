import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tdlib/td_api.dart' as td;
import 'package:telegram_media_player/src/core/errors/app_exception.dart';
import 'package:telegram_media_player/src/features/auth/models/auth_models.dart';
import 'package:telegram_media_player/src/features/settings/models/app_settings.dart';
import 'package:telegram_media_player/src/infrastructure/telegram/tdlib_gateway.dart';
import 'package:telegram_media_player/src/infrastructure/telegram/tdlib_telegram_client.dart';

void main() {
  test('selects the packaged TDLib filename for each supported platform', () {
    expect(
      resolveTdjsonLibraryPath(configuredPath: null, operatingSystem: 'android'),
      'libtdjson.so',
    );
    expect(
      resolveTdjsonLibraryPath(configuredPath: null, operatingSystem: 'windows'),
      'tdjson.dll',
    );
    expect(
      resolveTdjsonLibraryPath(
        configuredPath: r'C:\Telegram\custom-tdjson.dll',
        operatingSystem: 'windows',
      ),
      r'C:\Telegram\custom-tdjson.dll',
    );
  });

  test('preserves TDLib response metadata used to complete requests', () {
    final json = tdObjectToJsonWithMetadata(
      const td.Ok(extra: 'request-42', clientId: 7),
    );

    expect(json['@type'], 'ok');
    expect(json['@extra'], 'request-42');
    expect(json['@client_id'], 7);
  });

  test('initialization requests and advances the TDLib authorization state', () async {
    final supportDirectory = await Directory.systemTemp.createTemp('teleplayer-auth-test-');
    final gateway = _FakeTdlibGateway();
    final client = TdlibTelegramClient(
      gateway,
      applicationSupportDirectory: () async => supportDirectory,
    );
    final steps = <AuthStep>[];
    final subscription = client.authSteps.listen(steps.add);

    addTearDown(() async {
      await subscription.cancel();
      await client.close();
      await supportDirectory.delete(recursive: true);
    });

    await client.initialize(_configuredSettings);

    expect(
      gateway.requestTypes,
      <String>[
        'getAuthorizationState',
        'setTdlibParameters',
        'getAuthorizationState',
      ],
    );
    expect(steps, isNotEmpty);
    expect(steps.last.kind, AuthStepKind.needsPhone);
  });

  test('rejects an invalid phone before calling TDLib', () async {
    final gateway = _FakeTdlibGateway();
    final client = TdlibTelegramClient(gateway);

    addTearDown(client.close);

    expect(
      () => client.submitPhoneNumber('01700 000000'),
      throwsA(
        isA<AppException>().having(
          (error) => error.code,
          'code',
          AppErrorCode.telegramAuthFailed,
        ),
      ),
    );
    expect(gateway.requestTypes, isEmpty);
  });

  test('phone submission refreshes and advances to the code step', () async {
    final gateway = _FakeTdlibGateway(
      authorizationStates: <Map<String, dynamic>>[
        <String, dynamic>{'@type': 'authorizationStateWaitCode'},
      ],
    );
    final client = TdlibTelegramClient(gateway);
    final steps = <AuthStep>[];
    final subscription = client.authSteps.listen(steps.add);

    addTearDown(() async {
      await subscription.cancel();
      await client.close();
    });

    await client.submitPhoneNumber('+8801620262057');

    expect(
      gateway.requestTypes,
      <String>[
        'setAuthenticationPhoneNumber',
        'getAuthorizationState',
      ],
    );
    expect(steps.last.kind, AuthStepKind.needsCode);
  });

  test('maps TDLib phone errors to an actionable sign-in failure', () async {
    final gateway = _FakeTdlibGateway(
      requestError: const AppException(
        AppErrorCode.telegramApi,
        message: 'PHONE_NUMBER_INVALID',
      ),
    );
    final client = TdlibTelegramClient(gateway);

    addTearDown(client.close);

    await expectLater(
      client.submitPhoneNumber('+8801620262057'),
      throwsA(
        isA<AppException>()
            .having(
              (error) => error.code,
              'code',
              AppErrorCode.telegramAuthFailed,
            )
            .having(
              (error) => error.message,
              'message',
              contains('country code'),
            ),
      ),
    );
  });
}

const _configuredSettings = AppSettings(
  apiId: 12345,
  apiHash: '0123456789abcdef0123456789abcdef',
  channelIds: <int>[],
  cacheLimitMb: 4096,
  preferWifi: true,
);

class _FakeTdlibGateway extends TdlibGateway {
  _FakeTdlibGateway({
    List<Map<String, dynamic>>? authorizationStates,
    this.requestError,
  })
      : _authorizationStates = authorizationStates ??
            <Map<String, dynamic>>[
              <String, dynamic>{
                '@type': 'authorizationStateWaitTdlibParameters',
              },
              <String, dynamic>{
                '@type': 'authorizationStateWaitPhoneNumber',
              },
            ];

  final _updates = StreamController<Map<String, dynamic>>.broadcast();
  final requestTypes = <String>[];
  final List<Map<String, dynamic>> _authorizationStates;
  final AppException? requestError;

  bool _initialized = false;

  @override
  Stream<Map<String, dynamic>> get updates => _updates.stream;

  @override
  bool get isInitialized => _initialized;

  @override
  Future<void> initialize({String? tdjsonPath}) async {
    _initialized = true;
  }

  @override
  Future<Map<String, dynamic>> send(
    td.TdFunction request, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final type = request.getConstructor();
    requestTypes.add(type);
    if (type != 'getAuthorizationState' && requestError != null) {
      throw requestError!;
    }
    if (type == 'getAuthorizationState') {
      if (_authorizationStates.length > 1) {
        return _authorizationStates.removeAt(0);
      }
      return _authorizationStates.single;
    }
    return <String, dynamic>{'@type': 'ok'};
  }

  @override
  Future<void> close() async {
    _initialized = false;
    await _updates.close();
  }
}
