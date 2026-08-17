import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_media_player/src/features/update/application/app_update_controller.dart';
import 'package:telegram_media_player/src/features/update/data/app_update_service.dart';
import 'package:telegram_media_player/src/features/update/models/app_update.dart';
import 'package:telegram_media_player/src/features/update/presentation/app_update_sheet.dart';

void main() {
  testWidgets('shows the release changelog in a draggable sheet', (tester) async {
    final controller = AppUpdateController(
      AppUpdateService(repository: 'example/teleplayer'),
    );
    final update = AppUpdate(
      version: '1.2.0',
      tagName: 'v1.2.0',
      title: 'TelePlayer v1.2.0',
      publishedAt: DateTime.utc(2026, 8, 16),
      changes: const <String>[
        'Added automatic update checks.',
        'Improved Telegram playback.',
      ],
      releasePageUri: Uri.parse(
        'https://github.com/example/teleplayer/releases/tag/v1.2.0',
      ),
      downloadUri: Uri.parse(
        'https://github.com/example/teleplayer/releases/download/'
        'v1.2.0/TelePlayer-v1.2.0.apk',
      ),
      isDirectDownload: true,
      prerelease: false,
      assets: <AppUpdateAsset>[
        AppUpdateAsset(
          name: 'TelePlayer-v1.2.0-arm64.apk',
          uri: Uri.parse(
            'https://github.com/example/teleplayer/releases/download/'
            'v1.2.0/TelePlayer-v1.2.0-arm64.apk',
          ),
          sizeBytes: 41000000,
          type: AppUpdateAssetType.arm64,
        ),
        AppUpdateAsset(
          name: 'TelePlayer-v1.2.0-armeabi-v7a.apk',
          uri: Uri.parse(
            'https://github.com/example/teleplayer/releases/download/'
            'v1.2.0/TelePlayer-v1.2.0-armeabi-v7a.apk',
          ),
          sizeBytes: 33000000,
          type: AppUpdateAssetType.arm32,
        ),
      ],
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => unawaited(
                    showAppUpdateSheet(
                      context,
                      controller: controller,
                      update: update,
                    ),
                  ),
                  child: const Text('Show update'),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Show update'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Changelog'), findsOneWidget);
    expect(find.text('v1.2.0'), findsOneWidget);

    await tester.ensureVisible(find.text('Choose Android version'));
    await tester.pump();
    expect(find.textContaining('ARM64'), findsWidgets);
    expect(find.textContaining('ARM32'), findsWidgets);

    await tester.ensureVisible(find.text("What's New"));
    await tester.pump();
    expect(find.text("What's New"), findsOneWidget);

    await tester.ensureVisible(find.text('Added automatic update checks.'));
    await tester.pump();
    expect(find.text('Added automatic update checks.'), findsOneWidget);
  });
}
