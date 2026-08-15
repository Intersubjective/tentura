import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

/// Initial values when opening an ask/promise/blocker composer.
class AskComposerSeed {
  const AskComposerSeed({
    this.initialTitle = '',
    this.linkedMessageId,
    this.messagePreview,
  });

  final String initialTitle;
  final String? linkedMessageId;
  final String? messagePreview;

  factory AskComposerSeed.fromMessage({
    required String messageId,
    required String messageBody,
    String initialTitle = '',
  }) {
    final body = messageBody.trim();
    final title = initialTitle.trim();
    return AskComposerSeed(
      initialTitle: title.isNotEmpty ? title : body,
      linkedMessageId: messageId,
      messagePreview: body.isNotEmpty && title.isEmpty ? body : null,
    );
  }

  factory AskComposerSeed.fromItem(CoordinationItem item) => AskComposerSeed(
    initialTitle: item.title,
    linkedMessageId: item.linkedMessageId,
  );
}

/// Single required title field for ask, promise, and blocker composers.
class AskComposerFields extends StatelessWidget {
  const AskComposerFields({
    required this.l10n,
    required this.titleController,
    required this.submitting,
    required this.onChanged,
    this.messagePreview,
    super.key,
  });

  final L10n l10n;
  final TextEditingController titleController;
  final bool submitting;
  final VoidCallback onChanged;
  final String? messagePreview;

  static bool canSubmit(TextEditingController title, bool submitting) =>
      title.text.trim().isNotEmpty && !submitting;

  @override
  Widget build(BuildContext context) {
    final preview = messagePreview?.trim();
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (preview != null && preview.isNotEmpty) ...[
          Text(
            l10n.coordinationAskFromMessagePreview,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: kSpacingSmall),
          SelectableText(
            preview,
            style: theme.textTheme.bodyMedium,
            maxLines: 6,
          ),
          const SizedBox(height: kSpacingSmall),
        ],
        TextField(
          key: TestIds.key(TestIds.coordinationComposerTitle),
          controller: titleController,
          onChanged: (_) => onChanged(),
          maxLines: 6,
          minLines: 3,
          decoration: InputDecoration(
            labelText: l10n.labelTitle,
          ),
          textInputAction: TextInputAction.newline,
          enabled: !submitting,
          autofocus: preview == null || preview.isEmpty,
        ),
      ],
    );
  }
}
