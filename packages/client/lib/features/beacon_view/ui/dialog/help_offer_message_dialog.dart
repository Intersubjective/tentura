import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/withdraw_reason.dart';
import 'package:tentura/features/capability/ui/widget/capability_chip_set.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

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
  }) => showTenturaAdaptiveSheet<HelpOfferDialogOutcome>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    enableDrag: false,
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

  bool get _isDirty {
    if (_controller.text.trim() != widget.initialText.trim()) return true;
    if (_withdrawReason != null) return true;
    if (_helpTypeSlugs.length != widget.initialHelpTypeSlugs.length ||
        !_helpTypeSlugs.containsAll(widget.initialHelpTypeSlugs)) {
      return true;
    }
    return false;
  }

  Future<void> _requestClose() => TenturaSheetDismissGuard.requestClose(
    context,
    isDirty: _isDirty,
    useRootNavigator: true,
  );

  void _submit(L10n l10n) {
    if (!_canSubmit) return;
    final text = _controller.text.trim();
    Navigator.of(context).pop((
      message: text,
      helpTypesWire: _helpTypeSlugs.isEmpty ? null : _helpTypeSlugs.toList(),
      withdrawReasonWire: _withdrawReason?.wireKey,
    ));
  }

  bool get _canSubmit {
    if (widget.requireWithdrawReason && _withdrawReason == null) {
      return false;
    }
    if (!widget.allowEmptyMessage && _controller.text.trim().isEmpty) {
      return false;
    }
    if (widget.showHelpTypeChips && _helpTypeSlugs.isEmpty) {
      return false;
    }
    return true;
  }

  Widget _buildScrollContent(L10n l10n, ThemeData theme, TenturaTokens tt) {
    return Scrollbar(
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
                key: TestIds.key(TestIds.helpOfferSearch),
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
              key: TestIds.key(TestIds.helpOfferMessage),
              autofocus: !widget.requireWithdrawReason,
              controller: _controller,
              maxLines: 3,
              decoration: tenturaNoteInputDecoration(
                context,
                labelText: widget.showHelpTypeChips ? widget.hintText : null,
                hintText: widget.showHelpTypeChips ? null : widget.hintText,
              ),
              onChanged: (_) => setState(() {}),
              onTapOutside: (_) =>
                  FocusManager.instance.primaryFocus?.unfocus(),
            ),
          ],
        ),
      ),
    );
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
            Flexible(
              child: _buildScrollContent(l10n, theme, tt),
            ),
            SizedBox(height: tt.sectionGap),
            TextButton(
              onPressed: _requestClose,
              child: Text(l10n.buttonCancel),
            ),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: TestIds.key(TestIds.helpOfferSubmit),
                onPressed: _canSubmit ? () => _submit(l10n) : null,
                child: Text(
                  widget.showHelpTypeChips
                      ? l10n.helpOfferSubmit(_helpTypeSlugs.length, 4)
                      : l10n.buttonOk,
                ),
              ),
            ),
          ],
        ),
      ),
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
