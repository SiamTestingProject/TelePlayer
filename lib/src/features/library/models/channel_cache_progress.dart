enum ChannelCachePhase { scanning, thumbnails, complete }

class ChannelCacheProgress {
  const ChannelCacheProgress({
    required this.phase,
    required this.mediaCount,
    this.scannedMessages = 0,
    this.completedThumbnails = 0,
    this.totalThumbnails = 0,
  });

  final ChannelCachePhase phase;
  final int scannedMessages;
  final int mediaCount;
  final int completedThumbnails;
  final int totalThumbnails;

  double? get fraction {
    if (phase != ChannelCachePhase.thumbnails || totalThumbnails == 0) {
      return null;
    }
    return completedThumbnails / totalThumbnails;
  }

  String get label => switch (phase) {
        ChannelCachePhase.scanning =>
          'Scanning $scannedMessages messages · $mediaCount media files found',
        ChannelCachePhase.thumbnails =>
          'Saving best thumbnails · $completedThumbnails of $totalThumbnails',
        ChannelCachePhase.complete => '$mediaCount media files cached',
      };
}
