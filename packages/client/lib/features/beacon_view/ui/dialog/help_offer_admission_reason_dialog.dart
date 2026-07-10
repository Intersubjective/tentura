import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

class HelpOfferAdmissionReasonDialog extends StatefulWidget {
  const HelpOfferAdmissionReasonDialog({
    required this.title,
    required this.hintText,
    super.key,
  });

  static Future<String?> show(
    BuildContext context, {
    required String title,
    required String hintText,
  }) => showTenturaAdaptiveSheet<String>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    enableDrag: false,
    builder: (_) => HelpOfferAdmissionReasonDialog(
      title: title,
      hintText: hintText,
    ),
  );

  final String title;
  final String hintText;

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
            TextButton(
              onPressed: _requestClose,
              child: Text(l10n.buttonCancel),
            ),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: TestIds.key(TestIds.admissionReasonSubmit),
                onPressed: _canSubmit ? _submit : null,
                child: Text(l10n.buttonOk),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
