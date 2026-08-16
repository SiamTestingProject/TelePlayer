import '../../../core/utils/file_name_utils.dart';

enum MediaKind { video, audio, document, splitVideo }

enum MediaSortOrder { newest, alphabetical }

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
    this.dateEpochSeconds = 0,
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
  final int dateEpochSeconds;
  final String? artist;
  final int? durationSeconds;
  final int? thumbnailFileId;
  final String? localPath;
  final List<MediaPart> parts;

  String get readableSize => FileNameUtils.readableBytes(size);
  bool get isSplit => parts.isNotEmpty || kind == MediaKind.splitVideo;

  factory MediaItem.fromJson(Map<String, dynamic> json) {
    final rawParts = json['parts'] as List<dynamic>? ?? const <dynamic>[];
    return MediaItem(
      id: json['id']?.toString() ?? '',
      chatId: int.tryParse(json['chatId']?.toString() ?? '') ?? 0,
      messageId: int.tryParse(json['messageId']?.toString() ?? '') ?? 0,
      fileId: int.tryParse(json['fileId']?.toString() ?? '') ?? 0,
      title: json['title']?.toString() ?? '',
      fileName: json['fileName']?.toString() ?? '',
      mimeType: json['mimeType']?.toString() ?? 'application/octet-stream',
      size: int.tryParse(json['size']?.toString() ?? '') ?? 0,
      kind: MediaKind.values.firstWhere(
        (kind) => kind.name == json['kind']?.toString(),
        orElse: () => MediaKind.document,
      ),
      dateEpochSeconds:
          int.tryParse(json['dateEpochSeconds']?.toString() ?? '') ?? 0,
      artist: json['artist']?.toString(),
      durationSeconds:
          int.tryParse(json['durationSeconds']?.toString() ?? ''),
      thumbnailFileId:
          int.tryParse(json['thumbnailFileId']?.toString() ?? ''),
      localPath: json['localPath']?.toString(),
      parts: rawParts
          .whereType<Map>()
          .map((part) => MediaPart.fromJson(Map<String, dynamic>.from(part)))
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'chatId': chatId,
        'messageId': messageId,
        'fileId': fileId,
        'title': title,
        'fileName': fileName,
        'mimeType': mimeType,
        'size': size,
        'kind': kind.name,
        'dateEpochSeconds': dateEpochSeconds,
        if (artist != null) 'artist': artist,
        if (durationSeconds != null) 'durationSeconds': durationSeconds,
        if (thumbnailFileId != null) 'thumbnailFileId': thumbnailFileId,
        if (localPath != null && localPath!.isNotEmpty) 'localPath': localPath,
        'parts': parts.map((part) => part.toJson()).toList(growable: false),
      };

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
      dateEpochSeconds: dateEpochSeconds,
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

  factory MediaPart.fromJson(Map<String, dynamic> json) {
    return MediaPart(
      chatId: int.tryParse(json['chatId']?.toString() ?? '') ?? 0,
      messageId: int.tryParse(json['messageId']?.toString() ?? '') ?? 0,
      fileId: int.tryParse(json['fileId']?.toString() ?? '') ?? 0,
      partNumber: int.tryParse(json['partNumber']?.toString() ?? '') ?? 0,
      size: int.tryParse(json['size']?.toString() ?? '') ?? 0,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'chatId': chatId,
        'messageId': messageId,
        'fileId': fileId,
        'partNumber': partNumber,
        'size': size,
      };
}

int compareMediaItems(
  MediaItem left,
  MediaItem right,
  MediaSortOrder order,
) {
  if (order == MediaSortOrder.alphabetical) {
    final titleComparison = left.title.trim().toLowerCase().compareTo(
          right.title.trim().toLowerCase(),
        );
    if (titleComparison != 0) {
      return titleComparison;
    }
    final artistComparison = (left.artist ?? '').trim().toLowerCase().compareTo(
          (right.artist ?? '').trim().toLowerCase(),
        );
    if (artistComparison != 0) {
      return artistComparison;
    }
  }

  final dateComparison =
      right.dateEpochSeconds.compareTo(left.dateEpochSeconds);
  if (dateComparison != 0) {
    return dateComparison;
  }
  final messageComparison = right.messageId.compareTo(left.messageId);
  if (messageComparison != 0) {
    return messageComparison;
  }
  return right.id.compareTo(left.id);
}
