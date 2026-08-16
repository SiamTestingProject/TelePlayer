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
}

class AppUpdateCheckResult {
  const AppUpdateCheckResult({
    required this.currentVersion,
    required this.update,
  });

  final String currentVersion;
  final AppUpdate? update;
}
