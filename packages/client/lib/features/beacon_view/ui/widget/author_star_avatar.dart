import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/widget/avatar_rated.dart';
import 'package:tentura/ui/widget/overlapping_people_avatars.dart';

/// Avatar with author star badge (matches overlapping people stacks).
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
        ProfileAuthorStarBadge(avatarSize: size),
      ],
    );
  }
}
