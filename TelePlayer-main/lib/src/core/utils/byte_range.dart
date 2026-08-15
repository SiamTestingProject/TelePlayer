class ByteRange {
  const ByteRange({required this.start, required this.end, required this.total});

  final int start;
  final int end;
  final int total;

  int get length => end - start + 1;
  bool get isPartial => start != 0 || end != total - 1;

  String get contentRange => 'bytes $start-$end/$total';

  static ByteRange parse(String? header, int total) {
    if (total <= 0) {
      throw const FormatException('Total size must be positive.');
    }
    if (header == null || header.trim().isEmpty) {
      return ByteRange(start: 0, end: total - 1, total: total);
    }
    final value = header.trim().toLowerCase();
    if (!value.startsWith('bytes=')) {
      throw const FormatException('Unsupported range unit.');
    }
    final parts = value.substring(6).split('-');
    if (parts.length != 2) {
      throw const FormatException('Invalid range format.');
    }

    final rawStart = parts[0].trim();
    final rawEnd = parts[1].trim();
    late int start;
    late int end;
    if (rawStart.isEmpty) {
      final suffixLength = int.parse(rawEnd);
      if (suffixLength <= 0) {
        throw const FormatException('Invalid suffix range.');
      }
      start = (total - suffixLength).clamp(0, total - 1);
      end = total - 1;
    } else {
      start = int.parse(rawStart);
      end = rawEnd.isEmpty ? total - 1 : int.parse(rawEnd);
    }

    if (start < 0 || start >= total || end < start) {
      throw const FormatException('Range not satisfiable.');
    }
    if (end >= total) {
      end = total - 1;
    }
    return ByteRange(start: start, end: end, total: total);
  }
}
