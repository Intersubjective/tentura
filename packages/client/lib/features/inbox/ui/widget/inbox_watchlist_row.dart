import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/coordination/derive_beacon_coordination_phase.dart';
import 'package:tentura/features/beacon/ui/widget/beacon_overflow_menu.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_details_facts_access_row.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_view_details_sheet.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_room_card_hints.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/presenter/beacon_phase_input_builders.dart';
import 'package:tentura/ui/presenter/beacon_phase_presenter.dart';
import 'package:tentura/ui/utils/beacon_card_deadline.dart';
import 'package:tentura/ui/widget/beacon_card_primitives.dart';
import 'package:tentura/ui/widget/beacon_requirements_bar.dart';

import '../../domain/entity/inbox_item.dart';
import '../../domain/enum.dart';
import 'inbox_card_action_row.dart';

/// The Watching / Rejected list row.
///
/// Replaces `InboxItemTile`, retired in U17b. The tile carried a provenance
/// fold (`InboxCardForwardsFold`) that neither of its two live callers ever
/// showed — both passed `showProvenance: false` — and whose forward-note
/// content U16a had already ported into the For You forward mini-card. What
/// survived of the fold here is the calendar deadline line, which this row
/// renders directly.
///
/// These lists are **not** attention surfaces: they are the viewer's own
/// standing choices. So there is no attention marker and no clear control —
/// the two things the tile carried for a caller that no longer exists.
class InboxWatchlistRow extends StatelessWidget {
  const InboxWatchlistRow({
    required this.item,
    required this.onOpenBeacon,
    this.onTap,
    this.onWatch,
    this.onStopWatching,
    this.onCantHelp,
    this.onDismissFromInbox,
    this.onMoveToInbox,
    this.onOfferHelp,
    this.showCtaRow = true,
    this.showForwardCta = true,
    this.isSelected = false,
    super.key,
  });

  final InboxItem item;
  final VoidCallback onOpenBeacon;

  /// Forward this Request.
  final VoidCallback? onTap;
  final VoidCallback? onWatch;
  final VoidCallback? onStopWatching;
  final Future<void> Function()? onCantHelp;

  /// Card dismiss (X) — inbox-oriented dialog; falls back to [onCantHelp].
  final Future<void> Function()? onDismissFromInbox;
  final VoidCallback? onMoveToInbox;
  final Future<void> Function()? onOfferHelp;

  /// When false (Rejected), hide the footer offer-help / secondary cluster;
  /// those actions remain in the overflow menu.
  final bool showCtaRow;

  /// When false (Rejected), hide the footer Forward button regardless of
  /// [onTap]. Independent of [showCtaRow] so Watching can show Forward while
  /// still hiding the offer-help cluster.
  final bool showForwardCta;

  /// Master–detail selection chrome (highlight-on-arrival).
  final bool isSelected;

  bool get _hasDismissAction =>
      onDismissFromInbox != null || onCantHelp != null;

  String? _secondaryLabel(L10n l10n) {
    // Icon-only tertiary button for dismiss (see _secondaryIcon()).
    if (_hasDismissAction) return null;
    if (onStopWatching != null) return l10n.actionStopWatching;
    if (onMoveToInbox != null) return l10n.actionMoveToInbox;
    return null;
  }

  IconData? _secondaryIcon() {
    if (_hasDismissAction) return Icons.close;
    if (onStopWatching != null) return Icons.visibility_off_outlined;
    if (onMoveToInbox != null) return Icons.inbox_outlined;
    return null;
  }

