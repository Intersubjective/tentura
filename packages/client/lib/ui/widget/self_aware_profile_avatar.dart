import 'package:flutter/material.dart';

import 'package:tentura/design_system/components/tentura_avatar.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/widget/self_user_highlight.dart';

/// [TenturaAvatar] with self halo when [profile] is the signed-in user.
///
/// Sole owner of [ProfileCubit] coupling for avatar identity; call sites pass
/// [profile] and decoration flags only.
class SelfAwareAvatar extends StatelessWidget {
  const SelfAwareAvatar({
    required this.profile,
    super.key,
    this.sizeBucket = TenturaAvatarSize.medium,
    this.size,
    this.showAuthorStar = false,
    this.withRating = false,
    bool? withContactBadge,
    this.overlayBadge,
    this.isOnline = false,
    this.boxFit = BoxFit.cover,
  }) : withContactBadge = withContactBadge ?? withRating;

  const SelfAwareAvatar.big({
    required this.profile,
    super.key,
    this.showAuthorStar = false,
    this.withRating = false,
    bool? withContactBadge,
    this.overlayBadge,
    this.isOnline = false,
    this.boxFit = BoxFit.cover,
  }) : sizeBucket = TenturaAvatarSize.big,
       size = kTenturaAvatarBigSize,
       withContactBadge = withContactBadge ?? withRating;

  const SelfAwareAvatar.medium({
    required this.profile,
    super.key,
    this.size,
    this.showAuthorStar = false,
    this.withRating = false,
    bool? withContactBadge,
    this.overlayBadge,
    this.isOnline = false,
    this.boxFit = BoxFit.cover,
  }) : sizeBucket = TenturaAvatarSize.medium,
       withContactBadge = withContactBadge ?? withRating;

  const SelfAwareAvatar.small({
    required this.profile,
    super.key,
    this.size,
    this.showAuthorStar = false,
    this.withRating = false,
    bool? withContactBadge,
    this.overlayBadge,
    this.isOnline = false,
    this.boxFit = BoxFit.cover,
  }) : sizeBucket = TenturaAvatarSize.small,
       withContactBadge = withContactBadge ?? withRating;

  const SelfAwareAvatar.tiny({
    required this.profile,
    super.key,
    this.size,
    this.showAuthorStar = false,
    this.withRating = false,
    bool? withContactBadge,
    this.overlayBadge,
    this.isOnline = false,
    this.boxFit = BoxFit.cover,
  }) : sizeBucket = TenturaAvatarSize.tiny,
       withContactBadge = withContactBadge ?? withRating;

  final Profile profile;
  final TenturaAvatarSize sizeBucket;
  final double? size;
  final bool showAuthorStar;
  final bool withRating;
  final bool withContactBadge;
  final Widget? overlayBadge;
  final bool isOnline;
  final BoxFit boxFit;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProfileCubit, ProfileState>(
      buildWhen: (p, c) => p.profile.id != c.profile.id,
      builder: (context, state) {
        final isSelf = SelfUserHighlight.profileIsSelf(
          profile,
          state.profile.id,
        );
        return TenturaAvatar(
          profile: profile,
          sizeBucket: sizeBucket,
          size: size,
          showAuthorStar: showAuthorStar,
          isSelf: isSelf,
          withRating: withRating,
          withContactBadge: withContactBadge,
          overlayBadge: overlayBadge,
          isOnline: isOnline,
          boxFit: boxFit,
        );
      },
    );
  }
}
