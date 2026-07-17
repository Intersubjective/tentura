import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/coordination/derive_beacon_coordination_phase.dart';
import 'package:tentura/features/beacon/ui/widget/beacon_overflow_menu.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/presenter/beacon_phase_input_builders.dart';
import 'package:tentura/ui/presenter/beacon_phase_presenter.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/beacon_card_primitives.dart';
import 'package:tentura/ui/widget/beacon_requirements_bar.dart';
import 'package:tentura/features/home/ui/widget/attention_marker.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';

import '../../domain/entity/inbox_item.dart';
import '../../domain/enum.dart';
import 'inbox_card_action_row.dart';
import 'inbox_card_forwards_fold.dart';

import 'package:tentura/features/inbox/domain/entity/inbox_room_card_hints.dart';

class InboxItemTile extends StatelessWidget {
  const InboxItemTile({
    required this.item,
    required this.onOpenBeacon,
    required this.onTap,
    this.onWatch,
    this.onStopWatching,
    this.onCantHelp,
    this.onDismissFromInbox,
    this.onMoveToInbox,
    this.onOfferHelp,
    this.showCtaRow = true,
    this.showProvenance = true,
    this.attentionMarked = false,
    super.key,
  });

  final InboxItem item;
  final VoidCallback onOpenBeacon;
  final VoidCallback onTap;
  final VoidCallback? onWatch;
  final VoidCallback? onStopWatching;
  final Future<void> Function()? onCantHelp;

  /// Card dismiss (X) — inbox-oriented dialog; falls back to [onCantHelp].
  final Future<void> Function()? onDismissFromInbox;
  final VoidCallback? onMoveToInbox;

  /// Offer help for this beacon (same flow as beacon view); null hides the menu item.
  final Future<void> Function()? onOfferHelp;

  /// When false (Watching / Rejected tabs), hide the bottom Forward / secondary
  /// button row; actions remain in the overflow menu.
  final bool showCtaRow;

  /// When false (Watching / Rejected tabs), hide the whole forwarder block
  /// (avatars, expand, quotes).
  final bool showProvenance;

  /// Whether unread semantic attention currently maps to this Inbox card.
  final bool attentionMarked;

  String? _secondaryLabel(L10n l10n) {
    // Icon-only tertiary button for dismiss (see _secondaryIcon()).
    if (_hasDismissAction) return null;
    if (onStopWatching != null) return l10n.actionStopWatching;
    if (onMoveToInbox != null) return l10n.actionMoveToInbox;
    return null;
  }

  bool get _hasDismissAction =>
      onDismissFromInbox != null || onCantHelp != null;

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

    final hasProvenance = showProvenance && item.provenance.senders.isNotEmpty;
    final showDeadlineOrForwardsRow = hasProvenance || beacon.endAt != null;
    final updatedLine = beaconHasRealUpdate(beacon)
        ? l10n.myWorkUpdatedLine(
            '${dateFormatYMD(beacon.updatedAt)} ${timeFormatHm(beacon.updatedAt)}',
          )
        : null;

    final phaseInput = beaconPhaseInputFromInbox(
      beacon: beacon,
      roomHints: item.roomHints,
    );
    final phaseResult = deriveBeaconCoordinationPhase(phaseInput);
    final phaseStatus = formatBeaconPhaseStatus(
      l10n,
      phaseResult,
      now: DateTime.now(),
    );

    return BeaconCardShell(
      onTap: onOpenBeacon,
      tapSemanticsLabel: beacon.title.isEmpty ? l10n.openBeacon : beacon.title,
      marker: attentionMarked ? const AttentionMarker() : null,
      footer: showCtaRow
          ? InboxCardActionRow(
              onOfferHelp: onOfferHelp,
              onForward: onTap,
              secondaryLabel: secondaryLabel,
              secondaryIcon: secondaryIcon,
              secondaryTooltip: _hasDismissAction
                  ? l10n.inboxDismissTooltip
                  : null,
              onSecondary: (secondaryLabel != null || secondaryIcon != null)
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
            statusLine: phaseStatus.statusLine,
            statusTone: phaseStatus.tone,
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
          BeaconCardMetadataLine(
            beacon: beacon,
            updatedLine: updatedLine,
          ),
          if (beacon.needs.isNotEmpty) ...[
            SizedBox(height: tt.rowGap),
            BeaconRequirementsBar(needs: beacon.needs),
          ],
          if (item.roomHints != null) ...[
            SizedBox(height: tt.rowGap),
            ..._roomHintLines(context, l10n, item.roomHints!),
          ],
          if (showDeadlineOrForwardsRow) ...[
            SizedBox(height: tt.rowGap),
            InboxCardForwardsFold(
              provenance: item.provenance,
              deadlineEndAt: beacon.endAt,
            ),
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
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _roomHintLines(
    BuildContext context,
    L10n l10n,
    InboxRoomCardHints h,
  ) {
    final theme = Theme.of(context);
    final tt = context.tt;
    final out = <Widget>[];
    if (h.isRoomMember) {
      out.add(
        Text(
          l10n.inboxCardRoomUnread(h.roomUnreadCount),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.secondary,
          ),
        ),
      );
      if (h.openBlockerTitle.isNotEmpty ||
          (h.openBlocker?.title.isNotEmpty ?? false)) {
        final title = h.openBlocker?.title ?? h.openBlockerTitle;
        out.add(
          Padding(
            padding: EdgeInsets.only(top: tt.tightGap),
            child: Text(
              l10n.inboxCardOpenBlocker(title),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.tertiary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      }
      if (h.currentLineSnippet.isNotEmpty) {
        out.add(
          Padding(
            padding: EdgeInsets.only(top: tt.tightGap),
            child: Text(
              l10n.inboxCardRoomCurrentLine(h.currentLineSnippet),
              style: theme.textTheme.bodySmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      }
      if (h.myNextMove.isNotEmpty) {
        out.add(
          Padding(
            padding: EdgeInsets.only(top: tt.tightGap),
            child: Text(
              l10n.inboxCardRoomNextMove(h.myNextMove),
              style: theme.textTheme.bodySmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      }
      if (h.lastRoomMeaningfulChange.isNotEmpty) {
        out.add(
          Padding(
            padding: EdgeInsets.only(top: tt.tightGap),
            child: Text(
              l10n.inboxCardRoomLastChange(h.lastRoomMeaningfulChange),
              style: theme.textTheme.bodySmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      }
    }
    return out;
  }
}