  Future<void> _onSecondaryPressed() async {
    if (onDismissFromInbox != null) {
      await onDismissFromInbox?.call();
      return;
    }
    if (onCantHelp != null) {
      await onCantHelp?.call();
      return;
    }
    if (onStopWatching != null) {
      onStopWatching?.call();
      return;
    }
    onMoveToInbox?.call();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tt = context.tt;
    final beacon = item.beacon;
    if (beacon == null) return const SizedBox.shrink();

    final secondaryLabel = _secondaryLabel(l10n);
    final secondaryIcon = _secondaryIcon();

    final phaseResult = deriveBeaconCoordinationPhase(
      beaconPhaseInputFromInbox(beacon: beacon, roomHints: item.roomHints),
    );
    final phaseStatus = formatBeaconPhaseStatus(
      l10n,
      phaseResult,
      now: DateTime.now(),
    );

    final showDetails = beaconViewHasDetailsContent(beacon);
    final showForwardInFooter = showForwardCta && onTap != null;
    final showFooter = showCtaRow || showForwardInFooter;
    final deadline = _deadlineLine(context, l10n, beacon.endAt, beacon.startAt);

    return BeaconCardShell(
      onTap: onOpenBeacon,
      selected: isSelected,
      tapSemanticsLabel: beacon.title.isEmpty ? l10n.openBeacon : beacon.title,
      footer: showFooter
          ? InboxCardActionRow(
              onOfferHelp: showCtaRow ? onOfferHelp : null,
              onForward: showForwardInFooter ? onTap : null,
              secondaryLabel: showCtaRow ? secondaryLabel : null,
              secondaryIcon: showCtaRow ? secondaryIcon : null,
              secondaryTooltip: showCtaRow && _hasDismissAction
                  ? l10n.inboxDismissTooltip
                  : null,
              onSecondary:
                  showCtaRow && (secondaryLabel != null || secondaryIcon != null)
                  ? _onSecondaryPressed
                  : null,
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BeaconCardHeaderRow(
            beacon: beacon,
            onTitleBlockTap: onOpenBeacon,
            phaseStatus: phaseStatus,
            menu: BeaconOverflowMenu(
              beacon: beacon,
              onOpenBeacon: onOpenBeacon,
              onOfferHelp: onOfferHelp != null
                  ? () async {
                      await onOfferHelp?.call();
                    }
                  : null,
              onForward: onTap,
              onForwardsGraph: () =>
                  context.read<ScreenCubit>().showForwardsGraphFor(beacon.id),
              onWatch: onWatch,
              onStopWatching: onStopWatching,
              onCantHelp: onCantHelp,
              onMoveToInbox: onMoveToInbox,
              onComplaint: () =>
                  context.read<ScreenCubit>().showComplaint(beacon.id),
            ),
          ),
          SizedBox(height: tt.rowGap),
          BeaconCardMetadataLine(beacon: beacon, updatedLine: null),
          if (showDetails) ...[
            SizedBox(height: tt.rowGap),
            BeaconDetailsFactsAccessRow(
              showDetails: true,
              factsCount: 0,
              factsNewCount: 0,
              onOpenDetails: () => unawaited(
                showBeaconViewDetailsSheet(context, beacon: beacon),
              ),
              onOpenFacts: null,
            ),
          ],
          if (beacon.needs.isNotEmpty) ...[
            SizedBox(height: tt.rowGap),
            BeaconRequirementsBar(needs: beacon.needs),
          ],
          if (item.roomHints != null) ...[
            SizedBox(height: tt.rowGap),
            ..._roomHintLines(context, l10n, item.roomHints!),
          ],
          if (deadline != null) ...[
            SizedBox(height: tt.rowGap),
            deadline,
            SizedBox(height: tt.sectionGap),
          ],
          if (item.status == InboxItemStatus.rejected &&
              item.rejectionMessage.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(top: tt.rowGap),
              child: Text(
                item.rejectionMessage,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                softWrap: true,
              ),
            ),
        ],
      ),
    );
  }

  /// The calendar-style due line the retired fold used to host.
  Widget? _deadlineLine(
    BuildContext context,
    L10n l10n,
    DateTime? endAt,
    DateTime? startAt,
  ) {
    final meta = beaconCardCalendarDeadlineStatus(l10n, endAt, startAt: startAt);
    if (meta == null) return null;
    final theme = Theme.of(context);
    if (meta.overdue) {
      return TenturaStatusText(
        meta.text,
        tone: TenturaTone.danger,
        maxLines: null,
        overflow: TextOverflow.visible,
      );
    }
    return Text(
      meta.text,
      softWrap: true,
      style: theme.textTheme.bodySmall!.copyWith(
        height: 1.15,
        color: theme.colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  List<Widget> _roomHintLines(
    BuildContext context,
    L10n l10n,
    InboxRoomCardHints h,
  ) {
    if (!h.isRoomMember) return const [];
    final theme = Theme.of(context);
    final tt = context.tt;
    final out = <Widget>[
      TenturaStatusText(
        l10n.inboxCardRoomUnread(h.roomUnreadCount),
        tone: TenturaTone.info,
        maxLines: null,
        overflow: TextOverflow.visible,
      ),
    ];
    final blockerTitle = h.openBlocker?.title ?? h.openBlockerTitle;
    if (blockerTitle.isNotEmpty) {
      out.add(
        Padding(
          padding: EdgeInsets.only(top: tt.tightGap),
          child: TenturaStatusText(
            l10n.inboxCardOpenBlocker(blockerTitle),
            tone: TenturaTone.warn,
            maxLines: null,
            overflow: TextOverflow.visible,
          ),
        ),
      );
    }
    for (final line in <String>[
      if (h.currentLineSnippet.isNotEmpty)
        l10n.inboxCardRoomCurrentLine(h.currentLineSnippet),
      if (h.myNextMove.isNotEmpty) l10n.inboxCardRoomNextMove(h.myNextMove),
      if (h.lastRoomMeaningfulChange.isNotEmpty)
        l10n.inboxCardRoomLastChange(h.lastRoomMeaningfulChange),
    ]) {
      out.add(
        Padding(
          padding: EdgeInsets.only(top: tt.tightGap),
          child: Text(line, style: theme.textTheme.bodySmall, softWrap: true),
        ),
      );
    }
    return out;
  }
}
