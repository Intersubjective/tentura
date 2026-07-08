import 'dart:async';
import 'package:flutter/material.dart';

import 'package:tentura/domain/capability/person_capability_cues.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/profile_presence_line.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/design_system/components/tentura_avatar.dart';
import 'package:tentura/ui/widget/show_more_text.dart';
import 'package:tentura/ui/widget/tentura_fullscreen_image_viewer.dart';
import 'package:tentura/ui/widget/tentura_icons.dart';
import 'package:tentura/design_system/tentura_design_system.dart';

import 'package:tentura/features/capability/ui/widget/capability_cue_strip.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';

import '../bloc/profile_view_cubit.dart';
import '../dialog/edit_capabilities_dialog.dart';
import 'mutual_friends_button.dart';

class ProfileViewBody extends StatelessWidget {
  const ProfileViewBody({super.key});

  String _trustReciprocityLabel(L10n l10n, Profile profile) {
    if (profile.isMutualFriend) return l10n.classMutual;
    if (profile.isFriend) return l10n.classOneWayOut;
    if (profile.isSeeingMe) return l10n.classOneWayIn;
    return l10n.classNone;
  }

  Future<void> _showTrustInfoSheet(BuildContext context) => showTenturaAdaptiveSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        useSafeArea: true,
        builder: (ctx) {
          final l10n = L10n.of(ctx)!;
          final tt = ctx.tt;
          return Padding(
            padding: EdgeInsets.fromLTRB(
              tt.screenHPadding,
              tt.rowGap,
              tt.screenHPadding,
              tt.sectionGap,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.trustInfoTitle,
                  style: Theme.of(ctx).textTheme.titleMedium,
                ),
                SizedBox(height: tt.rowGap),
                Text(
                  l10n.trustInfoBody,
                  style: Theme.of(ctx).textTheme.bodyMedium,
                ),
              ],
            ),
          );
        },
      );

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
              child: profile.hasAvatar
                  ? GestureDetector(
                      onTap: () =>
                          openProfileAvatarFullscreen(context, profile),
                      child: TenturaAvatar.big(
                        profile: profile,
                        withContactBadge: true,
                      ),
                    )
                  : TenturaAvatar.big(
                      profile: profile,
                      withContactBadge: true,
                    ),
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
                                  error: e,
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

            // Shared invite genealogy between the viewer and this person.
            Padding(
              padding: kPaddingSmallT,
              child: OutlinedButton.icon(
                onPressed: () => context
                    .read<ScreenCubit>()
                    .showInviteGenealogyWith(profile.id),
                icon: const Icon(Icons.device_hub_outlined),
                label: Text(l10n.showInviteGenealogy),
              ),
            ),

            // Beacons this person authored that were ever forwarded to the
            // viewer — privacy-scoped by forwarding, not friendship (a
            // beacon's existence is never revealed to someone who was never
            // forwarded it).
            Padding(
              padding: kPaddingSmallT,
              child: OutlinedButton.icon(
                onPressed: () => context
                    .read<ScreenCubit>()
                    .showInvolvedBeaconsOf(profile.id),
                icon: const Icon(Icons.open_in_full),
                label: Text(l10n.showBeaconsInvolvedIn),
              ),
            ),

            Padding(
              padding: kPaddingSmallT,
              child: MutualFriendsButton(userId: profile.id),
            ),

            if (profile.id.isNotEmpty)
              Padding(
                padding: kPaddingSmallT,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${l10n.trustRelationPrefix} ${_trustReciprocityLabel(l10n, profile)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),

            if (profile.isNotFriend)
              Padding(
                padding: kPaddingSmallT,
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: context.read<ProfileViewCubit>().addFriend,
                        icon: const Icon(Icons.people),
                        label: Text(l10n.addToMyField),
                      ),
                    ),
                    IconButton(
                      onPressed: () => _showTrustInfoSheet(context),
                      icon: const Icon(Icons.info_outline),
                      tooltip: l10n.trustInfoTitle,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
