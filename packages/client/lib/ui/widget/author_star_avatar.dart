import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/widget/overlapping_people_avatars.dart';

/// Avatar with optional author star badge (matches overlapping people stacks).
class AuthorStarAvatar extends StatelessWidget {
  const AuthorStarAvatar({
    required this.profile,
    this.size = 18,
    this.showAuthorStar = true,
    super.key,
  });

  final Profile profile;
  final double size;
  final bool showAuthorStar;

  @override
  Widget build(BuildContext context) {
    final avatar = TenturaAvatar(profile: profile, size: size);
    if (!showAuthorStar) {
      return avatar;
    }
    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        ProfileAuthorStarBadge(avatarSize: size),
      ],
    );
  }
}
