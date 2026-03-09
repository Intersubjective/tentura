import 'package:flutter/material.dart';

import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

class MyFieldChooseTagsDialog extends StatefulWidget {
  static Future<Set<String>?> show(
    BuildContext context, {
    required List<String> allTags,
    required List<String> selectedTags,
  }) => showAdaptiveDialog<Set<String>>(
    context: context,
    builder: (_) => MyFieldChooseTagsDialog(
      allTags: allTags,
      selectedTags: selectedTags,
    ),
  );

  const MyFieldChooseTagsDialog({
    required this.allTags,
    required this.selectedTags,
    super.key,
  });

  final List<String> allTags;
  final List<String> selectedTags;

  @override
  State<MyFieldChooseTagsDialog> createState() =>
      _MyFieldChooseTagsDialogState();
}

class _MyFieldChooseTagsDialogState extends State<MyFieldChooseTagsDialog> {
  late final _selectedTags = widget.selectedTags.toSet();

  late final _theme = Theme.of(context);

  late final _l10n = L10n.of(context)!;

  @override
  Widget build(BuildContext context) => AlertDialog.adaptive(
    contentPadding: kPaddingAll,
    insetPadding: kPaddingAll,

    // Title
    title: Text(
      _l10n.filterByTag,
      style: _theme.textTheme.bodyMedium,
      textAlign: TextAlign.center,
    ),

    content: Wrap(
      spacing: kSpacingSmall,
      runSpacing: kSpacingSmall,
      children: [
        for (final tag in widget.allTags)
          ChoiceChip(
            backgroundColor: _theme.colorScheme.primary,
            label: Text(
              tag,
              style: _theme.chipTheme.labelStyle,
            ),
            selected: _selectedTags.contains(tag),
            onSelected: (isSelected) => setState(
              () => isSelected
                  ? _selectedTags.add(tag)
                  : _selectedTags.remove(tag),
            ),
          ),
      ],
    ),

    // Buttons
    actions: [
      // Ok
      TextButton(
        onPressed: () => Navigator.of(context).pop(_selectedTags),
        child: Text(_l10n.buttonOk),
      ),

      // Cancel
      TextButton(
        onPressed: Navigator.of(context).pop,
        child: Text(_l10n.buttonCancel),
      ),
    ],
  );
}
