import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/widget/avatar_rated.dart';
import 'package:tentura/ui/widget/self_user_highlight.dart';

import 'plain_mini_avatar.dart';

/// [PlainMiniAvatar] with a primary ring when [profile] is the signed-in user.
class SelfAwarePlainMiniAvatar extends StatelessWidget {
  const SelfAwarePlainMiniAvatar({
    required this.profile,
    this.size = AvatarRated.sizeSmall,
    this.overlay,
    super.key,
  });

  final Profile profile;
  final double size;
  final Widget? overlay;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProfileCubit, ProfileState>(
      buildWhen: (p, c) => p.profile.id != c.profile.id,
      builder: (context, state) {
        final isSelf = SelfUserHighlight.profileIsSelf(profile, state.profile.id);
        final core = PlainMiniAvatar(
          profile: profile,
          size: size,
          overlay: overlay,
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
