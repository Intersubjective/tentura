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
    }
    return;
  }
  if (!context.mounted) {
    return;
  }
  showUndoSnackBar(
    context,
    text: l10n.constellationHiddenFromFieldSnack,
    onUndo: () => unawaited(
      _undoHide(
        context,
        targetKind: targetKind,
        beaconId: beaconId,
        snapshot: snapshot,
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
    if (context.mounted) {
      cubit.cancelHideFromField(snapshot, beaconId: beaconId);
      cubit.noteHiddenByYouCountDelta(1);
      showSnackBar(context, text: l10n.errorGenericAction, isError: true);
    }
  }
}

/// Pin + Hide toolbar for pointer hover; secondary tap opens the same menu.
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

  @override
  State<ConstellationFieldBeaconMapChrome> createState() =>
      _ConstellationFieldBeaconMapChromeState();
}

class _ConstellationFieldBeaconMapChromeState
    extends State<ConstellationFieldBeaconMapChrome> {
  bool _hovered = false;
  bool _menuPinned = false;

  bool get _supportsHover {
    final platform = Theme.of(context).platform;
    return platform != TargetPlatform.android && platform != TargetPlatform.iOS;
  }

  bool get _showToolbar => _supportsHover && (_hovered || _menuPinned);

  void _openMenu(TapDownDetails details) {
    final l10n = L10n.of(context)!;
    final cubit = context.read<ConstellationCubit>();
    final target = ConstellationAnchorTarget.beacon(widget.beaconId);
    final anchored = cubit.isAnchored(target);
    unawaited(
      showMenu<void>(
        context: context,
        position: RelativeRect.fromLTRB(
          details.globalPosition.dx,
          details.globalPosition.dy,
          details.globalPosition.dx,
          details.globalPosition.dy,
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
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final cubit = context.read<ConstellationCubit>();
    final target = ConstellationAnchorTarget.beacon(widget.beaconId);
    final anchored = cubit.isAnchored(target);
    return TapRegion(
      onTapOutside: _menuPinned ? (_) => setState(() => _menuPinned = false) : null,
      child: MouseRegion(
        onEnter: _supportsHover ? (_) => setState(() => _hovered = true) : null,
        onExit: _supportsHover ? (_) => setState(() => _hovered = false) : null,
        child: GestureDetector(
          behavior: HitTestBehavior.deferToChild,
          onSecondaryTapDown: (details) {
            setState(() => _menuPinned = true);
            _openMenu(details);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_showToolbar)
                Padding(
                  padding: EdgeInsets.only(bottom: tt.tightGap),
                  child: Material(
                    elevation: 2,
                    borderRadius: BorderRadius.circular(tt.buttonRadius),
                    color: Theme.of(context).colorScheme.surface,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: tt.tightGap),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TenturaTextAction(
                            label: anchored
                                ? l10n.constellationUnpinTarget
                                : l10n.constellationPinTarget,
                            onPressed: () =>
                                unawaited(cubit.pinFromText(target: target)),
                            minInteractive: true,
                          ),
                          TenturaTextAction(
                            label: l10n.constellationHideFromField,
                            onPressed: () => unawaited(
                              _hideFromField(
                                context,
                                targetKind: widget.targetKind,
                                beaconId: widget.beaconId,
                              ),
                            ),
                            minInteractive: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              widget.child,
            ],
          ),
        ),
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
