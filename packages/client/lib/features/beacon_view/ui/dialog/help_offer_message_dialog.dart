import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/withdraw_reason.dart';
import 'package:tentura/features/capability/ui/widget/capability_chip_set.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Result of [HelpOfferMessageDialog.show].
typedef HelpOfferDialogOutcome = ({
  String message,
  List<String>? helpTypesWire,
  String? withdrawReasonWire,
});

class HelpOfferMessageDialog extends StatefulWidget {
  const HelpOfferMessageDialog({
    required this.title,
    required this.hintText,
    this.initialText = '',
    this.allowEmptyMessage = false,
    this.showHelpTypeChips = false,
    this.initialHelpTypeSlugs = const {},
    this.automaticSlugs = const {},
    this.requireWithdrawReason = false,
    super.key,
  });

  static Future<HelpOfferDialogOutcome?> show(
    BuildContext context, {
    required String title,
    required String hintText,
    String initialText = '',
    bool allowEmptyMessage = false,
    bool showHelpTypeChips = false,
    Set<String> initialHelpTypeSlugs = const {},
    Set<String> automaticSlugs = const {},
    bool requireWithdrawReason = false,
  }) => showAdaptiveDialog<HelpOfferDialogOutcome>(
    context: context,
    builder: (_) => HelpOfferMessageDialog(
      title: title,
      hintText: hintText,
      initialText: initialText,
      allowEmptyMessage: allowEmptyMessage,
      showHelpTypeChips: showHelpTypeChips,
      initialHelpTypeSlugs: initialHelpTypeSlugs,
      automaticSlugs: automaticSlugs,
      requireWithdrawReason: requireWithdrawReason,
    ),
  );

  final String title;
  final String hintText;
  final String initialText;
  final bool allowEmptyMessage;
  final bool showHelpTypeChips;

  /// Pre-selected capability slugs when [showHelpTypeChips] is true.
  final Set<String> initialHelpTypeSlugs;

  /// Slugs shown with automatic/highlight styling (e.g. beacon-required needs).
  final Set<String> automaticSlugs;
  final bool requireWithdrawReason;

  @override
  State<HelpOfferMessageDialog> createState() => _HelpOfferMessageDialogState();
}

class _HelpOfferMessageDialogState extends State<HelpOfferMessageDialog> {
  late final TextEditingController _controller;
  late final TextEditingController _searchController;
  late final ScrollController _scrollController;
  late final Set<String> _helpTypeSlugs;
  WithdrawReason? _withdrawReason;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
    _searchController = TextEditingController();
    _scrollController = ScrollController();
    _helpTypeSlugs = Set<String>.from(widget.initialHelpTypeSlugs);
  }

  @override
  void dispose() {
    _controller.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _submit(L10n l10n) {
    final text = _controller.text.trim();
    if (!widget.allowEmptyMessage && text.isEmpty) {
      return;
    }
    if (widget.requireWithdrawReason && _withdrawReason == null) {
      return;
    }
    Navigator.of(context).pop((
      message: text,
      helpTypesWire: _helpTypeSlugs.isEmpty ? null : _helpTypeSlugs.toList(),
      withdrawReasonWire: _withdrawReason?.wireKey,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final tt = context.tt;
    return AlertDialog.adaptive(
      title: Text(widget.title),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: tt.contentMaxWidth ?? double.infinity,
          maxHeight: MediaQuery.sizeOf(context).height * 0.68,
        ),
        child: Scrollbar(
          controller: _scrollController,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _scrollController,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.showHelpTypeChips) ...[
                  Text(
                    l10n.helpOfferRolePrompt,
                    style: theme.textTheme.labelLarge,
                  ),
                  SizedBox(height: tt.rowGap),
                  Text(
                    l10n.helpOfferSelectionLimit,
                    style: theme.textTheme.bodySmall,
                  ),
                  SizedBox(height: tt.rowGap),
                  TextField(
                    key: const Key('help-offer-search'),
                    controller: _searchController,
                    decoration: InputDecoration(
                      labelText: l10n.helpOfferSearchLabel,
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: MaterialLocalizations.of(
                                context,
                              ).deleteButtonTooltip,
                              onPressed: () {
                                _searchController.clear();
                                setState(() {});
                              },
                              icon: const Icon(Icons.clear),
                            ),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  SizedBox(height: tt.rowGap),
                  CapabilityChipSet(
                    selectedSlugs: _helpTypeSlugs,
                    automaticSlugs: widget.automaticSlugs,
                    maxSelection: 4,
                    query: _searchController.text,
                    onChanged: (s) => setState(() {
                      _helpTypeSlugs
                        ..clear()
                        ..addAll(s);
                    }),
                  ),
                  SizedBox(height: tt.sectionGap),
                ],
                if (widget.requireWithdrawReason) ...[
                  Text(
                    l10n.labelWithdrawReasonRequired,
                    style: theme.textTheme.labelLarge,
                  ),
                  SizedBox(height: tt.rowGap),
                  Wrap(
                    spacing: tt.rowGap,
                    runSpacing: tt.rowGap,
                    children: [
                      for (final r in WithdrawReason.values)
                        FilterChip(
                          label: Text(_withdrawReasonLabel(l10n, r)),
                          selected: _withdrawReason == r,
                          onSelected: (_) {
                            setState(() {
                              _withdrawReason = _withdrawReason == r ? null : r;
                            });
                          },
                        ),
                    ],
                  ),
                  SizedBox(height: tt.sectionGap),
                ],
                TextField(
                  autofocus: !widget.requireWithdrawReason,
                  controller: _controller,
                  maxLines: 3,
                  decoration: InputDecoration(hintText: widget.hintText),
                  onTapOutside: (_) =>
                      FocusManager.instance.primaryFocus?.unfocus(),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: Navigator.of(context).pop,
          child: Text(l10n.buttonCancel),
        ),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => _submit(l10n),
            child: Text(
              widget.showHelpTypeChips
                  ? l10n.helpOfferSubmit(_helpTypeSlugs.length, 4)
                  : l10n.buttonOk,
            ),
          ),
        ),
      ],
    );
  }

  static String _withdrawReasonLabel(L10n l10n, WithdrawReason r) =>
      switch (r) {
        WithdrawReason.cannotDoIt => l10n.withdrawCantDoIt,
        WithdrawReason.timing => l10n.withdrawTimingChanged,
        WithdrawReason.wrongFit => l10n.withdrawWrongFit,
        WithdrawReason.someoneElse => l10n.withdrawSomeoneElseTookOver,
        WithdrawReason.other => l10n.withdrawOther,
      };
}
