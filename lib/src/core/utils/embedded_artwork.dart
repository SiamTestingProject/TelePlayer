import 'dart:math' as math;
import 'dart:typed_data';

class RasterImageInfo {
  const RasterImageInfo({required this.width, required this.height});

  final int width;
  final int height;

  int get shortestSide => math.min(width, height);
  int get pixelCount => width * height;
}


class AudioTechnicalMetadata {
  const AudioTechnicalMetadata({this.sampleRateHz});

  final int? sampleRateHz;
}

class EmbeddedArtwork {
  const EmbeddedArtwork._();

  static Uint8List? extract(
    Uint8List bytes, {
    required String fileName,
    required String mimeType,
  }) {
    if (bytes.isEmpty) {
      return null;
    }

    final normalizedMime = mimeType.toLowerCase();
    final normalizedName = fileName.toLowerCase();

    if (normalizedMime.contains('flac') || normalizedName.endsWith('.flac')) {
      final flac = _extractFlacPicture(bytes);
      if (flac != null) {
        return flac;
      }
    }

    if (normalizedMime.contains('mpeg') || normalizedName.endsWith('.mp3')) {
      final mp3 = _extractId3Apic(bytes);
      if (mp3 != null) {
        return mp3;
      }
    }

    if (normalizedMime.contains('mp4') ||
        normalizedName.endsWith('.m4a') ||
        normalizedName.endsWith('.mp4')) {
      final mp4 = _extractMp4Cover(bytes);
      if (mp4 != null) {
        return mp4;
      }
    }

    // Some encoders wrap artwork differently than their container's common
    // metadata block. A bounded signature scan is a safe final fallback for
    // the beginning of an audio file, where embedded cover art normally lives.
    return _extractLargestRaster(bytes);
  }

  static AudioTechnicalMetadata? technicalMetadata(
    Uint8List bytes, {
    required String fileName,
    required String mimeType,
  }) {
    final normalizedMime = mimeType.toLowerCase();
    final normalizedName = fileName.toLowerCase();
    if (normalizedMime.contains('flac') || normalizedName.endsWith('.flac')) {
      final sampleRate = _flacSampleRate(bytes);
      return sampleRate == null
          ? null
          : AudioTechnicalMetadata(sampleRateHz: sampleRate);
    }
    if (normalizedMime.contains('mpeg') || normalizedName.endsWith('.mp3')) {
      final sampleRate = _mp3SampleRate(bytes);
      return sampleRate == null
          ? null
          : AudioTechnicalMetadata(sampleRateHz: sampleRate);
    }
    return null;
  }

  static RasterImageInfo? imageInfo(Uint8List bytes) {
    if (bytes.length >= 24 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A) {
      final width = _readUint32(bytes, 16);
      final height = _readUint32(bytes, 20);
      if (width > 0 && height > 0) {
        return RasterImageInfo(width: width, height: height);
      }
    }

    if (bytes.length >= 10 &&
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x38) {
      final width = bytes[6] | (bytes[7] << 8);
      final height = bytes[8] | (bytes[9] << 8);
      if (width > 0 && height > 0) {
        return RasterImageInfo(width: width, height: height);
      }
    }

    if (bytes.length >= 30 &&
        _matchesAscii(bytes, 0, 'RIFF') &&
        _matchesAscii(bytes, 8, 'WEBP')) {
      if (_matchesAscii(bytes, 12, 'VP8X') && bytes.length >= 30) {
        final width = 1 + _readUint24LittleEndian(bytes, 24);
        final height = 1 + _readUint24LittleEndian(bytes, 27);
        return RasterImageInfo(width: width, height: height);
      }
      if (_matchesAscii(bytes, 12, 'VP8L') &&
          bytes.length >= 25 &&
          bytes[20] == 0x2F) {
        final b1 = bytes[21];
        final b2 = bytes[22];
        final b3 = bytes[23];
        final b4 = bytes[24];
        final width = 1 + (b1 | ((b2 & 0x3F) << 8));
        final height =
            1 + ((b2 >> 6) | (b3 << 2) | ((b4 & 0x0F) << 10));
        return RasterImageInfo(width: width, height: height);
      }
      if (_matchesAscii(bytes, 12, 'VP8 ') &&
          bytes.length >= 30 &&
          bytes[23] == 0x9D &&
          bytes[24] == 0x01 &&
          bytes[25] == 0x2A) {
        final width = (bytes[26] | (bytes[27] << 8)) & 0x3FFF;
        final height = (bytes[28] | (bytes[29] << 8)) & 0x3FFF;
        if (width > 0 && height > 0) {
          return RasterImageInfo(width: width, height: height);
        }
      }
    }

    if (bytes.length >= 4 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
      var offset = 2;
      while (offset + 3 < bytes.length) {
        while (offset < bytes.length && bytes[offset] != 0xFF) {
          offset += 1;
        }
        while (offset < bytes.length && bytes[offset] == 0xFF) {
          offset += 1;
        }
        if (offset >= bytes.length) {
          break;
        }
        final marker = bytes[offset];
        offset += 1;
        if (marker == 0xD8 || marker == 0xD9 || (marker >= 0xD0 && marker <= 0xD7)) {
          continue;
        }
        if (offset + 1 >= bytes.length) {
          break;
        }
        final segmentLength = (bytes[offset] << 8) | bytes[offset + 1];
        if (segmentLength < 2 || offset + segmentLength > bytes.length) {
          break;
        }
        if (_isJpegStartOfFrame(marker) && segmentLength >= 7) {
          final height = (bytes[offset + 3] << 8) | bytes[offset + 4];
          final width = (bytes[offset + 5] << 8) | bytes[offset + 6];
          if (width > 0 && height > 0) {
            return RasterImageInfo(width: width, height: height);
          }
        }
        offset += segmentLength;
      }
    }

    return null;
  }

