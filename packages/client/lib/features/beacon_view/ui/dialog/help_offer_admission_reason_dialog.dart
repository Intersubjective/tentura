import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

class HelpOfferAdmissionReasonDialog extends StatefulWidget {
  const HelpOfferAdmissionReasonDialog({
    required this.title,
    required this.hintText,
    this.explanatoryNote,
    this.submitLabel,
    this.destructive = false,
    super.key,
  });

  static Future<String?> show(
    BuildContext context, {
    required String title,
    required String hintText,
    String? explanatoryNote,
    String? submitLabel,
    bool destructive = false,
  }) => showTenturaAdaptiveSheet<String>(
    context: context,
    useRootNavigator: true,
    enableDrag: false,
    builder: (_) => HelpOfferAdmissionReasonDialog(
      title: title,
      hintText: hintText,
      explanatoryNote: explanatoryNote,
      submitLabel: submitLabel,
      destructive: destructive,
    ),
  );

  final String title;
  final String hintText;
  final String? explanatoryNote;

  /// Verb for the primary button ("Decline"); defaults to OK.
  final String? submitLabel;

  /// Paints the primary button in the error role.
  final bool destructive;

  @override
  State<HelpOfferAdmissionReasonDialog> createState() =>
      _HelpOfferAdmissionReasonDialogState();
}

class _HelpOfferAdmissionReasonDialogState
    extends State<HelpOfferAdmissionReasonDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isDirty => _controller.text.trim().isNotEmpty;
  bool get _canSubmit => _controller.text.trim().isNotEmpty;

  Future<void> _requestClose() => TenturaSheetDismissGuard.requestClose(
    context,
    isDirty: _isDirty,
    useRootNavigator: true,
  );

  void _submit() {
    if (!_canSubmit) return;
    Navigator.of(context).pop<String>(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final tt = context.tt;
    return TenturaSheetDismissGuard(
      isDirty: _isDirty,
      useRootNavigator: true,
      child: Padding(
        padding: EdgeInsets.only(
          left: tt.screenHPadding,
          right: tt.screenHPadding,
          top: tt.rowGap,
          bottom: MediaQuery.viewInsetsOf(context).bottom + tt.sectionGap,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.title,
              style: theme.textTheme.titleLarge,
            ),
            if (widget.explanatoryNote != null &&
                widget.explanatoryNote!.trim().isNotEmpty) ...[
              SizedBox(height: tt.tightGap),
              Text(
                widget.explanatoryNote!,
                style: TenturaText.bodySmall(theme.colorScheme.onSurfaceVariant),
              ),
            ],
            SizedBox(height: tt.sectionGap),
            TextField(
              key: TestIds.key(TestIds.admissionReasonInput),
              autofocus: true,
              controller: _controller,
              maxLines: 4,
              maxLength: 500,
              decoration: tenturaNoteInputDecoration(
                context,
                hintText: widget.hintText,
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submit(),
              onTapOutside: (_) =>
                  FocusManager.instance.primaryFocus?.unfocus(),
            ),
            SizedBox(height: tt.sectionGap),
            TenturaSheetActions(
              cancelLabel: l10n.buttonCancel,
              onCancel: _requestClose,
              primaryKey: TestIds.key(TestIds.admissionReasonSubmit),
              primaryLabel: widget.submitLabel ?? l10n.buttonOk,
              destructive: widget.destructive,
              onPrimary: _canSubmit ? _submit : null,
            ),
          ],
        ),
      ),
    );
  }
}
