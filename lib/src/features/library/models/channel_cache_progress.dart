enum ChannelCachePhase { scanning, thumbnails, complete }

class ChannelCacheProgress {
  const ChannelCacheProgress({
    required this.phase,
    required this.mediaCount,
    this.scannedMessages = 0,
    this.completedThumbnails = 0,
    this.totalThumbnails = 0,
    this.failedThumbnails = 0,
  });

  final ChannelCachePhase phase;
  final int scannedMessages;
  final int mediaCount;
  final int completedThumbnails;
  final int totalThumbnails;
  final int failedThumbnails;

  int get processedThumbnails => completedThumbnails + failedThumbnails;

  double? get fraction {
    if (phase != ChannelCachePhase.thumbnails || totalThumbnails == 0) {
      return null;
    }
    return processedThumbnails / totalThumbnails;
  }

  String get label => switch (phase) {
        ChannelCachePhase.scanning =>
          'Scanning $scannedMessages messages · $mediaCount songs found',
        ChannelCachePhase.thumbnails => failedThumbnails == 0
            ? 'Saving album artwork · $processedThumbnails of $totalThumbnails'
            : 'Saving album artwork · $processedThumbnails of '
                '$totalThumbnails · $failedThumbnails unavailable',
        ChannelCachePhase.complete => failedThumbnails == 0
            ? '$mediaCount songs cached'
            : '$mediaCount songs cached · $failedThumbnails covers unavailable',
      };
}