  static bool isHighResolution(Uint8List bytes, {int minimumSide = 512}) {
    final info = imageInfo(bytes);
    // Unknown image containers are left usable instead of being rejected.
    return info == null || info.shortestSide >= minimumSide;
  }

  static bool isBetter(Uint8List candidate, Uint8List fallback) {
    final candidateInfo = imageInfo(candidate);
    final fallbackInfo = imageInfo(fallback);
    if (candidateInfo == null) {
      return fallbackInfo == null && candidate.length > fallback.length;
    }
    if (fallbackInfo == null) {
      return true;
    }
    if (candidateInfo.pixelCount != fallbackInfo.pixelCount) {
      return candidateInfo.pixelCount > fallbackInfo.pixelCount;
    }
    return candidate.length > fallback.length;
  }

  static int? _flacSampleRate(Uint8List bytes) {
    if (bytes.length < 42 || !_matchesAscii(bytes, 0, 'fLaC')) {
      return null;
    }
    var offset = 4;
    while (offset + 4 <= bytes.length) {
      final header = bytes[offset];
      final isLast = (header & 0x80) != 0;
      final blockType = header & 0x7F;
      final blockLength = (bytes[offset + 1] << 16) |
          (bytes[offset + 2] << 8) |
          bytes[offset + 3];
      offset += 4;
      if (blockLength < 0 || offset + blockLength > bytes.length) {
        return null;
      }
      if (blockType == 0 && blockLength >= 18) {
        final sampleRate = (bytes[offset + 10] << 12) |
            (bytes[offset + 11] << 4) |
            ((bytes[offset + 12] & 0xF0) >> 4);
        return sampleRate > 0 ? sampleRate : null;
      }
      offset += blockLength;
      if (isLast) {
        break;
      }
    }
    return null;
  }

  static int? _mp3SampleRate(Uint8List bytes) {
    var offset = 0;
    if (bytes.length >= 10 && _matchesAscii(bytes, 0, 'ID3')) {
      final tagSize = _readSyncSafe(bytes, 6);
      if (tagSize >= 0) {
        offset = math.min(bytes.length, 10 + tagSize);
      }
    }
    for (var index = offset; index + 3 < bytes.length; index++) {
      if (bytes[index] != 0xFF || (bytes[index + 1] & 0xE0) != 0xE0) {
        continue;
      }
      final versionBits = (bytes[index + 1] >> 3) & 0x03;
      final layerBits = (bytes[index + 1] >> 1) & 0x03;
      final sampleRateIndex = (bytes[index + 2] >> 2) & 0x03;
      if (versionBits == 1 || layerBits == 0 || sampleRateIndex == 3) {
        continue;
      }
      const rates = <int>[44100, 48000, 32000];
      var rate = rates[sampleRateIndex];
      if (versionBits == 2) {
        rate ~/= 2;
      } else if (versionBits == 0) {
        rate ~/= 4;
      }
      return rate;
    }
    return null;
  }

