import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:tentura/consts.dart';

class AvatarImage extends StatelessWidget {
  static String getAvatarUrl(String userId) =>
      '${kIsWeb ? '' : 'https://$kAppLinkBase'}'
      '/images/$userId/avatar.jpg';

  const AvatarImage({
    required this.size,
    required this.userId,
    this.boxFit = BoxFit.cover,
    super.key,
  });

  final String userId;
  final BoxFit boxFit;
  final double size;

  @override
  Widget build(BuildContext context) {
    final placeholder = Image.asset(
      'assets/images/avatar-placeholder.jpg',
      height: size,
      width: size,
      fit: boxFit,
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(size / 2),
      child: userId.isEmpty
          ? placeholder
          : CachedNetworkImage(
              height: size,
              width: size,
              fit: boxFit,
              filterQuality: FilterQuality.high,
              placeholder: (context, url) => placeholder,
              errorWidget: (context, url, error) => placeholder,
              imageUrl: getAvatarUrl(userId),
            ),
    );
  }
}
