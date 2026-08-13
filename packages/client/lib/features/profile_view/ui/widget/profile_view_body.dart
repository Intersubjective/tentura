import 'dart:async';
import 'package:flutter/material.dart';

import 'package:tentura/domain/capability/person_capability_cues.dart';
import 'package:tentura/domain/capability/tag_projection.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/features/profile/ui/sheet/availability_sheet.dart';
import 'package:tentura/ui/model/person_action_policy.dart';
import 'package:tentura/ui/utils/availability_line.dart';
import 'package:tentura/ui/utils/profile_presence_line.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/design_system/components/tentura_avatar.dart';
import 'package:tentura/ui/widget/contact_badge_legend.dart';
import 'package:tentura/ui/widget/show_more_text.dart';
import 'package:tentura/ui/widget/tentura_fullscreen_image_viewer.dart';
import 'package:tentura/ui/widget/tentura_icons.dart';
import 'package:tentura/design_system/tentura_design_system.dart';

import 'package:tentura/features/capability/ui/widget/capability_cue_strip.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';

import '../bloc/profile_view_cubit.dart';
import '../dialog/edit_capabilities_dialog.dart';
import 'edit_seed_suggestion_section.dart';
import 'mutual_friends_button.dart';
import 'seen_helping_with_strip.dart';

class ProfileViewBody extends StatelessWidget {
  const ProfileViewBody({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    return BlocSelector<ProfileViewCubit, ProfileViewState, Profile>(
      selector: (state) => state.profile,
      builder: (context, profile) => SliverToBoxAdapter(
        child: BlocSelector<ProfileCubit, ProfileState, String>(
          selector: (s) => s.profile.id,
          builder: (context, myId) {
            final isSelf = profile.id.isNotEmpty && profile.id == myId;
            final todayUtc = availabilityTodayUtc();
            final policy = PersonActionPolicy.from(
              profile,
              isSelf: isSelf,
              isBlocked: false,
              todayUtc: todayUtc,
            );

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ProfileAvatarSection(profile: profile),
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
                if (!isSelf && profile.id.isNotEmpty) ...[
                  _OtherProfileAvailabilityLine(
                    profile: profile,
                    todayUtc: todayUtc,
                  ),
                  _ProfileTrustRelationLine(l10n: l10n, profile: profile),
                  _ProfileVisibilitySection(
                    l10n: l10n,
                    profile: profile,
                    policy: policy,
                  ),
                  _ProfilePrimaryAction(
                    l10n: l10n,
                    profile: profile,
                    policy: policy,
                  ),
                  _ProfileSecondaryActions(
                    l10n: l10n,
                    theme: theme,
                    profile: profile,
                    policy: policy,
                  ),
                ],
                const _SeenHelpingWithSection(),
                _EditSeedSuggestionSection(profile: profile),
                _ProfileCapabilitySection(profile: profile),
                Padding(
                  padding: kPaddingSmallT,
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        context.read<ScreenCubit>().showGraphFor(profile.id),
                    icon: const Icon(TenturaIcons.graph),
                    label: Text(l10n.showConnections),
                  ),
                ),
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
              ],
            );
          },
        ),
      ),
    );
  }
}

class _OtherProfileAvailabilityLine extends StatelessWidget {
  const _OtherProfileAvailabilityLine({
    required this.profile,
    required this.todayUtc,
  });

  final Profile profile;
  final DateTime todayUtc;

  @override
  Widget build(BuildContext context) {
    final line = otherAvailabilityStatusLine(
      L10n.of(context)!,
      profile.availability,
      todayUtc,
    );
    if (line == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: kPaddingSmallT,
      child: TenturaStatusText(
        line,
        tone: TenturaTone.neutral,
        maxLines: null,
        softWrap: true,
      ),
    );
  }
}

class _ProfileAvatarSection extends StatelessWidget {
  const _ProfileAvatarSection({required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context) => Center(
    child: profile.hasAvatar
        ? GestureDetector(
            onTap: () => openProfileAvatarFullscreen(context, profile),
            child: TenturaAvatar.big(
              profile: profile,
              withContactBadge: true,
            ),
          )
        : TenturaAvatar.big(
            profile: profile,
            withContactBadge: true,
          ),
  );
}

class _ProfileTrustRelationLine extends StatelessWidget {
  const _ProfileTrustRelationLine({
    required this.l10n,
    required this.profile,
  });

  final L10n l10n;
  final Profile profile;

