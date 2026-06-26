import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_window_class.dart';
import 'package:tentura/design_system/components/tentura_command_button.dart';
import 'package:tentura/design_system/components/tentura_text_action.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_filter.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

/// Empty My Desk body — callback-only; parent owns navigation.
class MyWorkEmptyBody extends StatelessWidget {
  const MyWorkEmptyBody({
    required this.filter,
    required this.draftCount,
    required this.archivedCountHint,
    required this.onCreateBeacon,
    required this.onOpenInbox,
    required this.onShowDrafts,
    required this.onShowArchived,
    this.inboxNeedsMeCount = 0,
    this.inboxLoadComplete = false,
    super.key,
  });

  final MyWorkFilter filter;
  final int draftCount;
  final int archivedCountHint;
  final int inboxNeedsMeCount;
  final bool inboxLoadComplete;
  final VoidCallback onCreateBeacon;
  final VoidCallback onOpenInbox;
  final VoidCallback onShowDrafts;
  final VoidCallback onShowArchived;

  bool get _showShortcuts =>
      filter != MyWorkFilter.archived &&
      filter != MyWorkFilter.drafts &&
      (draftCount > 0 || archivedCountHint > 0);

  bool get _inboxPrimary =>
      filter == MyWorkFilter.active &&
      inboxLoadComplete &&
      inboxNeedsMeCount > 0;

  String _title(L10n l10n) => switch (filter) {
    MyWorkFilter.active => l10n.myWorkEmptyActiveTitle,
    MyWorkFilter.all => l10n.myWorkEmptyAll,
    MyWorkFilter.authored => l10n.myWorkEmptyAuthored,
    MyWorkFilter.helpOffered => l10n.myWorkEmptyHelpOffered,
    MyWorkFilter.drafts => l10n.myWorkEmptyDrafts,
    MyWorkFilter.archived => l10n.myWorkEmptyArchived,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isActive = filter == MyWorkFilter.active;

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: context.windowClass == WindowClass.expanded ? 480 : 360,
        ),
        child: Padding(
          padding: kPaddingAll,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.work_outline,
                size: 48,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(height: kSpacingMedium),
              Text(
                _title(l10n),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: scheme.onSurface,
                ),
                textAlign: TextAlign.center,
              ),
              if (isActive) ...[
                const SizedBox(height: kSpacingSmall),
                Text(
                  l10n.myWorkEmptyActiveBody,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (_inboxPrimary) ...[
                  const SizedBox(height: kSpacingSmall),
                  Text(
                    l10n.myWorkEmptyActiveInboxHint,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: kSpacingMedium),
                if (_inboxPrimary) ...[
                  TenturaCommandButton(
                    label: l10n.myWorkEmptyActiveInboxPrimaryCta(
                      inboxNeedsMeCount,
                    ),
                    icon: const Icon(Icons.inbox_outlined),
                    onPressed: onOpenInbox,
                  ),
                  const SizedBox(height: kSpacingSmall),
                  TenturaTextAction(
                    label: l10n.myWorkEmptyActiveCreateCta,
                    onPressed: onCreateBeacon,
                  ),
                ] else ...[
                  TenturaCommandButton(
                    label: l10n.myWorkEmptyActiveCreateCta,
                    icon: const Icon(Icons.add),
                    onPressed: onCreateBeacon,
                  ),
                  const SizedBox(height: kSpacingSmall),
                  TenturaTextAction(
                    label: l10n.myWorkEmptyActiveInboxCta,
                    onPressed: onOpenInbox,
                  ),
                ],
              ],
              if (_showShortcuts) ...[
                if (!isActive) const SizedBox(height: kSpacingSmall),
                if (draftCount > 0) ...[
                  const SizedBox(height: kSpacingSmall),
                  TenturaTextAction(
                    label: l10n.myWorkEmptyDraftsShortcut(draftCount),
                    onPressed: onShowDrafts,
                  ),
                ],
                if (archivedCountHint > 0) ...[
                  const SizedBox(height: kSpacingSmall),
                  TenturaTextAction(
                    label: l10n.myWorkEmptyArchiveShortcut(archivedCountHint),
                    onPressed: onShowArchived,
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
