import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/widget/avatar_rated.dart';
import 'package:tentura/ui/widget/self_user_highlight.dart';

/// [AvatarRated] with a primary ring when [profile] is the signed-in user.
class SelfAwareAvatar extends StatelessWidget {
  const SelfAwareAvatar({
    required this.profile,
    this.size = AvatarRated.sizeSmall,
    this.withRating = true,
    super.key,
  });

  factory SelfAwareAvatar.small({
    required Profile profile,
    bool withRating = true,
  }) {
    if (withRating) {
      return SelfAwareAvatar(profile: profile);
    }
    return SelfAwareAvatar(
      profile: profile,
      withRating: false,
    );
  }

  final Profile profile;
  final double size;
  final bool withRating;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProfileCubit, ProfileState>(
      buildWhen: (p, c) => p.profile.id != c.profile.id,
      builder: (context, state) {
        final isSelf = SelfUserHighlight.profileIsSelf(profile, state.profile.id);
        final core = AvatarRated(
          profile: profile,
          size: size,
          withRating: withRating,
        );
        return SelfUserHighlight.wrapSmallAvatar(
          context,
          avatarSize: size,
          isSelf: isSelf,
          child: core,
        );
      },
    );
  }
}
