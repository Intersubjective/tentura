import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/coordination_status.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'package:tentura/features/beacon/ui/widget/coordination_ui.dart';

typedef CoordinationSignalSheetSave = Future<void> Function({
  required int responseTypeSmallint,
  required bool inviteToRoom,
  required bool removeFromRoom,
});

bool _defaultInviteForCoordination(CoordinationResponseType t) =>
    t == CoordinationResponseType.useful ||
    t == CoordinationResponseType.needCoordination;

/// Author: set per-commit coordination response + Room access (compact sheet).
Future<void> showCoordinationResponseBottomSheet({
  required BuildContext context,
  required String commitUserTitle,
  required CoordinationResponseType? initialResponse,
  required bool commitUserAdmittedToRoom,
  required CoordinationSignalSheetSave onSave,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(ctx).bottom,
      ),
      child: _CoordinationSignalSheet(
        commitUserTitle: commitUserTitle,
        initialResponse: initialResponse,
        commitUserAdmittedToRoom: commitUserAdmittedToRoom,
        onSave: onSave,
      ),
    ),
  );
}

class _CoordinationSignalSheet extends StatefulWidget {
  const _CoordinationSignalSheet({
    required this.commitUserTitle,
    required this.initialResponse,
    required this.commitUserAdmittedToRoom,
    required this.onSave,
  });

  final String commitUserTitle;
  final CoordinationResponseType? initialResponse;
  final bool commitUserAdmittedToRoom;
  final CoordinationSignalSheetSave onSave;

  @override
  State<_CoordinationSignalSheet> createState() =>
      _CoordinationSignalSheetState();
}

class _CoordinationSignalSheetState extends State<_CoordinationSignalSheet> {
  late CoordinationResponseType _selected =
      widget.initialResponse ?? CoordinationResponseType.useful;

  late bool _inviteToRoom = widget.commitUserAdmittedToRoom
      ? false
      : _defaultInviteForCoordination(_selected);

  bool _inviteTouched = false;

  bool _pendingRemoveFromRoom = false;

  Future<void> _onSavePressed() async {
    try {
      await widget.onSave(
        responseTypeSmallint: _selected.smallintValue,
        inviteToRoom:
            widget.commitUserAdmittedToRoom ? false : _inviteToRoom,
        removeFromRoom:
            widget.commitUserAdmittedToRoom && _pendingRemoveFromRoom,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (_) {
      // BeaconViewCubit emits StateHasError; keep sheet open.
    }
  }

  void _onResponseSelected(CoordinationResponseType value) {
    setState(() {
      _selected = value;
      if (!_inviteTouched && !widget.commitUserAdmittedToRoom) {
        _inviteToRoom = _defaultInviteForCoordination(value);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final scheme = Theme.of(context).colorScheme;
    final maxH = MediaQuery.sizeOf(context).height * 0.52;

    return SafeArea(
      child: SizedBox(
        height: maxH,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(tt.screenHPadding, 8, tt.screenHPadding, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.commitUserTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l10n.labelSetCoordinationResponse,
                    style: TenturaText.bodySmall(tt.textMuted),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: scheme.outlineVariant),
            Expanded(
              child: ListView(
                padding: EdgeInsets.symmetric(horizontal: tt.screenHPadding),
                children: [
                  for (final t in CoordinationResponseType.values) ...[
                    if (t != CoordinationResponseType.values.first)
                      SizedBox(height: tt.rowGap * 0.25),
                    SizedBox(
                      height: 46,
                      child: InkWell(
                        onTap: () => _onResponseSelected(t),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 40,
                              child: Radio<CoordinationResponseType>(
                                value: t,
                                groupValue: _selected,
                                onChanged: (v) {
                                  if (v != null) _onResponseSelected(v);
                                },
                              ),
                            ),
                            Expanded(
                              child: Text(
                                coordinationResponseLabel(l10n, t) ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  SizedBox(height: tt.rowGap),
                  Divider(height: 1, color: scheme.outlineVariant),
                  SizedBox(height: tt.rowGap * 0.5),
                  if (!widget.commitUserAdmittedToRoom)
                    SizedBox(
                      height: 46,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              l10n.coordinationInviteToRoomRow,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                          Switch.adaptive(
                            value: _inviteToRoom,
                            onChanged: (v) => setState(() {
                              _inviteTouched = true;
                              _inviteToRoom = v;
                            }),
                          ),
                        ],
                      ),
                    )
                  else
                    SizedBox(
                      height: 46,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              l10n.coordinationRemoveFromRoom,
                              style: TenturaText.body(
                                _pendingRemoveFromRoom
                                    ? tt.danger
                                    : tt.textMuted,
                              ),
                            ),
                          ),
                          Theme(
                            data: Theme.of(context).copyWith(
                              checkboxTheme: CheckboxThemeData(
                                fillColor:
                                    WidgetStateProperty.resolveWith((states) {
                                  if (states.contains(WidgetState.selected)) {
                                    return tt.danger;
                                  }
                                  return scheme.surfaceContainerHighest;
                                }),
                              ),
                            ),
                            child: Checkbox.adaptive(
                              value: _pendingRemoveFromRoom,
                              onChanged: (v) => setState(() {
                                _pendingRemoveFromRoom = v ?? false;
                              }),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            Divider(height: 1, color: scheme.outlineVariant),
            Padding(
              padding: EdgeInsets.fromLTRB(
                tt.screenHPadding,
                8,
                tt.screenHPadding,
                8,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(l10n.buttonCancel),
                    ),
                  ),
                  SizedBox(width: tt.rowGap),
                  Expanded(
                    child: FilledButton(
                      onPressed: _onSavePressed,
                      child: Text(l10n.buttonSave),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Author: override beacon-level coordination status (manual).
Future<void> showBeaconCoordinationStatusBottomSheet({
  required BuildContext context,
  required void Function(int statusSmallint) onPick,
}) async {
  final l10n = L10n.of(context)!;
  final options = <(int, String)>[
    (
      BeaconCoordinationStatus.commitmentsWaitingForReview.smallintValue,
      l10n.coordinationWaitingForReview,
    ),
    (
      BeaconCoordinationStatus.moreOrDifferentHelpNeeded.smallintValue,
      l10n.coordinationMoreHelpNeeded,
    ),
    (
      BeaconCoordinationStatus.enoughHelpCommitted.smallintValue,
      l10n.coordinationEnoughHelp,
    ),
  ];
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              l10n.coordinationSetOverallStatus,
              style: Theme.of(ctx).textTheme.titleSmall,
            ),
          ),
          Flexible(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                for (final o in options)
                  ListTile(
                    title: Text(o.$2),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      onPick(o.$1);
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