  static Uint8List? _extractFlacPicture(Uint8List bytes) {
    if (bytes.length < 8 || !_matchesAscii(bytes, 0, 'fLaC')) {
      return null;
    }
    var offset = 4;
    Uint8List? best;
    while (offset + 4 <= bytes.length) {
      final header = bytes[offset];
      final isLast = (header & 0x80) != 0;
      final blockType = header & 0x7F;
      final blockLength = (bytes[offset + 1] << 16) |
          (bytes[offset + 2] << 8) |
          bytes[offset + 3];
      offset += 4;
      if (blockLength < 0 || offset + blockLength > bytes.length) {
        break;
      }
      if (blockType == 6) {
        final picture = _parseFlacPictureBlock(bytes, offset, blockLength);
        if (picture != null && (best == null || isBetter(picture, best))) {
          best = picture;
        }
      }
      offset += blockLength;
      if (isLast) {
        break;
      }
    }
    return best;
  }

  static Uint8List? _parseFlacPictureBlock(
    Uint8List bytes,
    int offset,
    int blockLength,
  ) {
    final end = offset + blockLength;
    var cursor = offset;

    bool has(int count) => count >= 0 && cursor + count <= end;
    int read32() {
      if (!has(4)) {
        return -1;
      }
      final value = _readUint32(bytes, cursor);
      cursor += 4;
      return value;
    }

    if (read32() < 0) {
      return null;
    }
    final mimeLength = read32();
    if (mimeLength < 0 || !has(mimeLength)) {
      return null;
    }
    cursor += mimeLength;
    final descriptionLength = read32();
    if (descriptionLength < 0 || !has(descriptionLength)) {
      return null;
    }
    cursor += descriptionLength;

    // Width, height, color depth, indexed color count.
    for (var index = 0; index < 4; index++) {
      if (read32() < 0) {
        return null;
      }
    }
    final dataLength = read32();
    if (dataLength <= 0 || !has(dataLength)) {
      return null;
    }
    return Uint8List.fromList(bytes.sublist(cursor, cursor + dataLength));
  }

  static Uint8List? _extractId3Apic(Uint8List bytes) {
    if (bytes.length < 10 || !_matchesAscii(bytes, 0, 'ID3')) {
      return null;
    }
    final majorVersion = bytes[3];
    if (majorVersion < 2 || majorVersion > 4) {
      return null;
    }
    final tagSize = _readSyncSafe(bytes, 6);
    final tagEnd = math.min(bytes.length, 10 + tagSize);
    var offset = 10;
    Uint8List? best;

    while (offset + 10 <= tagEnd) {
      final frameId = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      if (frameId.codeUnits.every((value) => value == 0)) {
        break;
      }
      final frameSize = majorVersion == 4
          ? _readSyncSafe(bytes, offset + 4)
          : _readUint32(bytes, offset + 4);
      if (frameSize <= 0 || offset + 10 + frameSize > tagEnd) {
        break;
      }
      if (frameId == 'APIC') {
        final picture = _parseApic(bytes, offset + 10, frameSize);
        if (picture != null && (best == null || isBetter(picture, best))) {
          best = picture;
        }
      }
      offset += 10 + frameSize;
    }
    return best;
  }

  static Uint8List? _parseApic(Uint8List bytes, int offset, int length) {
    final end = offset + length;
    if (offset >= end) {
      return null;
    }
    final encoding = bytes[offset];
    var cursor = offset + 1;
    final mimeEnd = _findByte(bytes, cursor, end, 0);
    if (mimeEnd < 0 || mimeEnd + 1 >= end) {
      return null;
    }
    cursor = mimeEnd + 1;
    // Picture type.
    cursor += 1;
    if (cursor >= end) {
      return null;
    }

    if (encoding == 1 || encoding == 2) {
      var descriptionEnd = -1;
      for (var index = cursor; index + 1 < end; index += 2) {
        if (bytes[index] == 0 && bytes[index + 1] == 0) {
          descriptionEnd = index;
          break;
        }
      }
      if (descriptionEnd < 0) {
        return null;
      }
      cursor = descriptionEnd + 2;
    } else {
      final descriptionEnd = _findByte(bytes, cursor, end, 0);
      if (descriptionEnd < 0) {
        return null;
      }
      cursor = descriptionEnd + 1;
    }
    if (cursor >= end) {
      return null;
    }
    return Uint8List.fromList(bytes.sublist(cursor, end));
  }

  static Uint8List? _extractMp4Cover(Uint8List bytes) {
    final covr = _findAscii(bytes, 'covr');
    if (covr < 4) {
      return null;
    }
    final covrSize = _readUint32(bytes, covr - 4);
    if (covrSize < 8) {
      return null;
    }
    final covrEnd = math.min(bytes.length, covr - 4 + covrSize);
    var cursor = covr + 4;
    Uint8List? best;
    while (cursor + 16 <= covrEnd) {
      final atomSize = _readUint32(bytes, cursor);
      if (atomSize < 16 || cursor + atomSize > covrEnd) {
        break;
      }
      if (_matchesAscii(bytes, cursor + 4, 'data')) {
        final payloadStart = cursor + 16;
        if (payloadStart < cursor + atomSize) {
          final picture = Uint8List.fromList(
            bytes.sublist(payloadStart, cursor + atomSize),
          );
          if (imageInfo(picture) != null &&
              (best == null || isBetter(picture, best))) {
            best = picture;
          }
        }
      }
      cursor += atomSize;
    }
    return best;
  }

