import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/beacon.dart';

import 'tentura_fullscreen_image_viewer.dart';

/// Full-screen gallery of a [Beacon]'s images, in [Beacon.displayImages]
/// order.
class BeaconGalleryViewer extends StatelessWidget {
  const BeaconGalleryViewer({
    required this.beacon,
    this.initialIndex = 0,
    super.key,
  });

  final Beacon beacon;
  final int initialIndex;

  static Future<void> show(
    BuildContext context, {
    required Beacon beacon,
    int initialIndex = 0,
  }) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => BeaconGalleryViewer(
            beacon: beacon,
            initialIndex: initialIndex,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => TenturaFullscreenImageViewer(
    initialIndex: initialIndex,
    images: [
      for (final image in beacon.displayImages)
        TenturaGalleryImage(
          url: beacon.urlForImage(image),
          blurHash: image.blurHash,
        ),
    ],
  );
}
