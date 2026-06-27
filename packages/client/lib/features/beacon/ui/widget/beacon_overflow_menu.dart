import 'dart:async';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/ui/l10n/l10n.dart';

Widget _beaconOverflowMenuRow(BuildContext context, IconData icon, String label) {
  final scheme = Theme.of(context).colorScheme;
  return Row(
    children: [
      Icon(icon, size: 22, color: scheme.onSurface),
      const SizedBox(width: 12),
      Expanded(child: Text(label)),
    ],
  );
}

/// Canonical overflow for beacon contexts (vertical more icon); items shown
/// when each callback is non-null (fixed order).
class BeaconOverflowMenu extends StatelessWidget {
  const BeaconOverflowMenu({
    required this.beacon,
    super.key,
    /// Overrides default edit-beacon label for the edit row (e.g. draft).
    this.editActionLabel,
    this.onOpenBeacon,
    this.onShare,
    this.onCloseBeacon,
    this.onCancelBeacon,
    this.onEdit,
    this.onCreateFrom,
    this.onCreatePromise,
    this.onCreatePoll,
    this.onUpdatePlan,
    this.onOfferHelp,
    this.onWithdraw,
    this.onForward,
    this.onForwardsGraph,
    this.onDraftReview,
    this.onWatch,
    this.onStopWatching,
    this.onCantHelp,
    this.onMoveToInbox,
    this.onDelete,
    this.onComplaint,
  });

  final Beacon beacon;

  final String? editActionLabel;

  /// Inbox / list: open detail (optional).
  final VoidCallback? onOpenBeacon;

  final VoidCallback? onShare;
  final Future<void> Function()? onCloseBeacon;
  final Future<void> Function()? onCancelBeacon;
  final VoidCallback? onEdit;
  final Future<void> Function()? onCreateFrom;
  final VoidCallback? onCreatePromise;
  final VoidCallback? onCreatePoll;
  final VoidCallback? onUpdatePlan;
  final Future<void> Function()? onOfferHelp;
  final Future<void> Function()? onWithdraw;
  final VoidCallback? onForward;
  final VoidCallback? onForwardsGraph;
  final VoidCallback? onDraftReview;
  final VoidCallback? onWatch;
  final VoidCallback? onStopWatching;
  final Future<void> Function()? onCantHelp;
  final VoidCallback? onMoveToInbox;
  final Future<void> Function()? onDelete;
  final VoidCallback? onComplaint;

  static Future<void> _deferPopupAction(
    BuildContext context,
    Future<void> Function()? action,
  ) async {
    await Future<void>.delayed(Duration.zero);
    if (!context.mounted || action == null) return;
    await action();
  }

