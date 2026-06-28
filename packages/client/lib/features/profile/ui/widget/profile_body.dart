import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/self_aware_profile_avatar.dart';
import 'package:tentura/ui/widget/show_more_text.dart';

class ProfileBody extends StatelessWidget {
  const ProfileBody({
    required this.profile,
    super.key,
  });

  final Profile profile;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final tt = context.tt;
    final screenCubit = context.read<ScreenCubit>();
    final sectionTop = EdgeInsets.only(top: tt.sectionGap);
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Avatar
          Center(
            child: SelfAwareAvatar.big(
              profile: profile,
            ),
          ),

          // Description
          Padding(
            padding: sectionTop,
            child: ShowMoreText(
              profile.description,
              style: textTheme.bodyMedium,
              colorClickableText: theme.colorScheme.primary,
            ),
          ),

          // Show Connections
          Padding(
            padding: sectionTop,
            child: OutlinedButton.icon(
              onPressed: () => screenCubit.showGraphFor(profile.id),
              icon: const Icon(TenturaIcons.graph),
              label: Text(l10n.showConnections),
            ),
          ),

          // Show Beacons
          Padding(
            padding: sectionTop,
            child: OutlinedButton.icon(
              onPressed: () => screenCubit.showBeaconsOf(profile.id),
              icon: const Icon(Icons.open_in_full),
              label: Text(l10n.showBeacons),
            ),
          ),

          Padding(
            padding: sectionTop,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.settings),
              label: Text(l10n.labelSettings),
              onPressed: screenCubit.showSettings,
            ),
          ),
        ],
      ),
    );
  }
}
