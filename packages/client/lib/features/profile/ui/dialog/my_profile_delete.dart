import 'package:flutter/material.dart';

import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';

class MyProfileDeleteDialog extends StatelessWidget {
  static Future<void> show(BuildContext context) => showAdaptiveDialog<void>(
    context: context,
    builder: (context) => const MyProfileDeleteDialog(),
  );

  const MyProfileDeleteDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    return AlertDialog.adaptive(
      title: Text(l10n.confirmProfileRemoval),
      content: Text(l10n.profileRemovalHint),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
            final profileId = GetIt.I<ProfileCubit>().state.profile.id;
            GetIt.I<ScreenCubit>().showAccountDeletionRequest(profileId);
          },
          child: Text(l10n.buttonDelete),
        ),
        TextButton(
          onPressed: Navigator.of(context).pop,
          child: Text(l10n.buttonCancel),
        ),
      ],
    );
  }
}
