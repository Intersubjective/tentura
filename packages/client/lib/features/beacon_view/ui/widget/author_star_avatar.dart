import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/widget/avatar_rated.dart';

/// Avatar with author star badge (matches HUD people strip).
class AuthorStarAvatar extends StatelessWidget {
  const AuthorStarAvatar({
    required this.profile,
    this.size = AvatarRated.sizeSmall,
    super.key,
  });

  final Profile profile;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        TenturaAvatar(profile: profile, size: size),
        Positioned(
          right: -2,
          bottom: -2,
          child: Icon(
            Icons.star_rounded,
            size: 14,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ],
    );
  }
}
