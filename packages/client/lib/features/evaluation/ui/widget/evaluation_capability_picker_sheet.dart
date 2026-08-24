import 'package:flutter/material.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/capability/capability_tag.dart';
import 'package:tentura/features/capability/ui/widget/capability_chip_set.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

/// Adaptive picker used by evaluation acknowledgement controls.
///
/// The returned set is canonicalized to [CapabilityTag.values] order. A
/// dismissed sheet, Cancel, or back navigation returns null, allowing the
/// parent form to keep its previous selection unchanged.
class EvaluationCapabilityPickerSheet extends StatefulWidget {
  const EvaluationCapabilityPickerSheet({
    required this.initialSlugs,
    required this.availableSlugs,
    required this.maxSelection,
    this.scrollController,
    super.key,
  }) : _compact = null;

  const EvaluationCapabilityPickerSheet._presented({
    required this.initialSlugs,
    required this.availableSlugs,
    required this.maxSelection,
    required bool compact,
    this.scrollController,
  }) : _compact = compact;

  final Set<String> initialSlugs;
  final Set<String>? availableSlugs;
  final int maxSelection;
  final ScrollController? scrollController;
  final bool? _compact;

  static Future<Set<String>?> show(
    BuildContext context, {
    required Set<String> initialSlugs,
    required Set<String>? availableSlugs,
    required int maxSelection,
    ScrollController? scrollController,
  }) {
    final compact =
        windowClassForWidth(MediaQuery.sizeOf(context).width) ==
        WindowClass.compact;
    return showTenturaAdaptiveSheet<Set<String>>(
      context: context,
      builder: (_) => EvaluationCapabilityPickerSheet._presented(
        initialSlugs: initialSlugs,
        availableSlugs: availableSlugs,
        maxSelection: maxSelection,
        compact: compact,
        scrollController: scrollController,
      ),
    );
  }

  @override
  State<EvaluationCapabilityPickerSheet> createState() =>
      _EvaluationCapabilityPickerSheetState();
}

class _EvaluationCapabilityPickerSheetState
    extends State<EvaluationCapabilityPickerSheet> {
  late Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = _canonicalizeForPicker(
      widget.initialSlugs,
      availableSlugs: widget.availableSlugs,
      maxSelection: widget.maxSelection,
    );
  }

  @override
  Widget build(BuildContext context) {
    final compact =
        widget._compact ??
        windowClassForWidth(MediaQuery.sizeOf(context).width) ==
            WindowClass.compact;
    final content = _PickerContent(
      selected: _selected,
      availableSlugs: widget.availableSlugs,
      maxSelection: widget.maxSelection,
      scrollController: widget.scrollController,
      onChanged: (slugs) => setState(() => _selected = _canonicalize(slugs)),
      onCancel: () => Navigator.of(context).pop(),
      onDone: () => Navigator.of(context).pop(_canonicalize(_selected)),
    );

    if (!compact) return content;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, controller) => _PickerContent(
        selected: _selected,
        availableSlugs: widget.availableSlugs,
        maxSelection: widget.maxSelection,
        scrollController: widget.scrollController ?? controller,
        onChanged: (slugs) => setState(() => _selected = _canonicalize(slugs)),
        onCancel: () => Navigator.of(context).pop(),
        onDone: () => Navigator.of(context).pop(_canonicalize(_selected)),
      ),
    );
  }
}

class _PickerContent extends StatelessWidget {
  const _PickerContent({
    required this.selected,
    required this.availableSlugs,
    required this.maxSelection,
    required this.scrollController,
    required this.onChanged,
    required this.onCancel,
    required this.onDone,
  });

  final Set<String> selected;
  final Set<String>? availableSlugs;
  final int maxSelection;
  final ScrollController? scrollController;
  final ValueChanged<Set<String>> onChanged;
  final VoidCallback onCancel;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            tt.screenHPadding,
            tt.screenHPadding,
            tt.screenHPadding,
            tt.rowGap,
          ),
          child: Text(
            l10n.evaluationCapabilityChoose,
            style: theme.textTheme.titleMedium,
          ),
        ),
        Flexible(
          child: ListView(
            controller: scrollController,
            padding: EdgeInsets.only(
              left: tt.screenHPadding,
              right: tt.screenHPadding,
              bottom: tt.sectionGap,
            ),
            children: [
              CapabilityChipSet(
                selectedSlugs: selected,
                availableSlugs: availableSlugs,
                maxSelection: maxSelection,
                onChanged: onChanged,
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            tt.screenHPadding,
            tt.tightGap,
            tt.screenHPadding,
            tt.screenHPadding,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                key: TestIds.key(TestIds.evaluationCapabilityCancel),
                onPressed: onCancel,
                child: Text(l10n.buttonCancel),
              ),
              SizedBox(width: tt.tightGap),
              FilledButton(
                key: TestIds.key(TestIds.evaluationCapabilityDone),
                onPressed: selected.length <= maxSelection ? onDone : null,
                child: Text(l10n.evaluationCapabilityDone),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

Set<String> _canonicalize(Iterable<String> slugs) {
  final selected = slugs.toSet();
  return {
    for (final tag in CapabilityTag.values)
      if (selected.contains(tag.slug)) tag.slug,
  };
}

Set<String> _canonicalizeForPicker(
  Iterable<String> slugs, {
  required Set<String>? availableSlugs,
  required int maxSelection,
}) {
  final canonical = _canonicalize(slugs).where(
    (slug) => availableSlugs == null || availableSlugs.contains(slug),
  );
  return canonical
      .take(maxSelection.clamp(0, CapabilityTag.values.length))
      .toSet();
}