  static Uint8List? _extractLargestRaster(Uint8List bytes) {
    Uint8List? best;

    for (var index = 0; index + 8 < bytes.length; index++) {
      Uint8List? image;
      if (bytes[index] == 0xFF &&
          bytes[index + 1] == 0xD8 &&
          bytes[index + 2] == 0xFF) {
        final end = _findJpegEnd(bytes, index + 3);
        if (end > index) {
          image = Uint8List.fromList(bytes.sublist(index, end));
          index = end - 1;
        }
      } else if (bytes[index] == 0x89 &&
          index + 8 <= bytes.length &&
          _matchesBytes(
            bytes,
            index,
            const <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
          )) {
        final end = _findPngEnd(bytes, index + 8);
        if (end > index) {
          image = Uint8List.fromList(bytes.sublist(index, end));
          index = end - 1;
        }
      }
      if (image != null && imageInfo(image) != null) {
        if (best == null || isBetter(image, best)) {
          best = image;
        }
      }
    }
    return best;
  }

  static int _findJpegEnd(Uint8List bytes, int start) {
    for (var index = start; index + 1 < bytes.length; index++) {
      if (bytes[index] == 0xFF && bytes[index + 1] == 0xD9) {
        return index + 2;
      }
    }
    return -1;
  }

  static int _findPngEnd(Uint8List bytes, int start) {
    var cursor = start;
    while (cursor + 12 <= bytes.length) {
      final length = _readUint32(bytes, cursor);
      if (length < 0 || cursor + 12 + length > bytes.length) {
        return -1;
      }
      final isEnd = _matchesAscii(bytes, cursor + 4, 'IEND');
      cursor += 12 + length;
      if (isEnd) {
        return cursor;
      }
    }
    return -1;
  }

  static bool _isJpegStartOfFrame(int marker) {
    return marker == 0xC0 ||
        marker == 0xC1 ||
        marker == 0xC2 ||
        marker == 0xC3 ||
        marker == 0xC5 ||
        marker == 0xC6 ||
        marker == 0xC7 ||
        marker == 0xC9 ||
        marker == 0xCA ||
        marker == 0xCB ||
        marker == 0xCD ||
        marker == 0xCE ||
        marker == 0xCF;
  }

  static int _readUint32(Uint8List bytes, int offset) {
    if (offset < 0 || offset + 4 > bytes.length) {
      return -1;
    }
    return (bytes[offset] << 24) |
        (bytes[offset + 1] << 16) |
        (bytes[offset + 2] << 8) |
        bytes[offset + 3];
  }

  static int _readSyncSafe(Uint8List bytes, int offset) {
    if (offset < 0 || offset + 4 > bytes.length) {
      return -1;
    }
    return ((bytes[offset] & 0x7F) << 21) |
        ((bytes[offset + 1] & 0x7F) << 14) |
        ((bytes[offset + 2] & 0x7F) << 7) |
        (bytes[offset + 3] & 0x7F);
  }

  static int _readUint24LittleEndian(Uint8List bytes, int offset) {
    return bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16);
  }

  static bool _matchesAscii(Uint8List bytes, int offset, String value) {
    if (offset < 0 || offset + value.length > bytes.length) {
      return false;
    }
    for (var index = 0; index < value.length; index++) {
      if (bytes[offset + index] != value.codeUnitAt(index)) {
        return false;
      }
    }
    return true;
  }

  static bool _matchesBytes(Uint8List bytes, int offset, List<int> value) {
    if (offset < 0 || offset + value.length > bytes.length) {
      return false;
    }
    for (var index = 0; index < value.length; index++) {
      if (bytes[offset + index] != value[index]) {
        return false;
      }
    }
    return true;
  }

  static int _findByte(Uint8List bytes, int start, int end, int value) {
    for (var index = start; index < end; index++) {
      if (bytes[index] == value) {
        return index;
      }
    }
    return -1;
  }

  static int _findAscii(Uint8List bytes, String value) {
    for (var index = 0; index + value.length <= bytes.length; index++) {
      if (_matchesAscii(bytes, index, value)) {
        return index;
      }
    }
    return -1;
  }
}
