import 'package:flutter/material.dart';

import 'package:tentura/ui/l10n/l10n.dart';

import 'package:tentura/ui/utils/ui_utils.dart';

import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';

import '../bloc/profile_cubit.dart';

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
          onPressed: () async {
            try {
              final authCubit = GetIt.I<AuthCubit>();
              await GetIt.I<ProfileCubit>().delete();
              await authCubit.removeAccount(authCubit.state.currentAccountId);
            } catch (e) {
              if (context.mounted) {
                showSnackBar(context, isError: true, text: e.toString());
              }
            }
            if (context.mounted) Navigator.of(context).pop();
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
