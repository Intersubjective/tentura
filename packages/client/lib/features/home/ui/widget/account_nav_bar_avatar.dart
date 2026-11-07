import 'package:flutter/material.dart';

import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/widget/self_aware_profile_avatar.dart';

/// Compact account glyph for Home chrome (top bar, rail indicator slot).
///
/// Visual-only: no gestures or nested [Semantics] — the parent [MenuAnchor] /
/// [IconButton] / [InkWell] owns hit testing and accessibility.
class AccountNavBarAvatar extends StatelessWidget {
  const AccountNavBarAvatar({super.key, this.selected = false});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    if (!GetIt.I.isRegistered<ProfileCubit>()) {
      return Icon(selected ? Icons.person : Icons.person_outline);
    }
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: BlocBuilder<ProfileCubit, ProfileState>(
        bloc: GetIt.I<ProfileCubit>(),
        buildWhen: (p, c) =>
            p.profile.hasAvatar != c.profile.hasAvatar ||
            p.profile.image?.blurHash != c.profile.image?.blurHash ||
            p.profile.displayName != c.profile.displayName,
        builder: (context, state) {
          final avatar = SelfAwareAvatar.medium(
            profile: state.profile,
            size: IconTheme.of(context).size ?? 24,
          );
          if (!selected) {
            return avatar;
          }
          return DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Theme.of(context).colorScheme.primary,
                width: 2,
              ),
            ),
            child: avatar,
          );
        },
      ),
    );
  }
}
