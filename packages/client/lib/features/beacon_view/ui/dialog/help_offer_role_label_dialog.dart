import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

/// Single-line editor for [TimelineHelpOffer.roleLabel] / chat role under avatar.
class HelpOfferRoleLabelDialog extends StatefulWidget {
  const HelpOfferRoleLabelDialog({
    this.initialText = '',
    super.key,
  });

  static Future<String?> show(
    BuildContext context, {
    String initialText = '',
  }) => showTenturaAdaptiveSheet<String>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    enableDrag: false,
    builder: (_) => HelpOfferRoleLabelDialog(initialText: initialText),
  );

  final String initialText;

  @override
  State<HelpOfferRoleLabelDialog> createState() =>
      _HelpOfferRoleLabelDialogState();
}

class _HelpOfferRoleLabelDialogState extends State<HelpOfferRoleLabelDialog> {
  late final TextEditingController _controller;
  String? _errorText;

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

  bool get _isDirty => _controller.text != widget.initialText;

  Future<void> _requestClose() => TenturaSheetDismissGuard.requestClose(
    context,
    isDirty: _isDirty,
    useRootNavigator: true,
  );

  void _submit() {
    final trimmed = _controller.text.trim();
    if (trimmed.contains('\n') || trimmed.contains('\r')) {
      setState(() => _errorText = L10n.of(context)!.helpOfferRoleLabelTooLong);
      return;
    }
    if (trimmed.length > kMaxHelpOfferRoleLabelLength) {
      setState(() => _errorText = L10n.of(context)!.helpOfferRoleLabelTooLong);
      return;
    }
    Navigator.of(context).pop<String>(trimmed);
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
              l10n.helpOfferRoleLabelField,
              style: theme.textTheme.titleLarge,
            ),
            SizedBox(height: tt.sectionGap),
            TextField(
              key: TestIds.key(TestIds.helpOfferRoleLabelInput),
              autofocus: true,
              controller: _controller,
              maxLines: 1,
              maxLength: kMaxHelpOfferRoleLabelLength,
              inputFormatters: [
                FilteringTextInputFormatter.deny(RegExp(r'[\r\n]')),
              ],
              decoration: tenturaNoteInputDecoration(
                context,
                hintText: l10n.helpOfferRoleLabelPlaceholder,
              ).copyWith(errorText: _errorText),
              onChanged: (_) {
                if (_errorText != null) setState(() => _errorText = null);
              },
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
                key: TestIds.key(TestIds.helpOfferRoleLabelSubmit),
                onPressed: _submit,
                child: Text(l10n.buttonSave),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
