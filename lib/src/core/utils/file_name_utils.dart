class FileNameUtils {
  static final RegExp _splitSuffix = RegExp(
    r'\.(mkv|mp4|avi|ts|m4v|mov|wmv|webm|flv|m2ts|mpg|mpeg)\.(\d{2,3})(?=$|\D)',
    caseSensitive: false,
  );

  static final RegExp _separator = RegExp(r'[\.\-_ ]+');

  static bool isSupportedVideoName(String fileName) {
    final lower = fileName.toLowerCase();
    return lower.endsWith('.mkv') ||
        lower.endsWith('.mp4') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.m4v') ||
        lower.endsWith('.avi') ||
        _splitSuffix.hasMatch(lower);
  }

  static bool isSupportedAudioName(String fileName) {
    final lower = fileName.toLowerCase();
    return lower.endsWith('.mp3') ||
        lower.endsWith('.m4a') ||
        lower.endsWith('.aac') ||
        lower.endsWith('.flac') ||
        lower.endsWith('.wav') ||
        lower.endsWith('.ogg') ||
        lower.endsWith('.oga') ||
        lower.endsWith('.opus') ||
        lower.endsWith('.wma') ||
        lower.endsWith('.alac');
  }

  static SplitFileInfo? parseSplitInfo(String fileName) {
    final match = _splitSuffix.firstMatch(fileName.trim());
    if (match == null) {
      return null;
    }
    final extension = match.group(1) ?? 'mkv';
    final part = int.parse(match.group(2)!);
    final base = '${fileName.substring(0, match.start)}.$extension';
    final key = _separator.allMatches(base).isEmpty
        ? base.toLowerCase()
        : base.split(_separator).where((part) => part.isNotEmpty).join('.').toLowerCase();
    return SplitFileInfo(groupKey: key, partNumber: part, displayName: base);
  }

  static String readableBytes(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    if (unit == 0) {
      return '${value.toInt()} ${units[unit]}';
    }
    return '${value.toStringAsFixed(1)} ${units[unit]}';
  }
}

class SplitFileInfo {
  const SplitFileInfo({
    required this.groupKey,
    required this.partNumber,
    required this.displayName,
  });

  final String groupKey;
  final int partNumber;
  final String displayName;
}
