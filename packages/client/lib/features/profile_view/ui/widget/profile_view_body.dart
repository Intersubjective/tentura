import 'dart:async';
import 'package:flutter/material.dart';

import 'package:tentura/domain/capability/person_capability_cues.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/profile_presence_line.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/avatar_rated.dart';
import 'package:tentura/ui/widget/show_more_text.dart';
import 'package:tentura/ui/widget/tentura_icons.dart';

import 'package:tentura/features/capability/ui/widget/capability_cue_strip.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';

import '../bloc/profile_view_cubit.dart';
import '../dialog/edit_capabilities_dialog.dart';
import 'mutual_friends_button.dart';

class ProfileViewBody extends StatelessWidget {
  const ProfileViewBody({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    return BlocSelector<ProfileViewCubit, ProfileViewState, Profile>(
      selector: (state) => state.profile,
      builder: (context, profile) => SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Avatar
            Center(
              child: AvatarRated.big(profile: profile),
            ),

            // Description
            Padding(
              padding: kPaddingT,
              child: ShowMoreText(
                profile.description,
                style: theme.textTheme.bodyMedium,
                colorClickableText: theme.colorScheme.primary,
              ),
            ),

            Builder(
              builder: (ctx) {
                final line = profilePresenceDisplayLine(
                  l10n: l10n,
                  locale: Localizations.localeOf(ctx),
                  status: profile.presenceStatus,
                  lastSeenAt: profile.presenceLastSeenAt,
                );
                if (line.isEmpty) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: kPaddingSmallT,
                  child: Text(
                    line,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                );
              },
            ),

            // Deduplicated capability strip + edit button (viewer ≠ subject, viewer is friend)
            BlocSelector<ProfileViewCubit, ProfileViewState,
                (List<CapabilityWithSource>, bool)>(
              selector: (s) => (s.cues.viewerVisible, s.profile.isFriend),
              builder: (context, rec) {
                final (viewerVisible, isFriend) = rec;
                final myId =
                    context.read<ProfileCubit>().state.profile.id;
                final isSelf = profile.id == myId;
                if (isSelf || !isFriend) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (viewerVisible.isNotEmpty)
                      Padding(
                        padding: kPaddingSmallT,
                        child: CapabilityCueStrip(
                          slugs: viewerVisible.map((c) => c.slug).toList(),
                        ),
                      ),
                    Padding(
                      padding: kPaddingSmallT,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          final cubit = context.read<ProfileViewCubit>();
                          unawaited(
                            EditCapabilitiesDialog.show(
                              context,
                              subjectId: profile.id,
                              currentVisible: viewerVisible,
                              onSaved: (slugs, automaticSlugs) =>
                                  cubit.updateViewerVisible(
                                    slugs
                                        .map(
                                          (s) => CapabilityWithSource(
                                            slug: s,
                                            hasManualLabel:
                                                !automaticSlugs.contains(s),
                                          ),
                                        )
                                        .toList(),
                                  ),
                            ).catchError((Object e) {
                              if (context.mounted) {
                                showSnackBar(
                                  context,
                                  text: e.toString(),
                                  isError: true,
                                );
                              }
                            }),
                          );
                        },
                        icon: const Icon(Icons.tune),
                        label: Text(l10n.capabilityEditCapabilities),
                      ),
                    ),
                  ],
                );
              },
            ),

            Padding(
              padding: kPaddingSmallT,
              child: OutlinedButton.icon(
                onPressed: () =>
                    context.read<ScreenCubit>().showGraphFor(profile.id),
                icon: const Icon(TenturaIcons.graph),
                label: Text(l10n.showConnections),
              ),
            ),

            // Show Beacons
            Padding(
              padding: kPaddingSmallT,
              child: OutlinedButton.icon(
                onPressed: () =>
                    context.read<ScreenCubit>().showBeaconsOf(profile.id),
                icon: const Icon(Icons.open_in_full),
                label: Text(l10n.showBeacons),
              ),
            ),

            Padding(
              padding: kPaddingSmallT,
              child: MutualFriendsButton(userId: profile.id),
            ),

            if (profile.isNotFriend)
              Padding(
                padding: kPaddingSmallT,
                child: FilledButton.icon(
                  onPressed: context.read<ProfileViewCubit>().addFriend,
                  icon: const Icon(Icons.people),
                  label: Text(l10n.addToMyField),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
