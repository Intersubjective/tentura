import 'package:flutter/material.dart';
import 'package:blurhash_shader/blurhash_shader.dart';

import 'package:tentura/domain/entity/beacon.dart';

class BeaconImage extends StatelessWidget {
  const BeaconImage({
    required this.beacon,
    this.boxFit = BoxFit.cover,
    super.key,
  });

  final Beacon beacon;

  final BoxFit boxFit;

  @override
  Widget build(BuildContext context) => beacon.hasNoPicture
      ? _placeholder
      : beacon.image?.blurHash.isEmpty ?? true
      ? _imageNetwork
      : AspectRatio(
          aspectRatio: beacon.image!.height > 0
              ? beacon.image!.width / beacon.image!.height
              : 1,
          child: BlurHash(beacon.image!.blurHash, child: _imageNetwork),
        );

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
