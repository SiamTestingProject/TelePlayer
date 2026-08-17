class AppVersion implements Comparable<AppVersion> {
  const AppVersion._({
    required this.numbers,
    required this.preRelease,
    required this.display,
  });

  final List<int> numbers;
  final List<String> preRelease;
  final String display;

  static AppVersion? tryParse(String input) {
    var value = input.trim();
    if (value.startsWith('v') || value.startsWith('V')) {
      value = value.substring(1);
    }
    value = value.split('+').first;
    final match = RegExp(
      r'^(\d+)\.(\d+)\.(\d+)(?:\.(\d+))?(?:-([0-9A-Za-z.-]+))?$',
    ).firstMatch(value);
    if (match == null) {
      return null;
    }

    final numbers = <int>[
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      if (match.group(4) != null) int.parse(match.group(4)!),
    ];
    final preRelease = match.group(5)?.split('.') ?? const <String>[];
    return AppVersion._(
      numbers: List<int>.unmodifiable(numbers),
      preRelease: List<String>.unmodifiable(preRelease),
      display: value,
    );
  }

  @override
  int compareTo(AppVersion other) {
    final length = numbers.length > other.numbers.length
        ? numbers.length
        : other.numbers.length;
    for (var index = 0; index < length; index++) {
      final left = index < numbers.length ? numbers[index] : 0;
      final right = index < other.numbers.length ? other.numbers[index] : 0;
      if (left != right) {
        return left.compareTo(right);
      }
    }

    if (preRelease.isEmpty && other.preRelease.isNotEmpty) {
      return 1;
    }
    if (preRelease.isNotEmpty && other.preRelease.isEmpty) {
      return -1;
    }
    final preReleaseLength = preRelease.length > other.preRelease.length
        ? preRelease.length
        : other.preRelease.length;
    for (var index = 0; index < preReleaseLength; index++) {
      if (index >= preRelease.length) {
        return -1;
      }
      if (index >= other.preRelease.length) {
        return 1;
      }
      final left = preRelease[index];
      final right = other.preRelease[index];
      if (left == right) {
        continue;
      }
      final leftNumber = int.tryParse(left);
      final rightNumber = int.tryParse(right);
      if (leftNumber != null && rightNumber != null) {
        return leftNumber.compareTo(rightNumber);
      }
      if (leftNumber != null) {
        return -1;
      }
      if (rightNumber != null) {
        return 1;
      }
      return left.compareTo(right);
    }
    return 0;
  }
}

enum AppUpdateAssetType {
  universal,
  arm64,
  arm32,
  x86_64,
  windowsInstaller,
  other,
}

class AppUpdateAsset {
  const AppUpdateAsset({
    required this.name,
    required this.uri,
    required this.sizeBytes,
    required this.type,
  });

  final String name;
  final Uri uri;
  final int? sizeBytes;
  final AppUpdateAssetType type;

  String get label => switch (type) {
        AppUpdateAssetType.arm64 => 'ARM64',
        AppUpdateAssetType.arm32 => 'ARM32',
        AppUpdateAssetType.x86_64 => 'x86_64',
        AppUpdateAssetType.universal => 'Universal',
        AppUpdateAssetType.windowsInstaller => 'Windows',
        AppUpdateAssetType.other => name,
      };
}

class AppUpdateDownloadProgress {
  const AppUpdateDownloadProgress({
    required this.receivedBytes,
    required this.totalBytes,
    required this.bytesPerSecond,
    required this.isComplete,
    this.localPath,
  });

  final int receivedBytes;
  final int? totalBytes;
  final double bytesPerSecond;
  final bool isComplete;
  final String? localPath;

  double? get fraction {
    final total = totalBytes;
    if (total == null || total <= 0) {
      return null;
    }
    return (receivedBytes / total).clamp(0.0, 1.0).toDouble();
  }
}

class AppUpdate {
  const AppUpdate({
    required this.version,
    required this.tagName,
    required this.title,
    required this.publishedAt,
    required this.changes,
    required this.releasePageUri,
    required this.downloadUri,
    required this.isDirectDownload,
    required this.prerelease,
    this.assets = const <AppUpdateAsset>[],
  });

  final String version;
  final String tagName;
  final String title;
  final DateTime? publishedAt;
  final List<String> changes;
  final Uri releasePageUri;
  final Uri downloadUri;
  final bool isDirectDownload;
  final bool prerelease;
  final List<AppUpdateAsset> assets;

  List<AppUpdateAsset> get androidAssets => assets
      .where(
        (asset) => const <AppUpdateAssetType>{
          AppUpdateAssetType.universal,
          AppUpdateAssetType.arm64,
          AppUpdateAssetType.arm32,
          AppUpdateAssetType.x86_64,
        }.contains(asset.type),
      )
      .toList(growable: false);

  AppUpdateAsset? get preferredAndroidAsset {
    final android = androidAssets;
    for (final type in const <AppUpdateAssetType>[
      AppUpdateAssetType.arm64,
      AppUpdateAssetType.universal,
      AppUpdateAssetType.arm32,
      AppUpdateAssetType.x86_64,
    ]) {
      for (final asset in android) {
        if (asset.type == type) {
          return asset;
        }
      }
    }
    return null;
  }
}

class AppUpdateCheckResult {
  const AppUpdateCheckResult({
    required this.currentVersion,
    required this.hasPublishedRelease,
    required this.update,
  });

  final String currentVersion;
  final bool hasPublishedRelease;
  final AppUpdate? update;
}