  String _trustReciprocityLabel() {
    if (profile.isMutualFriend) return l10n.classMutual;
    if (profile.isFriend) return l10n.classOneWayOut;
    if (profile.subjectExplicitlyTrustsViewer) return l10n.classOneWayIn;
    return l10n.classNone;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: kPaddingSmallT,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          '${l10n.trustRelationPrefix} ${_trustReciprocityLabel()}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _ProfileVisibilitySection extends StatelessWidget {
  const _ProfileVisibilitySection({
    required this.l10n,
    required this.profile,
    required this.policy,
  });

  final L10n l10n;
  final Profile profile;
  final PersonActionPolicy policy;

  List<String> _directionalLines() {
    final name = profile.shownName;
    return switch (policy.visibilityState) {
      PersonVisibilityState.mutual => [l10n.profileVisibilityMutual],
      PersonVisibilityState.viewerOnly => [
        l10n.profileVisibilityYouCanSee(name),
        l10n.profileVisibilityCantSeeYou(name),
      ],
      PersonVisibilityState.subjectOnly => [
        l10n.profileVisibilityTheyCanSeeYou(name),
        l10n.profileVisibilityYouDontSeeThem(name),
      ],
      PersonVisibilityState.neither => [l10n.profileVisibilityNeither],
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tt = context.tt;
    final eyeOpen = policy.isMutuallyVisible;
    final eyeTooltip = eyeOpen
        ? l10n.graphLegendEyeOpen
        : l10n.graphLegendEyeClosed;

    return Padding(
      padding: kPaddingSmallT,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Tooltip(
            message: eyeTooltip,
            child: Icon(
              eyeOpen
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              size: tt.iconSize,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          SizedBox(width: tt.iconTextGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final line in _directionalLines())
                  Text(
                    line,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfilePrimaryAction extends StatelessWidget {
  const _ProfilePrimaryAction({
    required this.l10n,
    required this.profile,
    required this.policy,
  });

  final L10n l10n;
  final Profile profile;
  final PersonActionPolicy policy;

  @override
  Widget build(BuildContext context) {
    final screenCubit = context.read<ScreenCubit>();
    final profileViewCubit = context.read<ProfileViewCubit>();

    return switch (policy.primaryAction) {
      PersonPrimaryAction.none => const SizedBox.shrink(),
      PersonPrimaryAction.trust => Padding(
        padding: kPaddingSmallT,
        child: Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: profileViewCubit.addFriend,
                icon: const Icon(Icons.people),
                label: Text(l10n.trustThisUser),
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
      PersonPrimaryAction.sendRequest => Padding(
        padding: kPaddingSmallT,
        child: FilledButton.icon(
          onPressed: () => screenCubit.showForwardToPerson(profile.id),
          icon: const Icon(Icons.send_outlined),
          label: Text(l10n.profileSendRequestTo),
        ),
      ),
    };
  }
}

class _ProfileSecondaryActions extends StatelessWidget {
  const _ProfileSecondaryActions({
    required this.l10n,
    required this.theme,
    required this.profile,
    required this.policy,
  });

  final L10n l10n;
  final ThemeData theme;
  final Profile profile;
  final PersonActionPolicy policy;

  @override
  Widget build(BuildContext context) {
    final screenCubit = context.read<ScreenCubit>();
    final profileViewCubit = context.read<ProfileViewCubit>();
    final children = <Widget>[];

    if (policy.primaryAction == PersonPrimaryAction.none &&
        policy.showRequestOptions &&
        profile.viewerExplicitlyTrustsSubject) {
      children.add(
        Text(
          l10n.profileRequestUnavailable,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    if (policy.showSecondaryTrust) {
      children.add(
        OutlinedButton.icon(
          onPressed: profileViewCubit.addFriend,
          icon: const Icon(Icons.people_outlined),
          label: Text(l10n.trustThisUser),
        ),
      );
    }

    if (policy.showRequestOptions) {
      children.add(
        OutlinedButton.icon(
          onPressed: () => screenCubit.showForwardToPerson(profile.id),
          icon: const Icon(Icons.alt_route_outlined),
          label: Text(l10n.profileRequestOptions),
        ),
      );
    }

    if (children.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: kPaddingSmallT,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) SizedBox(height: context.tt.rowGap),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _EditSeedSuggestionSection extends StatelessWidget {
  const _EditSeedSuggestionSection({required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context) {
    final myId = context.read<ProfileCubit>().state.profile.id;
    if (profile.id.isEmpty || profile.id == myId) {
      return const SizedBox.shrink();
    }
    return EditSeedSuggestionSection(profile: profile);
  }
}

class _SeenHelpingWithSection extends StatelessWidget {
  const _SeenHelpingWithSection();

  @override
  Widget build(BuildContext context) {
    return BlocSelector<ProfileViewCubit, ProfileViewState, bool>(
      selector: (state) => state.subjectiveTags.isNotEmpty,
      builder: (context, showStrip) {
        if (!showStrip) return const SizedBox.shrink();
        return BlocSelector<ProfileViewCubit, ProfileViewState, List<TagProjection>>(
          selector: (state) => state.subjectiveTags,
          builder: (context, subjectiveTags) => Padding(
            padding: kPaddingSmallT,
            child: SeenHelpingWithStrip(projections: subjectiveTags),
          ),
        );
      },
    );
  }
}

class _ProfileCapabilitySection extends StatelessWidget {
  const _ProfileCapabilitySection({required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    return BlocSelector<
      ProfileViewCubit,
      ProfileViewState,
      (List<CapabilityWithSource>, bool)
    >(
      selector: (s) => (s.cues.viewerVisible, s.profile.isFriend),
      builder: (context, rec) {
        final (viewerVisible, isFriend) = rec;
        final myId = context.read<ProfileCubit>().state.profile.id;
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
                                    hasManualLabel: !automaticSlugs.contains(s),
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
    );
  }
}

Future<void> _showTrustInfoSheet(BuildContext context) =>
    showTenturaAdaptiveSheet<void>(
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
              SizedBox(height: tt.sectionGap),
              const ContactBadgeLegend(showTextLabelNote: true),
            ],
          ),
        );
      },
    );
