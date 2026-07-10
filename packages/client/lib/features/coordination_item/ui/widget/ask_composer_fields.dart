import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

/// Initial values when opening an ask composer (e.g. from a room message).
class AskComposerSeed {
  const AskComposerSeed({
    this.initialTitle = '',
    this.initialBody = '',
    this.linkedMessageId,
    this.messagePreview,
  });

  final String initialTitle;
  final String initialBody;
  final String? linkedMessageId;
  final String? messagePreview;

  factory AskComposerSeed.fromMessage({
    required String messageId,
    required String messageBody,
    String initialTitle = '',
  }) {
    final body = messageBody.trim();
    return AskComposerSeed(
      initialTitle: initialTitle,
      initialBody: body,
      linkedMessageId: messageId,
      messagePreview: body.isNotEmpty ? body : null,
    );
  }

  factory AskComposerSeed.fromItem(CoordinationItem item) => AskComposerSeed(
    initialTitle: item.title,
    initialBody: item.body,
    linkedMessageId: item.linkedMessageId,
  );
}

/// Title (optional) + body (required) fields for ask and draft ask sheets.
class AskComposerFields extends StatelessWidget {
  const AskComposerFields({
    required this.l10n,
    required this.titleController,
    required this.bodyController,
    required this.submitting,
    required this.onChanged,
    this.messagePreview,
    super.key,
  });

  final L10n l10n;
  final TextEditingController titleController;
  final TextEditingController bodyController;
  final bool submitting;
  final VoidCallback onChanged;
  final String? messagePreview;

  static bool canSubmit(TextEditingController body, bool submitting) =>
      body.text.trim().isNotEmpty && !submitting;

  @override
  Widget build(BuildContext context) {
    final preview = messagePreview?.trim();
    final theme = Theme.of(context);
    return SelectionArea(
      child: Column(
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
            maxLines: 2,
            minLines: 1,
            decoration: InputDecoration(
              labelText: l10n.labelTitleOptional,
            ),
            textInputAction: TextInputAction.next,
            enabled: !submitting,
          ),
          const SizedBox(height: kSpacingSmall),
          TextField(
            key: TestIds.key(TestIds.coordinationComposerBody),
            controller: bodyController,
            onChanged: (_) => onChanged(),
            maxLines: 6,
            minLines: 3,
            decoration: InputDecoration(
              labelText: l10n.labelBody,
            ),
            textInputAction: TextInputAction.newline,
            enabled: !submitting,
            autofocus: preview == null || preview.isEmpty,
          ),
        ],
      ),
    );
  }
}
