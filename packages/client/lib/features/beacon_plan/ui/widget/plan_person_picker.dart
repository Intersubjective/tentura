import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// The pick of [showPlanPersonPicker]: a person id, or null for «nobody».
typedef PlanPersonPick = ({String? userId});

/// Single-select of admitted people (owner rule: steps go only to people
/// admitted to the Request). [allowNone] adds «Без исполнителя». Returns
/// null when dismissed.
Future<PlanPersonPick?> showPlanPersonPicker(
  BuildContext context, {
  required String title,
  required List<Profile> people,
  String? selectedId,
  bool allowNone = false,
  String? emptyText,
}) => showTenturaAdaptiveSheet<PlanPersonPick>(
  context: context,
  useRootNavigator: true,
  builder: (ctx) {
    final l10n = L10n.of(ctx)!;
    final tt = ctx.tt;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: tt.screenHPadding,
              vertical: tt.rowGap,
            ),
            child: Text(title, style: TenturaText.titleSmall(tt.text)),
          ),
          if (people.isEmpty && emptyText != null)
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: tt.screenHPadding,
                vertical: tt.rowGap,
              ),
              child: Text(
                emptyText,
                style: TenturaText.bodySmall(tt.textMuted),
              ),
            ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                if (allowNone)
                  ListTile(
                    leading: const Icon(Icons.person_off_outlined),
                    title: Text(l10n.planFieldNoAssignee),
                    trailing: selectedId == null
                        ? const Icon(Icons.check)
                        : null,
                    onTap: () => Navigator.of(ctx).pop((userId: null)),
                  ),
                for (final p in people)
                  ListTile(
                    leading: TenturaAvatar(
                      profile: p,
                      sizeBucket: TenturaAvatarSize.small,
                    ),
                    title: Text(
                      p.shownName.isEmpty ? l10n.unknownPerson : p.shownName,
                    ),
                    trailing: selectedId == p.id
                        ? const Icon(Icons.check)
                        : null,
                    onTap: () => Navigator.of(ctx).pop((userId: p.id)),
                  ),
              ],
            ),
          ),
          SizedBox(height: tt.rowGap),
        ],
      ),
    );
  },
);
