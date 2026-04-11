import 'package:flutter/material.dart';
import 'package:blurhash_shader/blurhash_shader.dart';

import 'package:tentura/domain/entity/beacon.dart';

import 'beacon_gallery_viewer.dart';

class BeaconImage extends StatelessWidget {
  const BeaconImage({
    required this.beacon,
    this.boxFit = BoxFit.cover,
    this.enableGalleryTap = false,
    super.key,
  });

  final Beacon beacon;
  final BoxFit boxFit;
  final bool enableGalleryTap;

  @override
  Widget build(BuildContext context) {
    if (beacon.hasNoPicture) return _placeholder;

    final image = beacon.images.first;
    final imageWidget = image.blurHash.isEmpty
        ? _imageNetwork
        : AspectRatio(
            aspectRatio: image.height > 0
                ? image.width / image.height
                : 1,
            child: BlurHash(image.blurHash, child: _imageNetwork),
          );

    if (!enableGalleryTap) return imageWidget;

    return GestureDetector(
      onTap: () => BeaconGalleryViewer.show(
        context,
        beacon: beacon,
      ),
      child: imageWidget,
    );
  }

  Widget get _imageNetwork => Image.network(
    beacon.imageUrl,
    fit: boxFit,
    errorBuilder: (_, _, _) => _placeholder,
  );

  // TBD: remove assets
  Widget get _placeholder => Image.asset(
    'images/placeholder/beacon.jpg',
    fit: boxFit,
  );
}
