import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/app_update.dart';

typedef ReleaseLoader = Future<List<Object?>> Function(Uri uri);
typedef InstalledVersionLoader = Future<String> Function();
typedef ExternalUrlLauncher = Future<bool> Function(Uri uri);

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
    UpdatePlatform? platform,
  })  : repository = repository ??
            const String.fromEnvironment('GITHUB_REPOSITORY'),
        _releaseLoader = releaseLoader ?? _loadGitHubReleases,
        _installedVersionLoader =
            installedVersionLoader ?? _loadInstalledVersion,
        _externalUrlLauncher = externalUrlLauncher ?? _launchExternally,
        platform = platform ?? _detectPlatform();

  final String repository;
  final ReleaseLoader _releaseLoader;
  final InstalledVersionLoader _installedVersionLoader;
  final ExternalUrlLauncher _externalUrlLauncher;
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
    final selectedAsset = _selectAsset(release['assets']);
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
      downloadUri: selectedAsset ?? releasePageUri,
      isDirectDownload: selectedAsset != null,
      prerelease: release['prerelease'] == true,
    );
  }

  Uri? _selectAsset(Object? value) {
    if (value is! List) {
      return null;
    }
    final candidates = <({String name, Uri uri, int score})>[];
    for (final assetValue in value) {
      if (assetValue is! Map) {
        continue;
      }
      final asset = Map<String, Object?>.from(assetValue);
      final name = asset['name']?.toString().trim() ?? '';
      final lowerName = name.toLowerCase();
      final uri = _trustedGitHubUri(asset['browser_download_url']);
      if (name.isEmpty || uri == null) {
        continue;
      }

      if (platform == UpdatePlatform.android && lowerName.endsWith('.apk')) {
        final isAbiSpecific = lowerName.contains('arm64') ||
            lowerName.contains('armeabi') ||
            lowerName.contains('x86_64') ||
            lowerName.contains('x86-64');
        if (!isAbiSpecific) {
          candidates.add((name: name, uri: uri, score: 100));
        }
      } else if (platform == UpdatePlatform.windows &&
          lowerName.endsWith('.exe') &&
          lowerName.contains('setup')) {
        candidates.add((name: name, uri: uri, score: 100));
      }
    }

    if (candidates.isEmpty) {
      return null;
    }
    candidates.sort((left, right) {
      final score = right.score.compareTo(left.score);
      return score != 0 ? score : left.name.compareTo(right.name);
    });
    return candidates.first.uri;
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
      if (response.statusCode != HttpStatus.ok) {
        throw AppUpdateException(
          response.statusCode == HttpStatus.forbidden
              ? 'GitHub temporarily limited update checks. Try again later.'
              : 'GitHub could not check for updates (${response.statusCode}).',
        );
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map) {
        throw const AppUpdateException(
          'GitHub returned an invalid update response.',
        );
      }
      return <Object?>[decoded];
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
    for (final rawLine in const LineSplitter().convert(body)) {
      var line = rawLine.trim();
      if (line.isEmpty ||
          line.startsWith('#') ||
          line.toLowerCase().contains('full changelog')) {
        continue;
      }
      line = line.replaceFirst(
        RegExp(r'^(?:[-*+] |\d+[.)] )(?:\[[ xX]\] )?'),
        '',
      );
      if (line == rawLine.trim() &&
          !rawLine.trimLeft().startsWith(RegExp(r'[-*+]'))) {
        continue;
      }
      line = line
          .replaceAllMapped(
            RegExp(r'\[([^\]]+)\]\([^)]+\)'),
            (match) => match.group(1)!,
          )
          .replaceAll(RegExp(r'[*_`]'), '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (line.isEmpty) {
        continue;
      }
      if (line.length > 220) {
        line = '${line.substring(0, 217)}...';
      }
      changes.add(line);
      if (changes.length == 10) {
        break;
      }
    }
    return List<String>.unmodifiable(
      changes.isEmpty
          ? const <String>['A new TelePlayer release is ready to install.']
          : changes,
    );
  }

  static String _cleanText(String value) {
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
