import 'dart:async';
import 'package:flutter/material.dart';

import 'package:tentura/domain/capability/capability_tag.dart';
import 'package:tentura/domain/capability/person_capability_cues.dart';
import 'package:tentura/domain/capability/tag_projection.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/domain/util/availability_presets.dart';
import 'package:tentura/ui/model/person_action_policy.dart';
import 'package:tentura/ui/utils/availability_line.dart';
import 'package:tentura/ui/utils/capability_tag_presenter.dart';
import 'package:tentura/ui/utils/profile_presence_line.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/show_more_text.dart';
import 'package:tentura/ui/widget/trust_info_sheet.dart';
import 'package:tentura/ui/widget/trust_toggle_line.dart';
import 'package:tentura/ui/widget/tentura_fullscreen_image_viewer.dart';
import 'package:tentura/ui/widget/tentura_selection_area.dart';
import 'package:tentura/ui/widget/url_link_annotations.dart';
import 'package:tentura/design_system/tentura_design_system.dart';

import 'package:tentura/features/friends/ui/dialog/friend_remove_dialog.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';

import '../../domain/port/person_shared_context_port.dart';
import '../bloc/profile_view_cubit.dart';
import '../dialog/edit_capabilities_dialog.dart';
import 'edit_seed_suggestion_section.dart';
import 'mutual_friends_button.dart';
import 'profile_info_sheet.dart';
import 'seen_helping_with_strip.dart';

class ProfileViewBody extends StatelessWidget {
  const ProfileViewBody({this.showNetwork = true, super.key});

