import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_media_player/src/features/update/data/app_update_service.dart';
import 'package:telegram_media_player/src/features/update/models/app_update.dart';

void main() {
  group('AppVersion', () {
    test('compares stable and prerelease semantic versions', () {
      final stable = AppVersion.tryParse('v1.2.0')!;
      final beta = AppVersion.tryParse('1.2.0-beta.2')!;
      final older = AppVersion.tryParse('1.1.9')!;

      expect(stable.compareTo(beta), greaterThan(0));
      expect(beta.compareTo(older), greaterThan(0));
      expect(AppVersion.tryParse('build-42'), isNull);
    });
  });

  group('AppUpdateService', () {
    test(
      'selects a newer stable release and the universal Android APK',
      () async {
        final service = AppUpdateService(
          repository: 'example/teleplayer',
          platform: UpdatePlatform.android,
          installedVersionLoader: () async => '1.1.0',
          releaseLoader: (uri) async {
            expect(uri.host, 'api.github.com');
            expect(uri.path, '/repos/example/teleplayer/releases/latest');
            return <Object?>[
              _release(tag: 'build-82', prerelease: true),
              _release(tag: 'v1.2.0-beta.1', prerelease: true),
              _release(
                tag: 'v1.2.0',
                body: '## What\'s Changed\n'
                    '* Faster Telegram downloads\n'
                    '* New changelog screen\n'
                    '**Full Changelog**: '
                    'https://github.com/example/teleplayer',
                assets: <Object?>[
                  _asset('TelePlayer-v1.2.0-arm64.apk'),
                  _asset('TelePlayer-v1.2.0.apk'),
                ],
              ),
            ];
          },
        );

        final result = await service.checkForUpdate();

        expect(result.currentVersion, '1.1.0');
        expect(result.update, isNotNull);
        expect(result.update!.version, '1.2.0');
        expect(
          result.update!.downloadUri.path,
          '/example/teleplayer/releases/download/v1.2.0/'
          'TelePlayer-v1.2.0.apk',
        );
        expect(result.update!.isDirectDownload, isTrue);
        expect(
          result.update!.changes,
          <String>['Faster Telegram downloads', 'New changelog screen'],
        );
      },
    );

    test(
      'selects the Windows installer instead of another executable',
      () async {
        final service = AppUpdateService(
          repository: 'example/teleplayer',
          platform: UpdatePlatform.windows,
          installedVersionLoader: () async => '1.0.0',
          releaseLoader: (_) async => <Object?>[
            _release(
              tag: 'v1.1.0',
              assets: <Object?>[
                _asset('teleplayer.exe'),
                _asset('TelePlayer-v1.1.0-Setup.exe'),
              ],
            ),
          ],
        );

        final result = await service.checkForUpdate();

        expect(
          result.update!.downloadUri.path,
          endsWith('/TelePlayer-v1.1.0-Setup.exe'),
        );
      },
    );

    test('reports up to date when no newer stable version exists', () async {
      final service = AppUpdateService(
        repository: 'example/teleplayer',
        installedVersionLoader: () async => '1.2.0',
        releaseLoader: (_) async => <Object?>[
          _release(tag: 'v1.2.0'),
          _release(tag: 'v1.1.0'),
        ],
      );

      final result = await service.checkForUpdate();

      expect(result.update, isNull);
    });

    test(
      'falls back to the release page when no installer is present',
      () async {
        final service = AppUpdateService(
          repository: 'example/teleplayer',
          platform: UpdatePlatform.windows,
          installedVersionLoader: () async => '1.0.0',
          releaseLoader: (_) async => <Object?>[
            _release(
              tag: 'v1.1.0',
              assets: <Object?>[_asset('teleplayer.exe')],
            ),
          ],
        );

        final result = await service.checkForUpdate();

        expect(result.update!.isDirectDownload, isFalse);
        expect(
          result.update!.downloadUri,
          result.update!.releasePageUri,
        );
      },
    );

    test('opens the selected download URL externally', () async {
      Uri? openedUri;
      final service = AppUpdateService(
        repository: 'example/teleplayer',
        externalUrlLauncher: (uri) async {
          openedUri = uri;
          return true;
        },
      );
      final update = AppUpdate(
        version: '1.2.0',
        tagName: 'v1.2.0',
        title: 'TelePlayer v1.2.0',
        publishedAt: null,
        changes: const <String>['Update'],
        releasePageUri: Uri.parse(
          'https://github.com/example/teleplayer/releases/tag/v1.2.0',
        ),
        downloadUri: Uri.parse(
          'https://github.com/example/teleplayer/releases/download/'
          'v1.2.0/TelePlayer-v1.2.0.apk',
        ),
        isDirectDownload: true,
        prerelease: false,
      );

      await service.openUpdate(update);

      expect(openedUri, update.downloadUri);
    });
  });
}

Map<String, Object?> _release({
  required String tag,
  bool prerelease = false,
  String body = '* General improvements',
  List<Object?> assets = const <Object?>[],
}) {
  return <String, Object?>{
    'draft': false,
    'prerelease': prerelease,
    'tag_name': tag,
    'name': 'TelePlayer $tag',
    'published_at': '2026-08-16T08:00:00Z',
    'body': body,
    'html_url': 'https://github.com/example/teleplayer/releases/tag/$tag',
    'assets': assets,
  };
}

Map<String, Object?> _asset(String name) {
  final version = name.contains('v1.1.0') ? 'v1.1.0' : 'v1.2.0';
  return <String, Object?>{
    'name': name,
    'browser_download_url':
        'https://github.com/example/teleplayer/releases/download/$version/$name',
  };
}
