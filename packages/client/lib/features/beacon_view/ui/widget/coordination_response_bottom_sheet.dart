import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'package:tentura/features/beacon/ui/widget/coordination_ui.dart';

typedef CoordinationSignalSheetSave =
    Future<void> Function({
      required int responseTypeSmallint,
      required bool inviteToRoom,
      required bool removeFromRoom,
    });

bool _defaultInviteForCoordination(CoordinationResponseType t) =>
    t == CoordinationResponseType.useful ||
    t == CoordinationResponseType.needCoordination;

/// Author: set per-help-offer coordination response + Room access (compact sheet).
Future<void> showCoordinationResponseBottomSheet({
  required BuildContext context,
  required String offerUserTitle,
  required CoordinationResponseType? initialResponse,
  required bool offerUserAdmittedToRoom,
  required CoordinationSignalSheetSave onSave,
}) async {
  await showTenturaAdaptiveSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(ctx).bottom,
      ),
      child: _CoordinationSignalSheet(
        offerUserTitle: offerUserTitle,
        initialResponse: initialResponse,
        offerUserAdmittedToRoom: offerUserAdmittedToRoom,
        onSave: onSave,
      ),
    ),
  );
}

class _CoordinationSignalSheet extends StatefulWidget {
  const _CoordinationSignalSheet({
    required this.offerUserTitle,
    required this.initialResponse,
    required this.offerUserAdmittedToRoom,
    required this.onSave,
  });

  final String offerUserTitle;
  final CoordinationResponseType? initialResponse;
  final bool offerUserAdmittedToRoom;
  final CoordinationSignalSheetSave onSave;

  @override
  State<_CoordinationSignalSheet> createState() =>
      _CoordinationSignalSheetState();
}

class _CoordinationSignalSheetState extends State<_CoordinationSignalSheet> {
  late CoordinationResponseType _selected =
      widget.initialResponse ?? CoordinationResponseType.useful;

  late bool _admitToRoom =
      widget.offerUserAdmittedToRoom ||
      _defaultInviteForCoordination(_selected);

  bool _admitTouched = false;

  Future<void> _onSavePressed() async {
    try {
      await widget.onSave(
        responseTypeSmallint: _selected.smallintValue,
        inviteToRoom: !widget.offerUserAdmittedToRoom && _admitToRoom,
        removeFromRoom: widget.offerUserAdmittedToRoom && !_admitToRoom,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (_) {
      // BeaconViewCubit emits ShowError; keep sheet open.
    }
  }

  void _onResponseSelected(CoordinationResponseType value) {
    setState(() {
      _selected = value;
      if (!_admitTouched && !widget.offerUserAdmittedToRoom) {
        _admitToRoom = _defaultInviteForCoordination(value);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final scheme = Theme.of(context).colorScheme;
    // Tall enough for response options + fixed room row + actions on typical phones.
    final maxH = MediaQuery.sizeOf(context).height * 0.72;

    return SafeArea(
      child: SizedBox(
        height: maxH,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                tt.screenHPadding,
                8,
                tt.screenHPadding,
                4,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.offerUserTitle,
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
              child: RadioGroup<CoordinationResponseType>(
                groupValue: _selected,
                onChanged: (v) {
                  if (v != null) _onResponseSelected(v);
                },
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
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: tt.screenHPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(height: tt.rowGap * 0.5),
                  Divider(height: 1, color: scheme.outlineVariant),
                  SizedBox(height: tt.rowGap * 0.5),
                  MergeSemantics(
                    child: SizedBox(
                      height: 48,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              l10n.coordinationInviteToRoomRow,
                              style: TenturaText.body(
                                _admitToRoom
                                    ? tt.good
                                    : widget.offerUserAdmittedToRoom
                                    ? tt.danger
                                    : tt.textMuted,
                              ),
                            ),
                          ),
                          Theme(
                            data: Theme.of(context).copyWith(
                              checkboxTheme: CheckboxThemeData(
                                fillColor: WidgetStateProperty.resolveWith((
                                  states,
                                ) {
                                  if (states.contains(WidgetState.selected)) {
                                    return tt.good;
                                  }
                                  return scheme.surfaceContainerHighest;
                                }),
                              ),
                            ),
                            child: Checkbox.adaptive(
                              value: _admitToRoom,
                              onChanged: (v) => setState(() {
                                _admitTouched = true;
                                _admitToRoom = v ?? false;
                              }),
                            ),
                          ),
                        ],
                      ),
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
