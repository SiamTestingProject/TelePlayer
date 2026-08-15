import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_media_player/src/core/utils/byte_range.dart';

void main() {
  test('parses full range when header is absent', () {
    final range = ByteRange.parse(null, 100);
    expect(range.start, 0);
    expect(range.end, 99);
    expect(range.length, 100);
    expect(range.isPartial, isFalse);
  });

  test('parses open-ended range', () {
    final range = ByteRange.parse('bytes=25-', 100);
    expect(range.start, 25);
    expect(range.end, 99);
    expect(range.contentRange, 'bytes 25-99/100');
  });

  test('parses suffix range', () {
    final range = ByteRange.parse('bytes=-20', 100);
    expect(range.start, 80);
    expect(range.end, 99);
  });

  test('rejects unsatisfiable ranges', () {
    expect(() => ByteRange.parse('bytes=100-120', 100), throwsFormatException);
  });
}
