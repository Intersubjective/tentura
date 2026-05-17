import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/features/coordination_item/domain/use_case/coordination_item_case.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

Future<void> showPreparedBlockerEditorSheet(
  BuildContext context, {
  required String beaconId,
  required VoidCallback onSaved,
  CoordinationItem? existing,
}) async {
  final l10n = L10n.of(context)!;
  final coordinationCase = GetIt.I<CoordinationItemCase>();
  final ok = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => _PreparedBlockerEditorSheetBody(
      beaconId: beaconId,
      coordinationCase: coordinationCase,
      existing: existing,
      l10n: l10n,
    ),
  );
  if (ok == true && context.mounted) {
    onSaved();
  }
}

class _PreparedBlockerEditorSheetBody extends StatefulWidget {
  const _PreparedBlockerEditorSheetBody({
    required this.beaconId,
    required this.coordinationCase,
    required this.existing,
    required this.l10n,
  });

  final String beaconId;
  final CoordinationItemCase coordinationCase;
  final CoordinationItem? existing;
  final L10n l10n;

  @override
  State<_PreparedBlockerEditorSheetBody> createState() =>
      _PreparedBlockerEditorSheetBodyState();
}

class _PreparedBlockerEditorSheetBodyState
    extends State<_PreparedBlockerEditorSheetBody> {
  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;
  var _submitting = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _titleController = TextEditingController(text: existing?.title ?? '');
    _bodyController = TextEditingController(text: existing?.body ?? '');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final canSubmit =
        _titleController.text.trim().isNotEmpty && !_submitting;
    final l10n = widget.l10n;
    final existing = widget.existing;
    return Padding(
      padding: EdgeInsets.only(
        left: kSpacingSmall,
        right: kSpacingSmall,
        top: kSpacingMedium,
        bottom: bottom + kSpacingMedium,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            existing == null
                ? l10n.beaconPreparedBlockerEditorTitleNew
                : l10n.beaconPreparedBlockerEditorTitleEdit,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: kSpacingSmall),
          TextField(
            controller: _titleController,
            onChanged: (_) => setState(() {}),
            maxLines: 2,
            minLines: 1,
            decoration: InputDecoration(
              labelText: l10n.labelTitle,
            ),
            textInputAction: TextInputAction.next,
            enabled: !_submitting,
          ),
          const SizedBox(height: kSpacingSmall),
          TextField(
            controller: _bodyController,
            onChanged: (_) => setState(() {}),
            maxLines: 4,
            minLines: 2,
            decoration: InputDecoration(
              labelText: l10n.labelBody,
            ),
            enabled: !_submitting,
          ),
          const SizedBox(height: kSpacingMedium),
          FilledButton(
            onPressed: !canSubmit
                ? null
                : () async {
                    setState(() => _submitting = true);
                    try {
                      if (existing == null) {
                        await widget.coordinationCase.createDraftBlocker(
                          beaconId: widget.beaconId,
                          title: _titleController.text.trim(),
                          body: _bodyController.text.trim(),
                        );
                      } else {
                        await widget.coordinationCase.updateDraftBlocker(
                          itemId: existing.id,
                          title: _titleController.text.trim(),
                          body: _bodyController.text.trim(),
                        );
                      }
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

Future<void> showPreparedBlockerPublishSheet(
  BuildContext context, {
  required CoordinationItem draft,
  required VoidCallback onSaved,
}) async {
  final l10n = L10n.of(context)!;
  final coordinationCase = GetIt.I<CoordinationItemCase>();

  var submitting = false;
  final ok = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setState) {
          final bottom = MediaQuery.viewInsetsOf(ctx).bottom;
          return Padding(
            padding: EdgeInsets.only(
              left: kSpacingSmall,
              right: kSpacingSmall,
              top: kSpacingMedium,
              bottom: bottom + kSpacingMedium,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.beaconPreparedBlockerPublishSheetTitle,
                  style: Theme.of(ctx).textTheme.titleMedium,
                ),
                const SizedBox(height: kSpacingSmall),
                Text(
                  draft.contentPreview,
                  style: Theme.of(ctx).textTheme.bodyMedium,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: kSpacingMedium),
                FilledButton(
                  onPressed: submitting
                      ? null
                      : () async {
                          setState(() => submitting = true);
                          try {
                            await coordinationCase.publishDraftBlocker(
                              itemId: draft.id,
                            );
                            if (ctx.mounted) {
                              Navigator.of(ctx).pop(true);
                            }
                          } on Object catch (_) {
                            if (ctx.mounted) {
                              setState(() => submitting = false);
                            }
                          }
                        },
                  child: submitting
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n.buttonPublish),
                ),
              ],
            ),
          );
        },
      );
    },
  );

  if (ok == true && context.mounted) {
    onSaved();
  }
}

Future<void> confirmDeletePreparedBlocker(
  BuildContext context, {
  required String itemId,
  required VoidCallback onDeleted,
}) async {
  final l10n = L10n.of(context)!;
  final coordinationCase = GetIt.I<CoordinationItemCase>();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.beaconPreparedBlockerDeleteConfirmTitle),
      content: Text(l10n.beaconPreparedBlockerDeleteConfirmBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(l10n.buttonDelete),
        ),
      ],
    ),
  );
  if (ok == true && context.mounted) {
    await coordinationCase.deleteDraftBlocker(itemId: itemId);
    onDeleted();
  }
}
