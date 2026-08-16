import '../../../core/utils/file_name_utils.dart';

enum MediaKind { video, audio, document, splitVideo }

class MediaItem {
  const MediaItem({
    required this.id,
    required this.chatId,
    required this.messageId,
    required this.fileId,
    required this.title,
    required this.fileName,
    required this.mimeType,
    required this.size,
    required this.kind,
    this.artist,
    this.durationSeconds,
    this.thumbnailFileId,
    this.localPath,
    this.parts = const <MediaPart>[],
  });

  final String id;
  final int chatId;
  final int messageId;
  final int fileId;
  final String title;
  final String fileName;
  final String mimeType;
  final int size;
  final MediaKind kind;
  final String? artist;
  final int? durationSeconds;
  final int? thumbnailFileId;
  final String? localPath;
  final List<MediaPart> parts;

  String get readableSize => FileNameUtils.readableBytes(size);
  bool get isSplit => parts.isNotEmpty || kind == MediaKind.splitVideo;

  MediaItem copyWith({
    int? size,
    String? localPath,
    List<MediaPart>? parts,
  }) {
    return MediaItem(
      id: id,
      chatId: chatId,
      messageId: messageId,
      fileId: fileId,
      title: title,
      fileName: fileName,
      mimeType: mimeType,
      size: size ?? this.size,
      kind: kind,
      artist: artist,
      durationSeconds: durationSeconds,
      thumbnailFileId: thumbnailFileId,
      localPath: localPath ?? this.localPath,
      parts: parts ?? this.parts,
    );
  }
}

class MediaPart {
  const MediaPart({
    required this.chatId,
    required this.messageId,
    required this.fileId,
    required this.partNumber,
    required this.size,
  });

  final int chatId;
  final int messageId;
  final int fileId;
  final int partNumber;
  final int size;
}
