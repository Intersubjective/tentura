import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/capability/capability_group.dart';
import 'package:tentura/domain/capability/capability_tag.dart';
import 'package:tentura/domain/capability/offer_help_classification.dart';
import 'package:tentura/domain/capability/offer_help_suggestions.dart';
import 'package:tentura/domain/entity/withdraw_reason.dart';
import 'package:tentura/features/capability/ui/widget/capability_chip_set.dart';
import 'package:tentura/features/capability/ui/widget/capability_tag_chip.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/widget/tentura_info_hint_button.dart';

final _log = Logger('HelpOfferMessageDialog');

/// Result of [HelpOfferMessageDialog.show].
typedef HelpOfferDialogOutcome = ({
  String message,
  List<String>? helpTypesWire,
  String? withdrawReasonWire,
  OfferHelpClassificationPath? classificationPath,
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
  bool _browseOpen = false;
  bool _browsedFullTaxonomy = false;

  static const _maxSelection = 4;

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

  List<String> get _suggestedSlugs => suggestOfferHelpSlugs(
    message: _controller.text,
    automaticSlugs: widget.automaticSlugs,
  );

  void _toggleSlug(String slug, bool selected) {
    setState(() {
      if (selected) {
        if (_helpTypeSlugs.length >= _maxSelection) return;
        _helpTypeSlugs.add(slug);
      } else {
        _helpTypeSlugs.remove(slug);
      }
    });
  }

  void _submit() {
    if (!_canSubmit) return;
    final text = _controller.text.trim();
    final suggested = _suggestedSlugs.toSet();
    final path = widget.showHelpTypeChips
        ? resolveOfferHelpClassificationPath(
            selectedSlugs: _helpTypeSlugs,
            suggestedSlugsAtSubmit: suggested,
            browsedFullTaxonomy: _browsedFullTaxonomy,
          )
        : null;
    if (path != null) {
      _log.info('offer_help_classification=${path.name}');
    }
    Navigator.of(context).pop((
      message: text,
      helpTypesWire: _helpTypeSlugs.isEmpty ? null : _helpTypeSlugs.toList(),
      withdrawReasonWire: _withdrawReason?.wireKey,
      classificationPath: path,
    ));
  }

  bool get _canSubmit {
    if (widget.requireWithdrawReason && _withdrawReason == null) {
      return false;
    }
    if (!widget.allowEmptyMessage && _controller.text.trim().isEmpty) {
      return false;
    }
    return true;
  }

  bool _searchHasMatches(L10n l10n) {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return true;
    for (final tag in CapabilityTag.values) {
      if (tag.labelOf(l10n).toLowerCase().contains(query)) return true;
    }
    for (final group in CapabilityGroup.values) {
      if (_groupLabel(l10n, group).toLowerCase().contains(query)) return true;
      if (_groupDescription(l10n, group).toLowerCase().contains(query)) {
        return true;
      }
    }
    return false;
  }

  static String _groupLabel(L10n l10n, CapabilityGroup group) =>
      switch (group) {
        CapabilityGroup.logistics => l10n.capabilityGroupLogistics,
        CapabilityGroup.communication => l10n.capabilityGroupCommunication,
        CapabilityGroup.knowledge => l10n.capabilityGroupKnowledge,
        CapabilityGroup.care => l10n.capabilityGroupCare,
        CapabilityGroup.resources => l10n.capabilityGroupResources,
        CapabilityGroup.technical => l10n.capabilityGroupTechnical,
        CapabilityGroup.special => l10n.capabilityGroupSpecial,
      };

  static String _groupDescription(L10n l10n, CapabilityGroup group) =>
      switch (group) {
        CapabilityGroup.logistics => l10n.capabilityGroupLogisticsDescription,
        CapabilityGroup.communication =>
          l10n.capabilityGroupCommunicationDescription,
        CapabilityGroup.knowledge => l10n.capabilityGroupKnowledgeDescription,
        CapabilityGroup.care => l10n.capabilityGroupCareDescription,
        CapabilityGroup.resources => l10n.capabilityGroupResourcesDescription,
        CapabilityGroup.technical => l10n.capabilityGroupTechnicalDescription,
        CapabilityGroup.special => l10n.capabilityGroupSpecialDescription,
      };

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
                labelText: widget.hintText,
              ),
              onChanged: (_) => setState(() {}),
              onTapOutside: (_) =>
                  FocusManager.instance.primaryFocus?.unfocus(),
            ),
            if (widget.showHelpTypeChips) ...[
              SizedBox(height: tt.sectionGap),
              Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Semantics(
                        identifier: TestIds.helpOfferBrowseCategories,
                        button: true,
                        child: TextButton.icon(
                          key: TestIds.key(TestIds.helpOfferBrowseCategories),
                          onPressed: () {
                            setState(() {
                              _browseOpen = !_browseOpen;
                              if (_browseOpen) {
                                _browsedFullTaxonomy = true;
                              }
                            });
                          },
                          icon: Icon(
                            _browseOpen
                                ? Icons.expand_less_rounded
                                : Icons.expand_more_rounded,
                          ),
                          label: Text(
                            _browseOpen
                                ? l10n.helpOfferHideCategories
                                : l10n.helpOfferBrowseCategories,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (_helpTypeSlugs.isNotEmpty)
                    Padding(
                      padding: EdgeInsets.only(left: tt.tightGap),
                      child: Wrap(
                        spacing: tt.tightGap / 2,
                        runSpacing: tt.tightGap / 2,
                        children: [
                          for (final slug in _helpTypeSlugs)
                            if (CapabilityTag.fromSlug(slug) case final tag?)
                              CapabilityTagIconChip(
                                tag: tag,
                                l10n: l10n,
                                onTap: () => _toggleSlug(slug, false),
                              ),
                        ],
                      ),
                    ),
                  TenturaInfoHintButton(
                    fullText: l10n.helpOfferOptionalEnrichmentHelper,
                    semanticsLabel: l10n.helpOfferOptionalEnrichmentLabel,
                  ),
                ],
              ),
              if (_browseOpen) ...[
                SizedBox(height: tt.rowGap),
                Semantics(
                  identifier: TestIds.helpOfferSearch,
                  textField: true,
                  child: TextField(
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
                ),
                SizedBox(height: tt.rowGap),
                if (!_searchHasMatches(l10n))
                  Text(
                    l10n.helpOfferSearchEmpty,
                    style: theme.textTheme.bodySmall,
                  )
                else
                  CapabilityChipSet(
                    selectedSlugs: _helpTypeSlugs,
                    automaticSlugs: widget.automaticSlugs,
                    maxSelection: _maxSelection,
                    query: _searchController.text,
                    onChanged: (s) => setState(() {
                      _helpTypeSlugs
                        ..clear()
                        ..addAll(s);
                    }),
                  ),
              ],
            ],
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final mediaHeight = MediaQuery.sizeOf(context).height;
          final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
          final maxHeight = constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : mediaHeight * 0.9;
          return ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: Padding(
              padding: EdgeInsets.only(
                left: tt.screenHPadding,
                right: tt.screenHPadding,
                top: tt.rowGap,
                bottom: viewInsets + tt.sectionGap,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.title,
                    style: theme.textTheme.titleMedium,
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
                    child: Semantics(
                      identifier: TestIds.helpOfferSubmit,
                      button: true,
                      enabled: _canSubmit,
                      child: FilledButton(
                        key: TestIds.key(TestIds.helpOfferSubmit),
                        onPressed: _canSubmit ? _submit : null,
                        child: Text(
                          widget.showHelpTypeChips
                              ? l10n.helpOfferSubmitAction
                              : l10n.buttonOk,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
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
