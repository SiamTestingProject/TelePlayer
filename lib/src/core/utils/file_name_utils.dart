class FileNameUtils {
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
