import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/design_system/components/tentura_avatar.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/widget/self_aware_profile_avatar.dart';

/// [SelfAwareAvatar] with a live online indicator from [PresenceCubit].
class PresenceAvatar extends StatelessWidget {
  const PresenceAvatar({
    required this.profile,
    required this.userId,
    super.key,
    this.sizeBucket = TenturaAvatarSize.medium,
    this.size,
    this.showAuthorStar = false,
    this.withRating = false,
    bool? withContactBadge,
    this.overlayBadge,
    this.boxFit = BoxFit.cover,
  }) : withContactBadge = withContactBadge ?? withRating;

  const PresenceAvatar.small({
    required this.profile,
    required this.userId,
    super.key,
    this.size,
    this.showAuthorStar = false,
    this.withRating = false,
    bool? withContactBadge,
    this.overlayBadge,
    this.boxFit = BoxFit.cover,
  }) : sizeBucket = TenturaAvatarSize.small,
       withContactBadge = withContactBadge ?? withRating;

  const PresenceAvatar.medium({
    required this.profile,
    required this.userId,
    super.key,
    this.size,
    this.showAuthorStar = false,
    this.withRating = false,
    bool? withContactBadge,
    this.overlayBadge,
    this.boxFit = BoxFit.cover,
  }) : sizeBucket = TenturaAvatarSize.medium,
       withContactBadge = withContactBadge ?? withRating;

  final Profile profile;
  final String userId;
  final TenturaAvatarSize sizeBucket;
  final double? size;
  final bool showAuthorStar;
  final bool withRating;
  final bool withContactBadge;
  final Widget? overlayBadge;
  final BoxFit boxFit;

  @override
  Widget build(BuildContext context) {
    final isOnline = context.select<PresenceCubit, bool>(
      (cubit) => cubit.state[userId] == UserPresenceStatus.online,
    );
    return SelfAwareAvatar(
      profile: profile,
      sizeBucket: sizeBucket,
      size: size,
      showAuthorStar: showAuthorStar,
      withRating: withRating,
      withContactBadge: withContactBadge,
      overlayBadge: overlayBadge,
      boxFit: boxFit,
      isOnline: isOnline,
    );
  }
}
