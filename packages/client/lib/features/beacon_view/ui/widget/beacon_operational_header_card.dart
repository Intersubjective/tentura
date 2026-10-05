import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/domain/pinned_facts.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/beacon_view/ui/presenter/beacon_hud_author_action.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_details_facts_access_row.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_view_details_sheet.dart';
import 'package:tentura/features/closure/domain/entity/closure_member.dart';
import 'package:tentura/features/closure/ui/widget/closure_result_card.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/beacon_hud_metadata_composer.dart';
import 'package:tentura/ui/widget/beacon_hud_metadata_table.dart';
import 'package:tentura/ui/widget/beacon_hud_row_lead.dart';

import 'beacon_hud_action_button.dart';
import 'beacon_helper_hud_actions.dart';
import 'beacon_hud_author_act_block.dart';
import 'closed_request_banner.dart';
import 'request_access_reason_banner.dart';

/// Compact HUD header: metadata strip, NOW/YOU, action rail.
class BeaconOperationalHeaderCard extends StatelessWidget {
  const BeaconOperationalHeaderCard({
    required this.state,
    required this.onAuthorTap,
    this.onAuthorHudAction,
    this.onOfferHelp,
    this.onLeavePostChat,
    this.onEditHelpOffer,
    this.onWatch,
    this.onStopWatching,
    this.onSwitchToPeopleTab,
    this.onEditNowLine,
    this.onOpenItemDiscussion,
    this.onOpenPinnedFacts,
    this.onForward,
    this.showHudRows = true,
    super.key,
  });

  final BeaconViewState state;

  /// False when the pinned HUD block above already shows YOU / BLOCKER /
  /// NEXT STEP; the card then keeps only banners, author and actions, and
  /// leaves Details to the HUD's ABOUT row.
  final bool showHudRows;

  final VoidCallback onAuthorTap;

  final void Function(BeaconHudAuthorAction action)? onAuthorHudAction;
  final VoidCallback? onOfferHelp;

  /// Leaves the Request chat as a former Post member (`postLeave`).
  final VoidCallback? onLeavePostChat;
  final VoidCallback? onEditHelpOffer;
  final VoidCallback? onWatch;
  final VoidCallback? onStopWatching;

  /// Forward CTA — independent of the author/helper primary action; shown
  /// whenever the beacon allows forward, alongside whatever else is showing.
  final VoidCallback? onForward;

  /// Switches to the People lens (tab index 1).
  final VoidCallback? onSwitchToPeopleTab;

  /// Edit room current line (NOW row).
  final VoidCallback? onEditNowLine;

  /// Opens an item discussion thread (YOU sheet Reply action).
  final void Function(CoordinationItem item)? onOpenItemDiscussion;

  /// Opens the pinned facts sheet.
  final VoidCallback? onOpenPinnedFacts;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final authorSpec = state.isBeaconMine && onAuthorHudAction != null
        ? deriveBeaconHudAuthorActSpec(l10n: l10n, state: state)
        : null;
    final showPostOriginCard =
        state.isPostOriginParticipant && onLeavePostChat != null;
    final helperActions = authorSpec == null && !showPostOriginCard
        ? buildBeaconHelperHudActions(
            l10n: l10n,
            state: state,
            onOfferHelp: onOfferHelp,
            onEditHelpOffer: onEditHelpOffer,
            onWatch: onWatch,
            onStopWatching: onStopWatching,
          )
        : const BeaconHelperHudActions();
    final showForwardCta = state.beacon.viewerCanForward && onForward != null;
    final hasOtherAction = authorSpec != null || helperActions.hasActions;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        tt.screenHPadding,
        TenturaSpacing.row,
        tt.screenHPadding,
        TenturaSpacing.cardGap,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ClosedRequestBanner(beacon: state.beacon),
          if (state.beacon.status == BeaconStatus.closed &&
              !state.isBeaconMine &&
              state.isHelpOffered)
            Padding(
              padding: EdgeInsets.only(bottom: tt.cardGap),
              child: ClosureResultCard(
                beaconId: state.beacon.id,
                viewerId: state.myProfile.id,
                author: ClosureMember(
                  id: state.beacon.author.id,
                  displayName: state.beacon.author.shownName,
                ),
              ),
            ),
          RequestAccessReasonBanner(beacon: state.beacon),
          // Someone else's Request has to say whose it is; the author's own
          // view already knows.
          if (!state.isBeaconMine) ...[
            _AuthorLine(
              author: state.beacon.author,
              label: l10n.beaconViewAuthorLine(state.beacon.author.shownName),
              onTap: onAuthorTap,
            ),
            const SizedBox(height: kBeaconHudRowGap),
          ],
          if (showHudRows) ...[
            BeaconHudMetadataTable(
              buildEntries: (rowWidth) => buildBeaconViewHudMetadataEntries(
                context,
                rowWidth: rowWidth,
                state: state,
                onEditNowLine: onEditNowLine,
                onReviewAuthorOffers: onAuthorHudAction == null
                    ? null
                    : () => onAuthorHudAction!(
                        BeaconHudAuthorAction.reviewOffers,
                      ),
              ),
            ),
            const SizedBox(height: kBeaconHudRowGap),
          ],
          if (showPostOriginCard) ...[
            _PostOriginCard(
              l10n: l10n,
              onOfferHelp: onOfferHelp,
              onLeave: onLeavePostChat!,
            ),
            const SizedBox(height: kBeaconHudRowGap),
          ],
          BeaconDetailsFactsAccessRow(
            showDetails:
                showHudRows && beaconViewHasDetailsContent(state.beacon),
            factsCount: activePinnedFacts(state.factCards).length,
            factsNewCount: pinnedFactsNewCount(
              facts: state.factCards,
              seenAt: state.pinnedFactsSeenAt,
              viewerUserId: state.myProfile.id,
            ),
            canAddFacts: state.canCoordinateInBeaconRoom,
            onOpenDetails: () => unawaited(
              showBeaconViewDetailsSheet(context, beacon: state.beacon),
            ),
            onOpenFacts: onOpenPinnedFacts,
          ),
          const SizedBox(height: kBeaconHudRowGap),
          if (hasOtherAction || showForwardCta) ...[
            const SizedBox(height: 10),
            if (authorSpec != null)
              BeaconHudAuthorActBlock(
                spec: authorSpec,
                onPressed: state.isLoading
                    ? null
                    : () => onAuthorHudAction!(authorSpec.action),
              )
            else if (helperActions.hasActions)
              _HudActionStack(actions: helperActions),
            if (showForwardCta) ...[
              if (hasOtherAction) const SizedBox(height: kBeaconHudRowGap),
              BeaconHudActionButton(
                icon: Icons.send,
                label: l10n.labelForward,
                onPressed: onForward,
                filled: !hasOtherAction,
              ),
            ],
            const SizedBox(height: 10),
          ],
          Divider(height: 1, color: tt.border),
        ],
      ),
    );
  }
}

