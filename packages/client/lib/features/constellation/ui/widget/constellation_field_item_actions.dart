import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/undo_snack_bar.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../../domain/constellation_field_patches.dart';
import '../../domain/entity/constellation_field_target_kind.dart';
import '../bloc/constellation_cubit.dart';
import 'constellation_anchor_controls.dart';

/// Pin and «Hide from Field» actions shared by preview sheets and list rows.
class ConstellationFieldItemFooterActions extends StatelessWidget {
  const ConstellationFieldItemFooterActions({
    required this.targetKind,
    required this.beaconId,
    super.key,
  });

  final ConstellationFieldTargetKind targetKind;
  final String beaconId;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: ConstellationAnchorTargetButton(
                target: ConstellationAnchorTarget.beacon(beaconId),
              ),
            ),
            SizedBox(width: tt.rowGap),
            Expanded(
              child: ConstellationFieldHideButton(
                targetKind: targetKind,
                beaconId: beaconId,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// «Hide from Field» control for sheets and toolbars.
class ConstellationFieldHideButton extends StatelessWidget {
  const ConstellationFieldHideButton({
    required this.targetKind,
    required this.beaconId,
    this.compact = false,
    super.key,
  });

  final ConstellationFieldTargetKind targetKind;
  final String beaconId;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    void onPressed() => unawaited(
      _hideFromField(
        context,
        targetKind: targetKind,
        beaconId: beaconId,
      ),
    );
    if (compact) {
      return Tooltip(
        message: l10n.constellationHideFromField,
        child: IconButton(
          key: TestIds.key(TestIds.constellationHideFromField),
          onPressed: onPressed,
          icon: const Icon(Icons.visibility_off_outlined),
        ),
      );
    }
    return OutlinedButton.icon(
      key: TestIds.key(TestIds.constellationHideFromField),
      onPressed: onPressed,
      icon: const Icon(Icons.visibility_off_outlined),
      label: Text(l10n.constellationHideFromField),
    );
  }
}

Future<void> _hideFromField(
  BuildContext context, {
  required ConstellationFieldTargetKind targetKind,
  required String beaconId,
}) async {
  final cubit = context.read<ConstellationCubit>();
  final l10n = L10n.of(context)!;
  final messenger =
      ScaffoldMessenger.maybeOf(context) ?? snackbarKey.currentState;
  final undoLabel = l10n.peopleTagsUndo;
  final hiddenSnackText = l10n.constellationHiddenFromFieldSnack;
  final snapshot = cubit.beginHideFromField(
    targetKind: targetKind,
    beaconId: beaconId,
  );
  if (snapshot == null) {
    return;
  }
  final hideCase = cubit.fieldHideCase;
  if (hideCase == null) {
    cubit.cancelHideFromField(snapshot, beaconId: beaconId);
    return;
  }
  try {
    await hideCase.hide(
      targetKind: targetKind.wireValue,
      targetId: beaconId,
    );
    cubit.noteHiddenByYouCountDelta(1);
  } on Object {
    if (context.mounted) {
      cubit.cancelHideFromField(snapshot, beaconId: beaconId);
      showSnackBar(context, text: l10n.errorGenericAction, isError: true);
    } else {
      cubit.cancelHideFromField(snapshot, beaconId: beaconId);
      showSnackBarOn(messenger, text: l10n.errorGenericAction, isError: true);
    }
    return;
  }
  showUndoSnackBar(
    context,
    messenger: messenger,
    undoActionLabel: undoLabel,
    text: hiddenSnackText,
    onUndo: () => unawaited(
      _undoHideForCubit(
        cubit,
        targetKind: targetKind,
        beaconId: beaconId,
        snapshot: snapshot,
        errorText: l10n.errorGenericAction,
        messenger: messenger,
      ),
    ),
  );
}

Future<void> _undoHide(
  BuildContext context, {
  required ConstellationFieldTargetKind targetKind,
  required String beaconId,
  required ConstellationFieldHideSnapshot snapshot,
}) async {
  final cubit = context.read<ConstellationCubit>();
  final l10n = L10n.of(context)!;
  await _undoHideForCubit(
    cubit,
    targetKind: targetKind,
    beaconId: beaconId,
    snapshot: snapshot,
    errorText: l10n.errorGenericAction,
    messenger: ScaffoldMessenger.maybeOf(context) ?? snackbarKey.currentState,
  );
}

Future<void> _undoHideForCubit(
  ConstellationCubit cubit, {
  required ConstellationFieldTargetKind targetKind,
  required String beaconId,
  required ConstellationFieldHideSnapshot snapshot,
  required String errorText,
  ScaffoldMessengerState? messenger,
}) async {
  cubit.restoreHideFromField(snapshot, beaconId: beaconId);
  cubit.noteHiddenByYouCountDelta(-1);
  final hideCase = cubit.fieldHideCase;
  if (hideCase == null) {
    return;
  }
  try {
    await hideCase.unhide(
      targetKind: targetKind.wireValue,
      targetId: beaconId,
    );
  } on Object {
    cubit.cancelHideFromField(snapshot, beaconId: beaconId);
    cubit.noteHiddenByYouCountDelta(1);
    showSnackBarOn(messenger, text: errorText, isError: true);
  }
}

/// Secondary tap opens Pin / Hide menu; actions also live on preview sheets
/// and list overflow (#255, #1154 — no hover toolbar on map nodes).
class ConstellationFieldBeaconMapChrome extends StatefulWidget {
  const ConstellationFieldBeaconMapChrome({
    required this.targetKind,
    required this.beaconId,
    required this.child,
    super.key,
  });

  final ConstellationFieldTargetKind targetKind;
  final String beaconId;
  final Widget child;

  /// Whether a map secondary-tap menu recently claimed this pointer (#255).
  static bool suppressesPrimaryTap() =>
      _ConstellationFieldBeaconMapChromeState.suppressesPrimaryTap();

  @override
  State<ConstellationFieldBeaconMapChrome> createState() =>
      _ConstellationFieldBeaconMapChromeState();
}

class _ConstellationFieldBeaconMapChromeState
    extends State<ConstellationFieldBeaconMapChrome> {
  bool _menuPinned = false;

  /// Web may fire a primary activation right after secondary tap; ignore it.
  static const _suppressPrimaryTapMs = 400;
  static int _suppressPrimaryTapUntilMs = 0;

  @visibleForTesting
  static bool suppressesPrimaryTap() =>
      DateTime.now().millisecondsSinceEpoch < _suppressPrimaryTapUntilMs;

  static void _suppressPrimaryTapBriefly() {
    _suppressPrimaryTapUntilMs =
        DateTime.now().millisecondsSinceEpoch + _suppressPrimaryTapMs;
  }

  void _openMenuAt(Offset globalPosition) {
    final l10n = L10n.of(context)!;
    final cubit = context.read<ConstellationCubit>();
    final target = ConstellationAnchorTarget.beacon(widget.beaconId);
    final anchored = cubit.isAnchored(target);
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final local = overlay.globalToLocal(globalPosition);
    unawaited(
      showMenu<void>(
        context: context,
        position: RelativeRect.fromRect(
          Rect.fromLTWH(local.dx, local.dy, 0, 0),
          Offset.zero & overlay.size,
        ),
        items: [
          PopupMenuItem<void>(
            onTap: () => unawaited(cubit.pinFromText(target: target)),
            child: Text(
              anchored
                  ? l10n.constellationUnpinTarget
                  : l10n.constellationPinTarget,
            ),
          ),
          PopupMenuItem<void>(
            onTap: () => unawaited(
              _hideFromField(
                context,
                targetKind: widget.targetKind,
                beaconId: widget.beaconId,
              ),
            ),
            child: Text(l10n.constellationHideFromField),
          ),
        ],
      ).whenComplete(() {
        if (mounted) {
          setState(() => _menuPinned = false);
        }
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return TapRegion(
      onTapOutside: _menuPinned
          ? (_) => setState(() => _menuPinned = false)
          : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTapUp: (details) {
          _suppressPrimaryTapBriefly();
          setState(() => _menuPinned = true);
          _openMenuAt(details.globalPosition);
        },
        child: widget.child,
      ),
    );
  }
}

/// List row overflow with Pin and Hide (#255).
class ConstellationFieldItemOverflowMenu extends StatelessWidget {
  const ConstellationFieldItemOverflowMenu({
    required this.targetKind,
    required this.beaconId,
    super.key,
  });

  final ConstellationFieldTargetKind targetKind;
  final String beaconId;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final cubit = context.read<ConstellationCubit>();
    final target = ConstellationAnchorTarget.beacon(beaconId);
    return PopupMenuButton<int>(
      key: Key('constellation.field_item.menu.$beaconId'),
      icon: const Icon(Icons.more_vert),
      tooltip: l10n.beaconHudOverflowMore,
      onSelected: (index) {
        switch (index) {
          case 0:
            unawaited(cubit.pinFromText(target: target));
          case 1:
            unawaited(
              _hideFromField(
                context,
                targetKind: targetKind,
                beaconId: beaconId,
              ),
            );
        }
      },
      itemBuilder: (context) {
        final anchored = cubit.isAnchored(target);
        return [
          PopupMenuItem(
            value: 0,
            child: Text(
              anchored
                  ? l10n.constellationUnpinTarget
                  : l10n.constellationPinTarget,
            ),
          ),
          PopupMenuItem(
            value: 1,
            child: Text(l10n.constellationHideFromField),
          ),
        ];
      },
    );
  }
}
