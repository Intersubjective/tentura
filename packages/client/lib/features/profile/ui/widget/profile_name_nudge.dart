import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Prompts the account owner to set a display name when only a placeholder remains.
class ProfileNameNudge extends StatelessWidget {
  const ProfileNameNudge({
    required this.profile,
    super.key,
  });

  final Profile profile;

  @override
  Widget build(BuildContext context) {
    if (!profile.needsDisplayNamePrompt) {
      return const SizedBox.shrink();
    }

    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final tt = context.tt;

    return Card(
      margin: EdgeInsets.only(bottom: tt.sectionGap),
      child: Padding(
        padding: tt.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.profileDisplayNameNudgeTitle,
              style: theme.textTheme.titleSmall,
            ),
            SizedBox(height: tt.tightGap),
            Text(
              l10n.profileDisplayNameNudgeBody,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            SizedBox(height: tt.rowGap),
            FilledButton(
              onPressed: () => context.read<ScreenCubit>().showProfileEditor(),
              child: Text(l10n.profileDisplayNameNudgeAction),
            ),
          ],
        ),
      ),
    );
  }
}
