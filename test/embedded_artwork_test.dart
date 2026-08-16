import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_media_player/src/core/utils/embedded_artwork.dart';

void main() {
  test('extracts the original FLAC METADATA_BLOCK_PICTURE image', () {
    final image = _pngHeader(width: 1200, height: 1200);
    final flac = _flacWithPicture(image);

    final extracted = EmbeddedArtwork.extract(
      flac,
      fileName: 'track.flac',
      mimeType: 'audio/flac',
    );

    expect(extracted, isNotNull);
    expect(extracted, orderedEquals(image));
    final info = EmbeddedArtwork.imageInfo(extracted!);
    expect(info?.width, 1200);
    expect(info?.height, 1200);
    expect(EmbeddedArtwork.isHighResolution(extracted), isTrue);
  });

  test('reads FLAC sample rate for the player metadata pill', () {
    final flac = _flacWithStreamInfo(sampleRateHz: 44100);

    final metadata = EmbeddedArtwork.technicalMetadata(
      flac,
      fileName: 'track.flac',
      mimeType: 'audio/flac',
    );

    expect(metadata?.sampleRateHz, 44100);
  });

  test('identifies a Telegram-sized cover as too small for the player', () {
    final tiny = _pngHeader(width: 96, height: 96);
    final full = _pngHeader(width: 1200, height: 1200);

    expect(EmbeddedArtwork.isHighResolution(tiny), isFalse);
    expect(EmbeddedArtwork.isBetter(full, tiny), isTrue);
  });
}

Uint8List _pngHeader({required int width, required int height}) {
  final bytes = Uint8List(24);
  bytes.setAll(0, const <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  bytes.setAll(8, const <int>[0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52]);
  _write32(bytes, 16, width);
  _write32(bytes, 20, height);
  return bytes;
}

Uint8List _flacWithPicture(Uint8List image) {
  final mime = 'image/png'.codeUnits;
  final block = BytesBuilder();
  block.add(_u32(3)); // front cover
  block.add(_u32(mime.length));
  block.add(mime);
  block.add(_u32(0)); // empty description
  block.add(_u32(1200));
  block.add(_u32(1200));
  block.add(_u32(24));
  block.add(_u32(0));
  block.add(_u32(image.length));
  block.add(image);
  final payload = block.takeBytes();

  final result = BytesBuilder();
  result.add('fLaC'.codeUnits);
  result.add(<int>[
    0x80 | 6,
    (payload.length >> 16) & 0xFF,
    (payload.length >> 8) & 0xFF,
    payload.length & 0xFF,
  ]);
  result.add(payload);
  return result.takeBytes();
}

Uint8List _u32(int value) => Uint8List.fromList(<int>[
      (value >> 24) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 8) & 0xFF,
      value & 0xFF,
    ]);

void _write32(Uint8List bytes, int offset, int value) {
  bytes[offset] = (value >> 24) & 0xFF;
  bytes[offset + 1] = (value >> 16) & 0xFF;
  bytes[offset + 2] = (value >> 8) & 0xFF;
  bytes[offset + 3] = value & 0xFF;
}

Uint8List _flacWithStreamInfo({required int sampleRateHz}) {
  final streamInfo = Uint8List(34);
  streamInfo[10] = (sampleRateHz >> 12) & 0xFF;
  streamInfo[11] = (sampleRateHz >> 4) & 0xFF;
  streamInfo[12] = (sampleRateHz & 0x0F) << 4;
  final result = BytesBuilder();
  result.add('fLaC'.codeUnits);
  result.add(<int>[0x80, 0, 0, streamInfo.length]);
  result.add(streamInfo);
  return result.takeBytes();
}