/// Intermediate state of a former Post member: in the chat, no offer yet.
class _PostOriginCard extends StatelessWidget {
  const _PostOriginCard({
    required this.l10n,
    required this.onOfferHelp,
    required this.onLeave,
  });

  final L10n l10n;
  final VoidCallback? onOfferHelp;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.postOriginCardTitle,
          style: TenturaText.title(tt.text),
        ),
        SizedBox(height: tt.tightGap),
        Text(
          l10n.postOriginCardBody,
          style: TenturaText.bodySmall(tt.textMuted),
        ),
        SizedBox(height: tt.rowGap),
        Wrap(
          spacing: tt.rowGap,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (onOfferHelp != null)
              BeaconHudActionButton(
                icon: Icons.volunteer_activism_outlined,
                label: l10n.labelOfferHelp,
                onPressed: onOfferHelp,
                filled: true,
              ),
            TextButton(
              onPressed: onLeave,
              child: Text(l10n.postOriginLeaveChat),
            ),
          ],
        ),
      ],
    );
  }
}

class _HudActionRail extends StatelessWidget {
  const _HudActionRail({required this.actions});

  final List<BeaconHudActionSpec> actions;

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return const SizedBox.shrink();
    final wide = context.windowClass != WindowClass.compact;
    return Row(
      // Default cross-axis is center. Avoid stretch: header sits in a sliver with
      // unbounded height, and stretch would pass infinite extent to children.
      children: [
        for (var i = 0; i < actions.length; i++) ...[
          if (i != 0) const SizedBox(width: 8),
          if (wide)
            _HudActionButton(spec: actions[i])
          else
            Expanded(
              child: _HudActionButton(spec: actions[i]),
            ),
        ],
      ],
    );
  }
}

class _HudActionStack extends StatelessWidget {
  const _HudActionStack({required this.actions});

  final BeaconHelperHudActions actions;

  @override
  Widget build(BuildContext context) {
    return _HudActionRail(actions: actions.primary);
  }
}

class _HudActionButton extends StatelessWidget {
  const _HudActionButton({required this.spec});

  final BeaconHudActionSpec spec;

  @override
  Widget build(BuildContext context) {
    return BeaconHudActionButton(
      icon: spec.icon,
      label: spec.label,
      onPressed: spec.onPressed,
      filled: spec.filled,
    );
  }
}

/// Read-only lifecycle pill (legacy beacon detail strip).
class BeaconCardPillReadOnly extends StatelessWidget {
  const BeaconCardPillReadOnly({required this.l10n, super.key});

  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: TenturaSpacing.cardPadding,
        vertical: TenturaSpacing.iconText,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(TenturaRadii.avatar),
      ),
      child: Text(
        l10n.beaconCtaReadOnly,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Avatar in the HUD lead column, "By `<name>`" on the HUD text keyline.
class _AuthorLine extends StatelessWidget {
  const _AuthorLine({
    required this.author,
    required this.label,
    required this.onTap,
  });

  final Profile author;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return Semantics(
      button: true,
      label: label,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(tt.buttonRadius),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: kMinInteractiveDimension,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: kBeaconHudRowLeadWidth,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TenturaAvatar(
                      profile: author,
                      size: kBeaconHudRowIconSize + tt.tightGap * 2,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TenturaText.bodySmall(tt.text),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
