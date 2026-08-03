import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../bloc/profile_view_cubit.dart';

/// Stripped profile shown when the viewer opens someone they have directly blocked.
class BlockedProfileViewBody extends StatelessWidget {
  const BlockedProfileViewBody({
    required this.profile,
    super.key,
  });

  final Profile profile;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final tt = context.tt;

    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: TenturaAvatar.big(
              profile: profile,
              withContactBadge: false,
            ),
          ),
          Padding(
            padding: EdgeInsets.only(top: tt.rowGap),
            child: Center(
              child: Text(
                profile.shownName,
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(top: tt.sectionGap),
            child: FilledButton(
              onPressed: () =>
                  context.read<ProfileViewCubit>().unblockBlockedProfile(),
              child: Text(l10n.unblockUserMenuItem),
            ),
          ),
        ],
      ),
    );
  }
}
