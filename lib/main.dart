import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'src/app/app_bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (defaultTargetPlatform == TargetPlatform.android) {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.siam.teleplayer.playback',
      androidNotificationChannelName: 'TelePlayer playback',
      androidNotificationChannelDescription:
          'Background audio playback and media controls',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: false,
    );
  }
  final bootstrap = await AppBootstrap.create();
  runApp(bootstrap.buildApp());
}