  static void _deferSync(BuildContext context, VoidCallback? action) {
    unawaited(
      Future<void>.delayed(Duration.zero).then((_) {
        if (context.mounted) action?.call();
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final entries = <PopupMenuEntry<String>>[];

    void add(String value, IconData icon, String label) {
      entries.add(
        PopupMenuItem<String>(
          value: value,
          child: _beaconOverflowMenuRow(context, icon, label),
        ),
      );
    }

    if (onOpenBeacon != null) {
      add('open_beacon', Icons.open_in_new, l10n.openBeacon);
    }
    if (onShare != null) {
      add('share', Icons.qr_code, l10n.shareLink);
    }
    if (onCloseBeacon != null && beacon.status == BeaconStatus.open) {
      add(
        'close_beacon',
        Icons.lock_outline,
        l10n.closeBeacon,
      );
    }
    if (onCancelBeacon != null && beacon.status == BeaconStatus.open) {
      add(
        'cancel_beacon',
        Icons.cancel_outlined,
        l10n.cancelBeacon,
      );
    }
    if (onEdit != null) {
      add('edit', Icons.edit_outlined, editActionLabel ?? l10n.editBeacon);
    }
    if (onCreateFrom != null) {
      add(
        'create_from',
        Icons.content_copy_outlined,
        l10n.beaconCreateFromAction,
      );
    }
    if (onCreatePromise != null) {
      add(
        'create_promise',
        Icons.front_hand_outlined,
        l10n.coordinationCreatePromiseAction,
      );
    }
    if (onCreatePoll != null) {
      add(
        'create_poll',
        Icons.poll_outlined,
        l10n.beaconRoomCreatePoll,
      );
    }
    if (onUpdatePlan != null) {
      add(
        'update_plan',
        Icons.edit_note_outlined,
        l10n.beaconRoomActionUpdatePlan,
      );
    }
    if (onOfferHelp != null) {
      final useOfferHelpAnyway =
          beacon.status ==
          BeaconStatus.enoughHelp;
      add(
        'offerHelp',
        Icons.handshake,
        useOfferHelpAnyway ? l10n.labelOfferHelpAnyway : l10n.labelOfferHelp,
      );
    }
    if (onWithdraw != null) {
      add(
        'withdraw',
        Icons.remove_circle_outline,
        l10n.dialogWithdrawHelpOfferTitle,
      );
    }
    if (onForward != null && beacon.allowsForward) {
      add('forward', Icons.send, l10n.labelForward);
    }
    if (onForwardsGraph != null) {
      add(
        'forwards_graph',
        TenturaIcons.graph,
        l10n.forwardsGraphMenuTitle,
      );
    }
    if (onDraftReview != null) {
      add(
        'draft_review',
        Icons.rate_review_outlined,
        l10n.evaluationBannerDraftReview,
      );
    }
    if (onWatch != null) {
      add('watch', Icons.visibility_outlined, l10n.actionWatch);
    }
    if (onStopWatching != null) {
      add(
        'stop_watch',
        Icons.visibility_off_outlined,
        l10n.actionStopWatching,
      );
    }
    if (onCantHelp != null) {
      add('cant_help', Icons.close, l10n.actionCantHelp);
    }
    if (onMoveToInbox != null) {
      add(
        'move_inbox',
        Icons.inbox_outlined,
        l10n.actionMoveToInbox,
      );
    }

    final hasTail = onDelete != null || onComplaint != null;
    if (hasTail && entries.isNotEmpty) {
      entries.add(const PopupMenuDivider());
    }
    if (onDelete != null) {
      add('delete', Icons.delete_outline, l10n.deleteBeacon);
    }
    if (onComplaint != null) {
      add('complaint', Icons.flag_outlined, l10n.buttonComplaint);
    }

    if (entries.isEmpty) {
      return const SizedBox.shrink();
    }

    final tt = context.tt;
    final hitSize = tt.buttonHeight < kMinInteractiveDimension
        ? kMinInteractiveDimension
        : tt.buttonHeight;

    return SizedBox(
      width: hitSize,
      height: hitSize,
      child: PopupMenuButton<String>(
        tooltip: l10n.beaconHudOverflowMore,
        padding: EdgeInsets.zero,
        constraints: BoxConstraints(
          minWidth: hitSize,
          minHeight: hitSize,
        ),
        iconSize: tt.iconSize,
        itemBuilder: (_) => entries,
        onSelected: (value) => switch (value) {
          'open_beacon' => onOpenBeacon?.call(),
          'share' => onShare?.call(),
          'close_beacon' => unawaited(
            _deferPopupAction(context, onCloseBeacon),
          ),
          'cancel_beacon' => unawaited(
            _deferPopupAction(context, onCancelBeacon),
          ),
          'edit' => onEdit?.call(),
          'create_from' => unawaited(
            _deferPopupAction(context, onCreateFrom),
          ),
          'create_promise' => _deferSync(context, onCreatePromise),
          'create_poll' => _deferSync(context, onCreatePoll),
          'update_plan' => _deferSync(context, onUpdatePlan),
          'offerHelp' => unawaited(_deferPopupAction(context, onOfferHelp)),
          'withdraw' => unawaited(_deferPopupAction(context, onWithdraw)),
          'forward' => onForward?.call(),
          'forwards_graph' => onForwardsGraph?.call(),
          'draft_review' => onDraftReview?.call(),
          'watch' => onWatch?.call(),
          'stop_watch' => onStopWatching?.call(),
          'cant_help' => unawaited(_deferPopupAction(context, onCantHelp)),
          'move_inbox' => onMoveToInbox?.call(),
          'delete' => unawaited(_deferPopupAction(context, onDelete)),
          'complaint' => _deferSync(context, onComplaint),
          _ => null,
        },
        icon: Icon(Icons.more_vert, size: tt.iconSize),
      ),
    );
  }
}
