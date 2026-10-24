import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:tentura/domain/capability/friend_context.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/people_tags/ui/widget/add_to_tag_sheet.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/presence_avatar.dart';
import 'package:tentura/ui/widget/self_user_highlight.dart';

import 'capability_cue_strip.dart';

/// Network/Friends surface card for a peer.
///
/// Tapping anywhere opens the peer's profile. No chat navigation is wired here.
/// Signal-strength order: closeAck > commitRole > forwardReason > privateLabel.
class NetworkPersonCard extends StatelessWidget {
  const NetworkPersonCard({
    required this.profile,
    this.friendContext = FriendContext.empty,
    this.trailing,
    this.privateLabels = const [],
    this.forwardedForSlugs = const [],
    this.commitRoleSlugs = const [],
    this.closeAckSlugs = const [],
    this.peopleTagsEnabled = kPeopleTagsEnabled,
    super.key,
  });

  final Profile profile;

  final FriendContext friendContext;

  /// Optional trailing widget (e.g. a Forward button).
  final Widget? trailing;

  /// Private-label slugs this viewer has set for [profile] (Phase 1+).
  final List<String> privateLabels;

  /// Forward-reason slugs (aggregated by count) — "Often forwarded for" (Phase 2+).
  final List<String> forwardedForSlugs;

  /// Commit-role slugs — "Committed" (Phase 3+).
  final List<String> commitRoleSlugs;

  /// Close-acknowledgement slugs — strongest signal (Phase 4+).
  final List<String> closeAckSlugs;

  /// Offers the person menu ("Add to tag…"); off with the feature gate.
  final bool peopleTagsEnabled;

  static const _touchOrStylus = {
    PointerDeviceKind.touch,
    PointerDeviceKind.stylus,
  };

  List<PopupMenuEntry<void>> _menuEntries(BuildContext context, L10n l10n) => [
    PopupMenuItem<void>(
      onTap: () => unawaited(showAddToTagSheet(context, personId: profile.id)),
      child: Text(l10n.peopleTagsAddToTag),
    ),
  ];

  void _showMenuAt(BuildContext context, Offset globalPosition) {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    unawaited(
      showMenu<void>(
        context: context,
        position: RelativeRect.fromRect(
          globalPosition & const Size(1, 1),
          Offset.zero & overlay.size,
        ),
        items: _menuEntries(context, L10n.of(context)!),
      ),
    );
  }

  String _trustReciprocityLabel(L10n l10n) {
    if (profile.isMutualFriend) return l10n.trustSentenceMutual;
    if (profile.isFriend) return l10n.trustSentenceOneWayOut;
    if (profile.subjectExplicitlyTrustsViewer) return l10n.trustSentenceOneWayIn;
    return l10n.trustSentenceNone;
  }

