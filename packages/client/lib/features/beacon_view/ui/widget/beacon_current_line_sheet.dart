import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/features/coordination_item/domain/use_case/coordination_item_case.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura_root/domain/entity/localizable.dart';

/// Sets the beacon room [current line] (synced via coordination updatePlan).
Future<void> showBeaconCurrentLineSheet(
  BuildContext context, {
  required String beaconId,
  required String initialText,
  void Function(String savedLine)? onSaved,
}) async {
  final l10n = L10n.of(context)!;
  final coordinationCase = GetIt.I<CoordinationItemCase>();
  final savedLine = await showTenturaAdaptiveSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useRootNavigator: true,
    enableDrag: false,
    builder: (ctx) => _BeaconCurrentLineSheetBody(
      l10n: l10n,
      beaconId: beaconId,
      initialText: initialText,
      coordinationCase: coordinationCase,
    ),
  );
  if (savedLine != null && savedLine.isNotEmpty && context.mounted) {
    onSaved?.call(savedLine);
  }
}

class _BeaconCurrentLineSheetBody extends StatefulWidget {
  const _BeaconCurrentLineSheetBody({
    required this.l10n,
    required this.beaconId,
    required this.initialText,
    required this.coordinationCase,
  });

  final L10n l10n;
  final String beaconId;
  final String initialText;
  final CoordinationItemCase coordinationCase;

  @override
  State<_BeaconCurrentLineSheetBody> createState() =>
      _BeaconCurrentLineSheetBodyState();
}

class _BeaconCurrentLineSheetBodyState extends State<_BeaconCurrentLineSheetBody> {
  late final TextEditingController _controller;
  var _submitting = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _controller.text.trim().isNotEmpty && !_submitting;

  bool get _isDirty =>
      _controller.text.trim() != widget.initialText.trim();

  Future<void> _save() async {
    if (!_canSubmit) return;
    setState(() => _submitting = true);
    try {
      final line = _controller.text.trim();
      await widget.coordinationCase.updatePlan(
        beaconId: widget.beaconId,
        title: line,
      );
      if (mounted) {
        Navigator.of(context).pop(line);
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        final locale = L10n.of(context)?.localeName;
        showSnackBar(
          context,
          isError: true,
          text: switch (e) {
            final Localizable l => l.toL10n(locale),
            _ => e.toString(),
          },
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final tt = context.tt;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return TenturaSheetDismissGuard(
      isDirty: _isDirty,
      useRootNavigator: true,
      child: Padding(
      padding: EdgeInsets.only(
        left: tt.screenHPadding,
        right: tt.screenHPadding,
        top: tt.sectionGap,
        bottom: bottom + tt.sectionGap,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.beaconHudEditCurrentLineTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          SizedBox(height: tt.rowGap),
          TextField(
            controller: _controller,
            decoration: InputDecoration(
              hintText: l10n.beaconRoomStripCurrentLineLabel,
            ),
            onChanged: (_) => setState(() {}),
            maxLength: kBeaconRoomCurrentLineMaxLength,
            maxLines: 2,
            minLines: 1,
            textInputAction: TextInputAction.done,
            enabled: !_submitting,
            autofocus: true,
          ),
          SizedBox(height: tt.sectionGap),
          FilledButton(
            onPressed: !_canSubmit ? null : _save,
            child: _submitting
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(MaterialLocalizations.of(context).saveButtonLabel),
          ),
        ],
      ),
    ),
    );
  }
}
