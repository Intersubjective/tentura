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
    final ordered = beacon.displayImages;
    if (ordered.isEmpty) return _placeholder;

    final image = ordered.first;
    final network = _imageNetwork(beacon.urlForImage(image));
    final imageWidget = image.blurHash.isEmpty
        ? network
        : AspectRatio(
            aspectRatio: image.height > 0
                ? image.width / image.height
                : 1,
            child: BlurHash(image.blurHash, child: network),
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

  Widget _imageNetwork(String url) => Image.network(
    url,
    fit: boxFit,
    errorBuilder: (_, _, _) => _placeholder,
  );

  // TBD: remove assets
  Widget get _placeholder => Image.asset(
    'images/placeholder/beacon.jpg',
    fit: boxFit,
  );
}