  @override
  Widget build(BuildContext context) {
    final screenCubit = context.read<ScreenCubit>();
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final tt = context.tt;
    final selected = TenturaListDetailSelection.of(context) == profile.id;
    final hasMenu =
        peopleTagsEnabled &&
        !SelfUserHighlight.profileIsSelf(
          profile,
          context.read<ProfileCubit>().state.profile.id,
        );
    Widget row = InkWell(
      onTap: () =>
          screenCubit.showProfile(profile.id, entry: kProfileEntryPeople),
      child: Padding(
        // The screen already insets the list by screenHPadding; a second
        // inset put rows 8-24 dp inside the tab bar's start edge. A 3-4 line
        // row carries a list-size avatar, top-aligned with the name, at the
        // same avatar/text gap as every other people list.
        padding: EdgeInsets.symmetric(vertical: tt.cardGap),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PresenceAvatar.medium(
              profile: profile,
              userId: profile.id,
              withContactBadge: true,
            ),
            SizedBox(width: tt.avatarTextGap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  BlocBuilder<ProfileCubit, ProfileState>(
                    buildWhen: (p, c) => p.profile.id != c.profile.id,
                    builder: (context, state) {
                      final isSelf = SelfUserHighlight.profileIsSelf(
                        profile,
                        state.profile.id,
                      );
                      final primary = isSelf
                          ? SelfUserHighlight.displayName(
                              l10n,
                              profile,
                              state.profile.id,
                            )
                          : (profile.shownName.isEmpty
                                ? l10n.noName
                                : profile.shownName);
                      final secondary = profile.canonicalSecondaryLabel;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            primary,
                            style: SelfUserHighlight.nameStyle(
                              theme,
                              theme.textTheme.bodyLarge,
                              isSelf,
                            ),
                          ),
                          if (secondary.isNotEmpty)
                            Text(
                              secondary,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          if (!isSelf)
                            Text(
                              _trustReciprocityLabel(l10n),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                  // Signal-strength order: closeAck > commitRole > forwardReason > privateLabel
                  if (closeAckSlugs.isNotEmpty)
                    Text(
                      l10n.capabilityCueAcknowledged(
                        closeAckSlugs.join(' · '),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    )
                  else if (commitRoleSlugs.isNotEmpty)
                    Text(
                      l10n.capabilityCueHelpOffered(
                        commitRoleSlugs.join(' · '),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    )
                  else if (forwardedForSlugs.isNotEmpty)
                    Text(
                      l10n.capabilityCueForwardedFor(
                        forwardedForSlugs.join(' · '),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    )
                  else if (privateLabels.isNotEmpty)
                    CapabilityCueStrip(slugs: privateLabels),

                  _FriendContextCountsRow(
                    l10n: l10n,
                    theme: theme,
                    context: friendContext,
                  ),
                ],
              ),
            ),
            ?trailing,
            if (hasMenu)
              PopupMenuButton<void>(
                itemBuilder: (menuContext) => _menuEntries(context, l10n),
              ),
          ],
        ),
      ),
    );
    if (hasMenu) {
      row = RawGestureDetector(
        behavior: HitTestBehavior.deferToChild,
        gestures: {
          LongPressGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
                () => LongPressGestureRecognizer(
                  supportedDevices: _touchOrStylus,
                ),
                (r) => r
                  ..onLongPressStart = (details) =>
                      _showMenuAt(context, details.globalPosition),
              ),
          TapGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                TapGestureRecognizer.new,
                (r) => r
                  ..onSecondaryTapUp = (details) =>
                      _showMenuAt(context, details.globalPosition),
              ),
        },
        child: row,
      );
    }
    // Material 3 list-detail: the person whose profile is open beside this
    // list is marked selected.
    return Semantics(
      selected: selected,
      child: selected
          ? Material(
              color: Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(context.tt.cardRadius),
              child: row,
            )
          : row,
    );
  }
}

class _FriendContextCountsRow extends StatelessWidget {
  const _FriendContextCountsRow({
    required this.l10n,
    required this.theme,
    required this.context,
  });

  final L10n l10n;
  final ThemeData theme;
  final FriendContext context;

  @override
  Widget build(BuildContext context) {
    final inbox = this.context.activeForwardsToCount;
    final shared = this.context.coInvolvedBeaconsCount;
    if (inbox <= 0 && shared <= 0) return const SizedBox.shrink();

    final style = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Padding(
      padding: EdgeInsets.only(top: context.tt.tightGap * 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (inbox > 0) ...[
            Tooltip(
              message: L10n.of(context)!.friendContextInboxCount(inbox),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.send_outlined,
                    size: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    L10n.of(context)!.friendContextInboxShort(inbox),
                    style: style,
                  ),
                ],
              ),
            ),
          ],
          if (shared > 0) ...[
            if (inbox > 0) const SizedBox(width: 10),
            Tooltip(
              message: L10n.of(context)!.friendContextSharedCount(shared),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.radio_button_checked,
                    size: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    L10n.of(context)!.friendContextSharedShort(shared),
                    style: style,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
