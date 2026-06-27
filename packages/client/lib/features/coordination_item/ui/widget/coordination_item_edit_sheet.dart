import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/features/coordination_item/domain/use_case/coordination_item_case.dart';
import 'package:tentura/ui/l10n/l10n.dart';

String _editSheetTitle(L10n l10n, CoordinationItem item) => switch (item.kind) {
  CoordinationItemKind.blocker => l10n.coordinationBlockerCardLabel,
  CoordinationItemKind.ask => l10n.coordinationAskCardLabel,
  CoordinationItemKind.promise => l10n.coordinationPromiseCardLabel,
  CoordinationItemKind.plan =>
    item.isPlanStep
        ? l10n.coordinationPlanStepCardLabel
        : l10n.coordinationPlanCardLabel,
  CoordinationItemKind.resolution => l10n.coordinationResolutionCardLabel,
};

/// In-place edit for a published coordination item (open or accepted).
Future<void> showCoordinationItemEditSheet(
  BuildContext context, {
  required CoordinationItem item,
  VoidCallback? onSaved,
}) async {
  final l10n = L10n.of(context)!;
  final coordinationCase = GetIt.I<CoordinationItemCase>();
  final ok = await showTenturaAdaptiveSheet<bool>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => _CoordinationItemEditSheetBody(
      item: item,
      l10n: l10n,
      coordinationCase: coordinationCase,
    ),
  );
  if (ok == true && context.mounted) {
    onSaved?.call();
  }
}

class _CoordinationItemEditSheetBody extends StatefulWidget {
  const _CoordinationItemEditSheetBody({
    required this.item,
    required this.l10n,
    required this.coordinationCase,
  });

  final CoordinationItem item;
  final L10n l10n;
  final CoordinationItemCase coordinationCase;

  @override
  State<_CoordinationItemEditSheetBody> createState() =>
      _CoordinationItemEditSheetBodyState();
}

class _CoordinationItemEditSheetBodyState
    extends State<_CoordinationItemEditSheetBody> {
  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;
  var _submitting = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.item.title);
    _bodyController = TextEditingController(text: widget.item.body);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final canSubmit = _titleController.text.trim().isNotEmpty && !_submitting;
    return Padding(
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
            _editSheetTitle(widget.l10n, widget.item),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          SizedBox(height: tt.rowGap),
          TextField(
            controller: _titleController,
            onChanged: (_) => setState(() {}),
            maxLines: 2,
            minLines: 1,
            textInputAction: TextInputAction.next,
            enabled: !_submitting,
            autofocus: true,
          ),
          SizedBox(height: tt.rowGap),
          TextField(
            controller: _bodyController,
            onChanged: (_) => setState(() {}),
            maxLines: 6,
            minLines: 3,
            enabled: !_submitting,
          ),
          SizedBox(height: tt.sectionGap),
          FilledButton(
            onPressed: !canSubmit
                ? null
                : () async {
                    setState(() => _submitting = true);
                    try {
                      await widget.coordinationCase.updateItem(
                        itemId: widget.item.id,
                        title: _titleController.text.trim(),
                        body: _bodyController.text.trim(),
                      );
                      if (context.mounted) {
                        Navigator.of(context).pop(true);
                      }
                    } on Object catch (_) {
                      if (context.mounted) {
                        setState(() => _submitting = false);
                      }
                    }
                  },
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
    );
  }
}
