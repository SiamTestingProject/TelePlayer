import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/app_update.dart';

typedef ReleaseLoader = Future<List<Object?>> Function(Uri uri);
typedef InstalledVersionLoader = Future<String> Function();
typedef ExternalUrlLauncher = Future<bool> Function(Uri uri);
typedef UpdateDownloadDirectoryLoader = Future<Directory> Function();
typedef UpdateDownloadProgressCallback = void Function(
  AppUpdateDownloadProgress progress,
);

enum UpdatePlatform { android, windows, other }

class AppUpdateException implements Exception {
  const AppUpdateException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AppUpdateService {
  AppUpdateService({
    String? repository,
    ReleaseLoader? releaseLoader,
    InstalledVersionLoader? installedVersionLoader,
    ExternalUrlLauncher? externalUrlLauncher,
    UpdateDownloadDirectoryLoader? downloadDirectoryLoader,
    UpdatePlatform? platform,
  })  : repository = repository ??
            const String.fromEnvironment('GITHUB_REPOSITORY'),
        _releaseLoader = releaseLoader ?? _loadGitHubReleases,
        _installedVersionLoader =
            installedVersionLoader ?? _loadInstalledVersion,
        _externalUrlLauncher = externalUrlLauncher ?? _launchExternally,
        _downloadDirectoryLoader =
            downloadDirectoryLoader ?? _defaultDownloadDirectory,
        platform = platform ?? _detectPlatform();

  final String repository;
  final ReleaseLoader _releaseLoader;
  final InstalledVersionLoader _installedVersionLoader;
  final ExternalUrlLauncher _externalUrlLauncher;
  final UpdateDownloadDirectoryLoader _downloadDirectoryLoader;
  final UpdatePlatform platform;

  Future<AppUpdateCheckResult> checkForUpdate() async {
    final repositoryName = _validatedRepository();
    final installedVersionText = await _installedVersionLoader();
    final installedVersion = AppVersion.tryParse(installedVersionText);
    if (installedVersion == null) {
      throw const AppUpdateException(
        'The installed TelePlayer version could not be read.',
      );
    }

    final releasesUri = Uri.https(
      'api.github.com',
      '/repos/$repositoryName/releases/latest',
    );
    final releases = await _releaseLoader(releasesUri);
    AppUpdate? newestUpdate;
    AppVersion? newestVersion;

    for (final releaseValue in releases) {
      if (releaseValue is! Map) {
        continue;
      }
      final release = Map<String, Object?>.from(releaseValue);
      if (release['draft'] == true || release['prerelease'] == true) {
        continue;
      }
      final tagName = release['tag_name']?.toString() ?? '';
      final releaseVersion = AppVersion.tryParse(tagName);
      if (releaseVersion == null ||
          releaseVersion.compareTo(installedVersion) <= 0 ||
          (newestVersion != null &&
              releaseVersion.compareTo(newestVersion) <= 0)) {
        continue;
      }
      final parsed = _parseRelease(release, releaseVersion);
      if (parsed != null) {
        newestUpdate = parsed;
        newestVersion = releaseVersion;
      }
    }

    return AppUpdateCheckResult(
      currentVersion: installedVersion.display,
      hasPublishedRelease: releases.isNotEmpty,
      update: newestUpdate,
    );
  }

  Future<void> openUpdate(AppUpdate update) async {
    final launched = await _externalUrlLauncher(update.downloadUri);
    if (!launched) {
      throw const AppUpdateException(
        'The update download could not be opened.',
      );
    }
  }

  Future<String> downloadAsset(
    AppUpdateAsset asset, {
    required UpdateDownloadProgressCallback onProgress,
  }) async {
    if (asset.uri.scheme != 'https') {
      throw const AppUpdateException('The update download URL is invalid.');
    }

    final root = await _downloadDirectoryLoader();
    final updatesDirectory = Directory(
      '${root.path}${Platform.pathSeparator}TelePlayer${Platform.pathSeparator}updates',
    );
    await updatesDirectory.create(recursive: true);

    final safeName = asset.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final target = File(
      '${updatesDirectory.path}${Platform.pathSeparator}$safeName',
    );
    final partial = File('${target.path}.part');
    if (await partial.exists()) {
      await partial.delete();
    }

    final client = HttpClient();
    IOSink? sink;
    try {
      final request = await client
          .getUrl(asset.uri)
          .timeout(const Duration(seconds: 20));
      request.headers
        ..set(HttpHeaders.userAgentHeader, 'TelePlayer')
        ..set(HttpHeaders.acceptHeader, 'application/octet-stream');
      final response = await request
          .close()
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != HttpStatus.ok) {
        throw AppUpdateException(
          'GitHub could not download this update (${response.statusCode}).',
        );
      }

      final responseLength = response.contentLength;
      final totalBytes = responseLength > 0 ? responseLength : asset.sizeBytes;
      var receivedBytes = 0;
      var lastBytes = 0;
      var lastTick = DateTime.now();
      var smoothedSpeed = 0.0;
      var lastNotification = DateTime.fromMillisecondsSinceEpoch(0);
      sink = partial.openWrite();

      onProgress(
        AppUpdateDownloadProgress(
          receivedBytes: 0,
          totalBytes: totalBytes,
          bytesPerSecond: 0,
          isComplete: false,
        ),
      );

      await for (final chunk in response) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        final now = DateTime.now();
        final speedElapsed = now.difference(lastTick).inMilliseconds;
        if (speedElapsed >= 400) {
          final instantSpeed =
              (receivedBytes - lastBytes) * 1000.0 / speedElapsed;
          smoothedSpeed = smoothedSpeed == 0
              ? instantSpeed
              : (smoothedSpeed * 0.65) + (instantSpeed * 0.35);
          lastBytes = receivedBytes;
          lastTick = now;
        }
        if (now.difference(lastNotification).inMilliseconds >= 100) {
          lastNotification = now;
          onProgress(
            AppUpdateDownloadProgress(
              receivedBytes: receivedBytes,
              totalBytes: totalBytes,
              bytesPerSecond: smoothedSpeed,
              isComplete: false,
            ),
          );
        }
      }

      await sink.flush();
      await sink.close();
      sink = null;
      if (await target.exists()) {
        await target.delete();
      }
      await partial.rename(target.path);
      onProgress(
        AppUpdateDownloadProgress(
          receivedBytes: receivedBytes,
          totalBytes: totalBytes ?? receivedBytes,
          bytesPerSecond: smoothedSpeed,
          isComplete: true,
          localPath: target.path,
        ),
      );
      return target.path;
    } on AppUpdateException {
      rethrow;
    } on TimeoutException {
      throw const AppUpdateException('The update download timed out.');
    } on SocketException {
      throw const AppUpdateException(
        'The internet connection was interrupted while downloading the update.',
      );
    } catch (_) {
      throw const AppUpdateException('TelePlayer could not download the update.');
    } finally {
      await sink?.close();
      if (await partial.exists()) {
        await partial.delete();
      }
      client.close(force: true);
    }
  }

  String _validatedRepository() {
    final value = repository.trim();
    final match = RegExp(
      r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$',
    ).firstMatch(value);
    if (match == null) {
      throw const AppUpdateException(
        'Update checks are unavailable in this local build.',
      );
    }
    return value;
  }

  AppUpdate? _parseRelease(
    Map<String, Object?> release,
    AppVersion releaseVersion,
  ) {
    final releasePageUri = _trustedGitHubUri(release['html_url']);
    if (releasePageUri == null) {
      return null;
    }
    final assets = _parseAssets(release['assets']);
    final selectedAsset = _selectAsset(assets);
    final tagName = release['tag_name']?.toString() ?? releaseVersion.display;
    final title = _cleanText(release['name']?.toString() ?? '');
    final publishedAt = DateTime.tryParse(
      release['published_at']?.toString() ?? '',
    );
    return AppUpdate(
      version: releaseVersion.display,
      tagName: tagName,
      title: title.isEmpty ? 'TelePlayer $tagName' : title,
      publishedAt: publishedAt,
      changes: _parseChanges(release['body']?.toString() ?? ''),
      releasePageUri: releasePageUri,
      downloadUri: selectedAsset?.uri ?? releasePageUri,
      isDirectDownload: selectedAsset != null,
      prerelease: release['prerelease'] == true,
      assets: assets,
    );
  }

  List<AppUpdateAsset> _parseAssets(Object? value) {
    if (value is! List) {
      return const <AppUpdateAsset>[];
    }
    final assets = <AppUpdateAsset>[];
    for (final assetValue in value) {
      if (assetValue is! Map) {
        continue;
      }
      final asset = Map<String, Object?>.from(assetValue);
      final name = asset['name']?.toString().trim() ?? '';
      final uri = _trustedGitHubUri(asset['browser_download_url']);
      if (name.isEmpty || uri == null) {
        continue;
      }
      final lowerName = name.toLowerCase();
      final type = _assetType(lowerName);
      if (type == AppUpdateAssetType.other) {
        continue;
      }
      final rawSize = asset['size'];
      final size = rawSize is int ? rawSize : int.tryParse(rawSize?.toString() ?? '');
      assets.add(
        AppUpdateAsset(
          name: name,
          uri: uri,
          sizeBytes: size,
          type: type,
        ),
      );
    }
    return List<AppUpdateAsset>.unmodifiable(assets);
  }

  AppUpdateAssetType _assetType(String lowerName) {
    if (platform == UpdatePlatform.android && lowerName.endsWith('.apk')) {
      if (lowerName.contains('arm64')) {
        return AppUpdateAssetType.arm64;
      }
      if (lowerName.contains('armeabi') || lowerName.contains('arm32')) {
        return AppUpdateAssetType.arm32;
      }
      if (lowerName.contains('x86_64') || lowerName.contains('x86-64')) {
        return AppUpdateAssetType.x86_64;
      }
      return AppUpdateAssetType.universal;
    }
    if (platform == UpdatePlatform.windows &&
        lowerName.endsWith('.exe') &&
        lowerName.contains('setup')) {
      return AppUpdateAssetType.windowsInstaller;
    }
    return AppUpdateAssetType.other;
  }

  AppUpdateAsset? _selectAsset(List<AppUpdateAsset> assets) {
    final preferredTypes = switch (platform) {
      UpdatePlatform.android => const <AppUpdateAssetType>[
          AppUpdateAssetType.arm64,
          AppUpdateAssetType.universal,
          AppUpdateAssetType.arm32,
          AppUpdateAssetType.x86_64,
        ],
      UpdatePlatform.windows => const <AppUpdateAssetType>[
          AppUpdateAssetType.windowsInstaller,
        ],
      UpdatePlatform.other => const <AppUpdateAssetType>[],
    };
    for (final type in preferredTypes) {
      for (final asset in assets) {
        if (asset.type == type) {
          return asset;
        }
      }
    }
    return null;
  }

  static Future<List<Object?>> _loadGitHubReleases(Uri uri) async {
    final client = HttpClient();
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 15));
      request.headers
        ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
        ..set(HttpHeaders.userAgentHeader, 'TelePlayer')
        ..set('X-GitHub-Api-Version', '2022-11-28');
      final response = await request
          .close()
          .timeout(const Duration(seconds: 15));
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 15));
      return decodeGitHubReleaseResponse(
        statusCode: response.statusCode,
        body: body,
      );
    } on AppUpdateException {
      rethrow;
    } on TimeoutException {
      throw const AppUpdateException('The update check timed out.');
    } on SocketException {
      throw const AppUpdateException(
        'Connect to the internet to check for updates.',
      );
    } on FormatException {
      throw const AppUpdateException(
        'GitHub returned an invalid update response.',
      );
    } finally {
      client.close(force: true);
    }
  }

  static Future<String> _loadInstalledVersion() async {
    final info = await PackageInfo.fromPlatform();
    return info.version;
  }

  static Future<Directory> _defaultDownloadDirectory() async {
    if (Platform.isAndroid) {
      return getApplicationSupportDirectory();
    }
    final downloads = await getDownloadsDirectory();
    return downloads ?? getApplicationSupportDirectory();
  }

  static Future<bool> _launchExternally(Uri uri) {
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static UpdatePlatform _detectPlatform() {
    if (Platform.isAndroid) {
      return UpdatePlatform.android;
    }
    if (Platform.isWindows) {
      return UpdatePlatform.windows;
    }
    return UpdatePlatform.other;
  }

  static Uri? _trustedGitHubUri(Object? value) {
    final uri = Uri.tryParse(value?.toString() ?? '');
    if (uri == null || uri.scheme != 'https') {
      return null;
    }
    final host = uri.host.toLowerCase();
    if (host == 'github.com' ||
        host.endsWith('.github.com') ||
        host.endsWith('.githubusercontent.com')) {
      return uri;
    }
    return null;
  }

  static List<String> _parseChanges(String body) {
    final changes = <String>[];
    final seen = <String>{};
    for (final rawLine in const LineSplitter().convert(body)) {
      var line = rawLine.trim();
      if (line.isEmpty ||
          line.startsWith('#') ||
          line.startsWith('<!--') ||
          line.toLowerCase().contains('full changelog')) {
        continue;
      }

      line = line.replaceFirst(
        RegExp(r'^(?:[-*+] |\d+[.)] )(?:\[[ xX]\] )?'),
        '',
      );
      line = line
          .replaceAllMapped(
            RegExp(r'\[([^\]]+)\]\([^)]+\)'),
            (match) => match.group(1)!,
          )
          .replaceAll(RegExp(r'[*_`]'), '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (line.isEmpty || line.startsWith('http://') || line.startsWith('https://')) {
        continue;
      }
      if (line.length > 280) {
        line = '${line.substring(0, 277)}...';
      }
      if (seen.add(line)) {
        changes.add(line);
      }
      if (changes.length == 14) {
        break;
      }
    }
    return List<String>.unmodifiable(
      changes.isEmpty
          ? const <String>['Release notes were not provided for this version.']
          : changes,
    );
  }

  static String _cleanText(String value) {
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}

List<Object?> decodeGitHubReleaseResponse({
  required int statusCode,
  required String body,
}) {
  if (statusCode == HttpStatus.notFound) {
    return const <Object?>[];
  }
  if (statusCode != HttpStatus.ok) {
    throw AppUpdateException(
      statusCode == HttpStatus.forbidden
          ? 'GitHub temporarily limited update checks. Try again later.'
          : 'GitHub could not check for updates ($statusCode).',
    );
  }
  final decoded = jsonDecode(body);
  if (decoded is! Map) {
    throw const AppUpdateException(
      'GitHub returned an invalid update response.',
    );
  }
  return <Object?>[decoded];
}
