import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/coordination_status.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/tentura_icons.dart';

Widget _beaconOverflowMenuRow(IconData icon, String label) {
  return Row(
    children: [
      Icon(icon, size: 22),
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
    this.onGraph,
    this.onShare,
    this.onToggleLifecycle,
    this.onEdit,
    this.onCommit,
    this.onWithdraw,
    this.onForward,
    this.onViewForwards,
    this.onForwardsGraph,
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

  final VoidCallback? onGraph;
  final VoidCallback? onShare;
  final Future<void> Function()? onToggleLifecycle;
  final VoidCallback? onEdit;
  final Future<void> Function()? onCommit;
  final Future<void> Function()? onWithdraw;
  final VoidCallback? onForward;
  final VoidCallback? onViewForwards;
  final VoidCallback? onForwardsGraph;
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
          child: _beaconOverflowMenuRow(icon, label),
        ),
      );
    }

    if (onOpenBeacon != null) {
      add('open_beacon', Icons.open_in_new, l10n.openBeacon);
    }
    if (onGraph != null) {
      add('graph', TenturaIcons.graph, l10n.graphView);
    }
    if (onShare != null) {
      add('share', Icons.qr_code, l10n.shareLink);
    }
    if (onToggleLifecycle != null) {
      add(
        'toggle_lifecycle',
        beacon.isListed ? Icons.lock_outline : Icons.lock_open,
        beacon.isListed ? l10n.closeBeacon : l10n.openBeacon,
      );
    }
    if (onEdit != null) {
      add('edit', Icons.edit_outlined, editActionLabel ?? l10n.editBeacon);
    }
    if (onCommit != null) {
      final useCommitAnyway =
          beacon.coordinationStatus ==
          BeaconCoordinationStatus.enoughHelpCommitted;
      add(
        'commit',
        Icons.handshake,
        useCommitAnyway ? l10n.labelCommitAnyway : l10n.labelCommit,
      );
    }
    if (onWithdraw != null) {
      add(
        'withdraw',
        Icons.remove_circle_outline,
        l10n.dialogWithdrawTitle,
      );
    }
    if (onForward != null) {
      add('forward', Icons.send, l10n.labelForward);
    }
    if (onViewForwards != null) {
      add(
        'view_forwards',
        Icons.forward_to_inbox,
        l10n.overflowMenuSeeForwards,
      );
    }
    if (onForwardsGraph != null) {
      add(
        'forwards_graph',
        TenturaIcons.graph,
        l10n.forwardsGraphMenuTitle,
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

    return SizedBox(
      width: 32,
      height: 40,
      child: PopupMenuButton<String>(
        padding: EdgeInsets.zero,
        iconSize: 22,
        itemBuilder: (_) => entries,
        onSelected: (value) => switch (value) {
          'open_beacon' => onOpenBeacon?.call(),
          'graph' => onGraph?.call(),
          'share' => onShare?.call(),
          'toggle_lifecycle' => unawaited(
            _deferPopupAction(context, onToggleLifecycle),
          ),
          'edit' => onEdit?.call(),
          'commit' => unawaited(_deferPopupAction(context, onCommit)),
          'withdraw' => unawaited(_deferPopupAction(context, onWithdraw)),
          'forward' => onForward?.call(),
          'view_forwards' => onViewForwards?.call(),
          'forwards_graph' => onForwardsGraph?.call(),
          'watch' => onWatch?.call(),
          'stop_watch' => onStopWatching?.call(),
          'cant_help' => unawaited(_deferPopupAction(context, onCantHelp)),
          'move_inbox' => onMoveToInbox?.call(),
          'delete' => unawaited(_deferPopupAction(context, onDelete)),
          'complaint' => _deferSync(context, onComplaint),
          _ => null,
        },
        icon: const Icon(Icons.more_vert, size: 22),
      ),
    );
  }
}
