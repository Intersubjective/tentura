import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/avatar_rated.dart';
import 'package:tentura/ui/widget/show_more_text.dart';
import 'package:tentura/ui/widget/tentura_icons.dart';

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
    final screenCubit = context.read<ScreenCubit>();
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Avatar
          Center(
            child: AvatarRated.big(
              profile: profile,
              withRating: false,
            ),
          ),

          // Description
          Padding(
            padding: kPaddingT,
            child: ShowMoreText(
              profile.description,
              style: textTheme.bodyMedium,
              colorClickableText: theme.colorScheme.primary,
            ),
          ),

          // Show Connections
          Padding(
            padding: kPaddingSmallT,
            child: OutlinedButton.icon(
              onPressed: () => screenCubit.showGraphFor(profile.id),
              icon: const Icon(TenturaIcons.graph),
              label: Text(l10n.showConnections),
            ),
          ),

          // Show Beacons
          Padding(
            padding: kPaddingSmallT,
            child: OutlinedButton.icon(
              onPressed: () => screenCubit.showBeaconsOf(profile.id),
              icon: const Icon(Icons.open_in_full),
              label: Text(l10n.showBeacons),
            ),
          ),

          Padding(
            padding: kPaddingSmallT,
            child: Row(
              spacing: kSpacingSmall,
              children: [
                // Settings
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.settings),
                    label: Text(l10n.labelSettings),
                    onPressed: screenCubit.showSettings,
                  ),
                ),

                // New Beacon
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.post_add),
                    label: Text(l10n.newBeacon),
                    onPressed: screenCubit.showBeaconCreate,
                  ),
                ),
              ],
            ),
          ),

          // Opinions
          Padding(
            padding: kPaddingT,
            child: Text(
              l10n.communityFeedback,
              style: textTheme.headlineMedium,
            ),
          ),
        ],
      ),
    );
  }
}
