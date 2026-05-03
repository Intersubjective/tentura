import 'package:flutter/material.dart';

import 'package:tentura/domain/capability/capability_tag.dart';
import 'package:tentura/domain/entity/uncommit_reason.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Result of [CommitmentMessageDialog.show].
typedef CommitmentDialogOutcome = ({
  String message,
  String? helpTypeWire,
  String? uncommitReasonWire,
});

class CommitmentMessageDialog extends StatefulWidget {
  const CommitmentMessageDialog({
    required this.title,
    required this.hintText,
    this.initialText = '',
    this.allowEmptyMessage = false,
    this.showHelpTypeChips = false,
    this.requireUncommitReason = false,
    super.key,
  });

  static Future<CommitmentDialogOutcome?> show(
    BuildContext context, {
    required String title,
    required String hintText,
    String initialText = '',
    bool allowEmptyMessage = false,
    bool showHelpTypeChips = false,
    bool requireUncommitReason = false,
  }) =>
      showAdaptiveDialog<CommitmentDialogOutcome>(
        context: context,
        builder: (_) => CommitmentMessageDialog(
          title: title,
          hintText: hintText,
          initialText: initialText,
          allowEmptyMessage: allowEmptyMessage,
          showHelpTypeChips: showHelpTypeChips,
          requireUncommitReason: requireUncommitReason,
        ),
      );

  final String title;
  final String hintText;
  final String initialText;
  final bool allowEmptyMessage;
  final bool showHelpTypeChips;
  final bool requireUncommitReason;

  @override
  State<CommitmentMessageDialog> createState() =>
      _CommitmentMessageDialogState();
}

class _CommitmentMessageDialogState extends State<CommitmentMessageDialog> {
  late final TextEditingController _controller;
  CapabilityTag? _helpType;
  UncommitReason? _uncommitReason;

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

  void _submit(L10n l10n) {
    final text = _controller.text.trim();
    if (!widget.allowEmptyMessage && text.isEmpty) {
      return;
    }
    if (widget.requireUncommitReason && _uncommitReason == null) {
      return;
    }
    Navigator.of(context).pop((
      message: text,
      helpTypeWire: _helpType?.slug,
      uncommitReasonWire: _uncommitReason?.wireKey,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    return AlertDialog.adaptive(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.showHelpTypeChips) ...[
              Text(
                l10n.commitRolePrompt,
                style: theme.textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final t in CapabilityTag.values)
                    FilterChip(
                      label: Text(t.labelOf(l10n)),
                      selected: _helpType == t,
                      onSelected: (_) {
                        setState(() {
                          _helpType = _helpType == t ? null : t;
                        });
                      },
                    ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            if (widget.requireUncommitReason) ...[
              Text(
                l10n.labelUncommitReasonRequired,
                style: theme.textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final r in UncommitReason.values)
                    FilterChip(
                      label: Text(_uncommitReasonLabel(l10n, r)),
                      selected: _uncommitReason == r,
                      onSelected: (_) {
                        setState(() {
                          _uncommitReason = _uncommitReason == r ? null : r;
                        });
                      },
                    ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            TextField(
              autofocus: !widget.requireUncommitReason,
              controller: _controller,
              maxLines: 3,
              decoration: InputDecoration(hintText: widget.hintText),
              onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => _submit(l10n),
          child: Text(l10n.buttonOk),
        ),
        TextButton(
          onPressed: Navigator.of(context).pop,
          child: Text(l10n.buttonCancel),
        ),
      ],
    );
  }

  static String _uncommitReasonLabel(L10n l10n, UncommitReason r) =>
      switch (r) {
        UncommitReason.cannotDoIt => l10n.uncommitCantDoIt,
        UncommitReason.timing => l10n.uncommitTimingChanged,
        UncommitReason.wrongFit => l10n.uncommitWrongFit,
        UncommitReason.someoneElse => l10n.uncommitSomeoneElseTookOver,
        UncommitReason.other => l10n.uncommitOther,
      };
}