  /// False when [ProfileViewNetworkGroup] is placed in a supporting pane.
  final bool showNetwork;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    return BlocSelector<
      ProfileViewCubit,
      ProfileViewState,
      (Profile, List<PersonSharedContext>)
    >(
      selector: (state) => (state.profile, state.sharedContexts),
      builder: (context, selected) => SliverToBoxAdapter(
        child: BlocSelector<ProfileCubit, ProfileState, String>(
          selector: (s) => s.profile.id,
          builder: (context, myId) {
            final (profile, sharedContexts) = selected;
            final isSelf = profile.id.isNotEmpty && profile.id == myId;
            final todayUtc = availabilityTodayUtc();
            final policy = PersonActionPolicy.from(
              profile,
              isSelf: isSelf,
              isBlocked: false,
              todayUtc: todayUtc,
              sharesActiveContext: sharedContexts.isNotEmpty,
            );

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ProfileAvatarSection(profile: profile),
                Padding(
                  padding: kPaddingT,
                  child: TenturaSelectionArea(
                    child: ShowMoreText(
                      profile.description,
                      style: theme.textTheme.bodyMedium,
                      colorClickableText: theme.colorScheme.primary,
                      annotations: buildUrlAnnotations(
                        linkColor: context.tt.info,
                      ),
                    ),
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
                    sharedContexts: sharedContexts,
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
                if (showNetwork) ProfileViewNetworkGroup(profile: profile),
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

/// Your own trust vote toward this person, with the toggle that casts or
/// withdraws it (#140). Incoming trust is part of why the eye is open, so it
/// lives behind the eye's ⓘ.
class _ProfileTrustRelationLine extends StatelessWidget {
  const _ProfileTrustRelationLine({
    required this.l10n,
    required this.profile,
  });

  final L10n l10n;
  final Profile profile;

  @override
  Widget build(BuildContext context) {
    final trusts = profile.viewerExplicitlyTrustsSubject;
    final cubit = context.read<ProfileViewCubit>();
    return Padding(
      padding: kPaddingSmallT,
      child: TrustToggleLine(
        trusts: trusts,
        onTextTap: () => showTrustInfoSheet(context),
        onChanged: (on) => on
            ? unawaited(cubit.addFriend())
            : unawaited(
                FriendRemoveDialog.show(
                  context,
                  profile: profile,
                  onRemove: cubit.removeFriend,
                ),
              ),
      ),
    );
  }
}

/// The open / closed eye: the result of trust and MeritRank in both
/// directions (#140). One line on the profile; the reason sits behind ⓘ.
class _ProfileVisibilitySection extends StatelessWidget {
  const _ProfileVisibilitySection({
    required this.l10n,
    required this.profile,
    required this.policy,
    required this.sharedContexts,
  });

  final L10n l10n;
  final Profile profile;
  final PersonActionPolicy policy;
  final List<PersonSharedContext> sharedContexts;

  String _line() => switch (policy.visibilityState) {
    PersonVisibilityState.mutual => l10n.profileEyeOpen,
    PersonVisibilityState.sharedContext => l10n.profileVisibilitySharedContext(
      sharedContexts.first.title,
    ),
    PersonVisibilityState.viewerOnly ||
    PersonVisibilityState.subjectOnly ||
    PersonVisibilityState.neither => l10n.profileEyeClosed,
  };

  List<String> _reasons() {
    final name = profile.shownName;
    return [
      ...switch (policy.visibilityState) {
        PersonVisibilityState.mutual =>
          profile.isMutualFriend ||
                  (policy.viewerExplicitlyTrustsSubject &&
                      policy.subjectExplicitlyTrustsViewer)
              ? [l10n.profileEyeReasonMutualTrust]
              : [l10n.profileEyeReasonMeritRank],
        PersonVisibilityState.sharedContext => [
          l10n.profileVisibilitySharedContextNote,
        ],
        PersonVisibilityState.viewerOnly => [
          l10n.profileVisibilityYouCanSee(name),
          l10n.profileVisibilityCantSeeYou(name),
          l10n.profileEyeClosedHint,
        ],
        PersonVisibilityState.subjectOnly => [
          l10n.profileVisibilityTheyCanSeeYou(name),
          l10n.profileVisibilityYouDontSeeThem(name),
          l10n.profileEyeClosedHint,
        ],
        PersonVisibilityState.neither => [l10n.profileEyeClosedHint],
      },
      if (policy.subjectExplicitlyTrustsViewer &&
          !policy.viewerExplicitlyTrustsSubject)
        l10n.trustSentenceOneWayIn,
      l10n.profileEyeTrustNote,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final eyeOpen = policy.isMutuallyVisible;
    return ProfileFactRow(
      icon: eyeOpen ? Icons.visibility_outlined : Icons.visibility_off_outlined,
      text: _line(),
      trailing: IconButton(
        onPressed: () => showProfileInfoSheet(
          context,
          title: l10n.profileEyeInfoTitle,
          lines: _reasons(),
        ),
        tooltip: l10n.profileEyeInfoTitle,
        icon: const Icon(Icons.info_outline),
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

    return switch (policy.primaryAction) {
      PersonPrimaryAction.none => const SizedBox.shrink(),
      // The trust toggle on the trust line is the trust action (#140).
      PersonPrimaryAction.trust => const SizedBox.shrink(),
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
        return BlocSelector<
          ProfileViewCubit,
          ProfileViewState,
          List<TagProjection>
        >(
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

/// Capability labels the viewer links with a friend (#134): one compact
/// line. Each label carries its source: 🔒 the viewer's own note (only they
/// see it) or 👥 from forwards / help acknowledgements (the subject sees it
/// and it feeds suggestions for people who trust the viewer). The
/// explanation sits behind ⓘ.
class _ProfileCapabilitySection extends StatelessWidget {
  const _ProfileCapabilitySection({required this.profile});

  final Profile profile;

  static const _privateIcon = Icons.lock_outline;
  static const _sharedIcon = Icons.group_outlined;

  void _edit(BuildContext context, List<CapabilityWithSource> viewerVisible) {
    final cubit = context.read<ProfileViewCubit>();
    unawaited(
      EditCapabilitiesDialog.show(
        context,
        subjectId: profile.id,
        subjectName: profile.shownName,
        currentVisible: viewerVisible,
        onSaved: (slugs, automaticSlugs) => cubit.updateViewerVisible(
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
          showSnackBar(context, text: e.toString(), isError: true, error: e);
        }
      }),
    );
  }

  static String _labelOf(L10n l10n, CapabilityWithSource c) =>
      CapabilityTag.fromSlug(c.slug)?.labelOf(l10n) ?? c.slug;

  InlineSpan _labelsSpan(
    BuildContext context,
    L10n l10n,
    List<CapabilityWithSource> viewerVisible,
  ) {
    final theme = Theme.of(context);
    final tt = context.tt;
    final iconSize = theme.textTheme.bodySmall?.fontSize ?? tt.iconSize;
    final prefix = l10n.profileMyLabelsLine('');
    return TextSpan(
      children: [
        TextSpan(text: prefix),
        for (final (i, c) in viewerVisible.indexed) ...[
          if (i > 0) const TextSpan(text: ', '),
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Tooltip(
              message: c.hasManualLabel
                  ? l10n.profileLabelPrivate
                  : l10n.profileLabelShared,
              child: Icon(
                c.hasManualLabel ? _privateIcon : _sharedIcon,
                size: iconSize,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          TextSpan(
            text: ' ${CapabilityTag.fromSlug(c.slug)?.labelOf(l10n) ?? c.slug}',
          ),
        ],
      ],
    );
  }

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
        final name = profile.shownName;
        final isEmpty = viewerVisible.isEmpty;
        return ProfileFactRow(
          icon: Icons.label_outline,
          text: isEmpty
              ? l10n.profileMarkCapabilities(name)
              : l10n.profileMyLabelsLine(
                  viewerVisible.map((c) => _labelOf(l10n, c)).join(', '),
                ),
          richText: isEmpty ? null : _labelsSpan(context, l10n, viewerVisible),
          onTextTap: () => _edit(context, viewerVisible),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: () => _edit(context, viewerVisible),
                tooltip: l10n.profileEditLabels,
                icon: Icon(isEmpty ? Icons.add : Icons.edit_outlined),
              ),
              IconButton(
                onPressed: () => showProfileInfoSheet(
                  context,
                  title: l10n.profileLabelsInfoTitle,
                  lines: [
                    l10n.profileLabelsInfoPrivate,
                    l10n.profileLabelsInfoShared(name),
                  ],
                  lineIcons: const [_privateIcon, _sharedIcon],
                ),
                tooltip: l10n.profileLabelsInfoTitle,
                icon: const Icon(Icons.info_outline),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The other profile's navigation: connections, invite tree, shared
/// Requests and mutual trust.
class ProfileViewNetworkGroup extends StatelessWidget {
  const ProfileViewNetworkGroup({required this.profile, super.key});

  final Profile profile;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final screenCubit = context.read<ScreenCubit>();
    return Padding(
      padding: EdgeInsets.only(top: context.tt.sectionGap),
      child: TenturaMenuGroup(
        title: l10n.profileSectionNetwork,
        children: [
          TenturaMenuTile(
            icon: TenturaIcons.graph,
            title: l10n.showConnections,
            onTap: () => screenCubit.showGraphFor(profile.id),
          ),
          TenturaMenuTile(
            icon: Icons.device_hub_outlined,
            title: l10n.showInviteGenealogy,
            onTap: () => screenCubit.showInviteGenealogyWith(profile.id),
          ),
          TenturaMenuTile(
            icon: Icons.campaign_outlined,
            title: l10n.showBeaconsInvolvedIn,
            onTap: () => screenCubit.showInvolvedBeaconsOf(profile.id),
          ),
          MutualFriendsButton(userId: profile.id),
        ],
      ),
    );
  }
}

/// [ProfileViewNetworkGroup] for the current [ProfileViewCubit] profile, as a
/// sliver — the supporting pane's first section. Hidden for the viewer's own
/// profile and a blocked fallback, like the body it came from.
class ProfileViewNetworkSliver extends StatelessWidget {
  const ProfileViewNetworkSliver({super.key});

  @override
  Widget build(BuildContext context) =>
      BlocSelector<ProfileViewCubit, ProfileViewState, Profile>(
        selector: (state) => state.profile,
        builder: (context, profile) => SliverPadding(
          padding: context.tt.cardPadding,
          sliver: SliverToBoxAdapter(
            child: profile.id.isEmpty
                ? const SizedBox.shrink()
                : ProfileViewNetworkGroup(profile: profile),
          ),
        ),
      );
}
