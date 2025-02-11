import 'package:flutter/material.dart';
import 'package:flutter_blurhash/flutter_blurhash.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/profile.dart';

class AvatarImage extends StatelessWidget {
  const AvatarImage({
    required this.size,
    required this.profile,
    this.boxFit = BoxFit.cover,
    super.key,
  });

  const AvatarImage.small({
    required this.profile,
    super.key,
  })  : boxFit = BoxFit.cover,
        size = 40;

  final Profile profile;
  final BoxFit boxFit;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cachedSize = size.ceil();
    return SizedBox.square(
      dimension: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size / 2),
        child: profile.hasAvatar
            ? BlurHash(
                decodingHeight: cachedSize,
                decodingWidth: cachedSize,
                image: profile.avatarUrl,
                hash: profile.blurhash,
                imageFit: boxFit,
              )
            : Image.asset(
                'images/placeholder/avatar.jpg',
                // ignore: avoid_redundant_argument_values // set from env
                package: kAssetPackage,
                cacheHeight: cachedSize,
                cacheWidth: cachedSize,
                fit: boxFit,
              ),
      ),
    );
  }
}
