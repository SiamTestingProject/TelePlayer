import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../application/media_library_controller.dart';
import '../models/media_item.dart';

class MediaArtwork extends StatelessWidget {
  const MediaArtwork({
    required this.item,
    required this.libraryController,
    this.borderRadius = 22,
    this.iconSize = 36,
    super.key,
  });

  final MediaItem item;
  final MediaLibraryController libraryController;
  final double borderRadius;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: FutureBuilder<Uint8List?>(
        future: libraryController.thumbnailFor(item),
        builder: (context, snapshot) {
          final bytes = snapshot.data;
          if (bytes != null && bytes.isNotEmpty) {
            return Image.memory(
              bytes,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => _ArtworkFallback(
                iconSize: iconSize,
              ),
            );
          }
          return _ArtworkFallback(iconSize: iconSize);
        },
      ),
    );
  }
}

class _ArtworkFallback extends StatelessWidget {
  const _ArtworkFallback({required this.iconSize});

  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            colors.primaryContainer,
            colors.secondaryContainer,
            colors.tertiaryContainer,
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.music_note_rounded,
          size: iconSize,
          color: colors.onPrimaryContainer,
        ),
      ),
    );
  }
}
