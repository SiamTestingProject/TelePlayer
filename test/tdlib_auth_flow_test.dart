import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tdlib/td_api.dart' as td;
import 'package:telegram_media_player/src/core/errors/app_exception.dart';
import 'package:telegram_media_player/src/features/auth/models/auth_models.dart';
import 'package:telegram_media_player/src/features/library/models/media_item.dart';
import 'package:telegram_media_player/src/features/settings/models/app_settings.dart';
import 'package:telegram_media_player/src/infrastructure/telegram/tdlib_gateway.dart';
import 'package:telegram_media_player/src/infrastructure/telegram/tdlib_telegram_client.dart';
import 'package:telegram_media_player/src/infrastructure/telegram/telegram_client.dart';

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

  test('does not label chat history lookup failures as deleted messages', () {
    final historyError = telegramExceptionForResponse(
      <String, dynamic>{
        '@type': 'error',
        'code': 404,
        'message': 'Not Found',
      },
      requestType: 'getChatHistory',
    );
    final messageError = telegramExceptionForResponse(
      <String, dynamic>{
        '@type': 'error',
        'code': 404,
        'message': 'Message not found',
      },
      requestType: 'getMessage',
    );
    final completedChatLoad = telegramExceptionForResponse(
      <String, dynamic>{
        '@type': 'error',
        'code': 404,
        'message': 'Not Found',
      },
      requestType: 'loadChats',
    );

    expect(historyError?.code, AppErrorCode.privateChannel);
    expect(messageError?.code, AppErrorCode.deletedMessage);
    expect(completedChatLoad, isNull);
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

    await client.submitPhoneNumber('+15551234567');

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
      client.submitPhoneNumber('+15551234567'),
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

  test('loads an unknown channel and includes Telegram audio posts', () async {
    var chatsLoaded = false;
    final gateway = _FakeTdlibGateway(
      requestHandler: (request) {
        switch (request.getConstructor()) {
          case 'getChat':
            if (!chatsLoaded) {
              throw const AppException(
                AppErrorCode.privateChannel,
                message: 'Chat not found',
              );
            }
            return <String, dynamic>{
              '@type': 'chat',
              'id': -1001234567890,
              'title': 'My Music Collection',
            };
          case 'loadChats':
            chatsLoaded = true;
            return <String, dynamic>{'@type': 'ok'};
          case 'getChatHistory':
            return <String, dynamic>{
              '@type': 'messages',
              'messages': <Object?>[
                <String, dynamic>{
                  '@type': 'message',
                  'id': 552,
                  'content': <String, dynamic>{
                    '@type': 'messageAudio',
                    'audio': <String, dynamic>{
                      '@type': 'audio',
                      'duration': 262,
                      'title': 'Example Track',
                      'performer': 'Example Artist',
                      'file_name': 'Example Track.mp3',
                      'mime_type': 'audio/mpeg',
                      'album_cover_minithumbnail': <String, dynamic>{
                        '@type': 'minithumbnail',
                        'width': 40,
                        'height': 40,
                        'data': 'AQIDBA==',
                      },
                      'thumbnail': <String, dynamic>{
                        'width': 90,
                        'height': 90,
                        'file': <String, dynamic>{
                          'id': 66,
                          'size': 4000,
                        },
                      },
                      'album_cover_thumbnail': <String, dynamic>{
                        'width': 640,
                        'height': 640,
                        'file': <String, dynamic>{
                          'id': 88,
                          'size': 48000,
                        },
                      },
                      'external_album_covers': <Object?>[
                        <String, dynamic>{
                          'width': 1280,
                          'height': 1280,
                          'file': <String, dynamic>{
                            'id': 99,
                            'size': 160000,
                          },
                        },
                      ],
                      'audio': <String, dynamic>{
                        '@type': 'file',
                        'id': 77,
                        'size': 0,
                        'expected_size': 32600000,
                        'local': <String, dynamic>{'path': ''},
                      },
                    },
                  },
                },
              ],
            };
          default:
            return <String, dynamic>{'@type': 'ok'};
        }
      },
    );
    final client = TdlibTelegramClient(gateway);

    addTearDown(client.close);

    final items = await client.listRecentMedia(
      channelIds: const <int>[-1001234567890],
      limitPerChannel: 60,
    );

    expect(
      gateway.requestTypes,
      <String>['getChat', 'loadChats', 'getChat', 'getChatHistory'],
    );
    expect(items, hasLength(1));
    expect(items.single.kind, MediaKind.audio);
    expect(items.single.title, 'Example Track');
    expect(items.single.artist, 'Example Artist');
    expect(items.single.fileId, 77);
    expect(items.single.size, 32600000);
    expect(items.single.thumbnailFileId, 99);
    expect(items.single.inlineThumbnailBase64, 'AQIDBA==');
  });

  test('prefetches the complete audio file after the first playback range', () async {
    final directory = await Directory.systemTemp.createTemp(
      'teleplayer-range-prefetch-test-',
    );
    final mediaFile = File('${directory.path}/track.mp3');
    await mediaFile.writeAsBytes(<int>[10, 20, 30, 40, 50, 60, 70, 80]);
    final gateway = _FakeTdlibGateway(
      requestHandler: (request) {
        if (request.getConstructor() == 'downloadFile') {
          return <String, dynamic>{
            '@type': 'file',
            'id': 77,
            'size': 8,
            'local': <String, dynamic>{
              'path': mediaFile.path,
            },
          };
        }
        return <String, dynamic>{'@type': 'ok'};
      },
    );
    final client = TdlibTelegramClient(gateway);
    addTearDown(() async {
      await client.close();
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    const item = MediaItem(
      id: '-1001:70:77',
      chatId: -1001,
      messageId: 70,
      fileId: 77,
      title: 'Background Track',
      fileName: 'track.mp3',
      mimeType: 'audio/mpeg',
      size: 8,
      kind: MediaKind.audio,
    );
    final bytes = await client.readFileRange(item, 0, 3);
    await Future<void>.delayed(Duration.zero);

    expect(bytes, orderedEquals(<int>[10, 20, 30, 40]));
    expect(
      gateway.requestTypes.where((type) => type == 'downloadFile').length,
      2,
    );
  });

  test('full media scan paginates through the complete channel history', () async {
    var historyCalls = 0;
    final gateway = _FakeTdlibGateway(
      requestHandler: (request) {
        switch (request.getConstructor()) {
          case 'getChat':
            return <String, dynamic>{
              '@type': 'chat',
              'id': -1001234567890,
              'title': 'Complete Music Collection',
            };
          case 'getChatHistory':
            historyCalls += 1;
            final ids = switch (historyCalls) {
              1 => List<int>.generate(100, (index) => 200 - index),
              2 => List<int>.generate(100, (index) => 101 - index),
              _ => const <int>[2],
            };
            return <String, dynamic>{
              '@type': 'messages',
              'messages': ids.map(_audioMessage).toList(growable: false),
            };
          default:
            return <String, dynamic>{'@type': 'ok'};
        }
      },
    );
    final client = TdlibTelegramClient(gateway);
    final progress = <MediaScanProgress>[];
    addTearDown(client.close);

    final items = await client.listAllMedia(
      channelIds: const <int>[-1001234567890],
      onProgress: progress.add,
    );

    expect(historyCalls, 3);
    expect(items, hasLength(199));
    expect(progress.last.scannedMessages, 199);
    expect(progress.last.mediaCount, 199);
  });
  test('playback cache cleanup cancels download and deletes TDLib file', () async {
    final gateway = _FakeTdlibGateway(
      requestHandler: (request) {
        return switch (request.getConstructor()) {
          'getMessage' => _audioMessage(42),
          'cancelDownloadFile' || 'deleteFile' => <String, dynamic>{'@type': 'ok'},
          _ => <String, dynamic>{'@type': 'ok'},
        };
      },
    );
    final client = TdlibTelegramClient(gateway);
    addTearDown(client.close);

    const item = MediaItem(
      id: 'song-42',
      chatId: -1001234567890,
      messageId: 42,
      fileId: 1042,
      title: 'Track 42',
      fileName: 'Track 42.flac',
      mimeType: 'audio/flac',
      size: 42000000,
      kind: MediaKind.audio,
    );

    await client.clearPlaybackCache(item);

    expect(
      gateway.requestTypes,
      <String>['getMessage', 'cancelDownloadFile', 'deleteFile'],
    );
  });

}

Map<String, dynamic> _audioMessage(int id) => <String, dynamic>{
      '@type': 'message',
      'id': id,
      'content': <String, dynamic>{
        '@type': 'messageAudio',
        'audio': <String, dynamic>{
          '@type': 'audio',
          'duration': 180,
          'title': 'Track $id',
          'performer': 'Artist',
          'file_name': 'Track $id.flac',
          'mime_type': 'audio/flac',
          'audio': <String, dynamic>{
            '@type': 'file',
            'id': 1000 + id,
            'size': 42000000,
            'expected_size': 42000000,
            'local': <String, dynamic>{'path': ''},
          },
        },
      },
    };

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
    this.requestHandler,
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
  final FutureOr<Map<String, dynamic>> Function(td.TdFunction request)?
      requestHandler;

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
    final handler = requestHandler;
    if (handler != null) {
      return handler(request);
    }
    return <String, dynamic>{'@type': 'ok'};
  }

  @override
  Future<void> close() async {
    _initialized = false;
    await _updates.close();
  }
}
