import 'package:flutter/material.dart';

import 'package:tentura/ui/l10n/l10n.dart';

import '../bloc/auth_cubit.dart';

class AccountRemoveDialog extends StatelessWidget {
  static Future<void> show(BuildContext context, {required String id}) =>
      showAdaptiveDialog(
        context: context,
        builder: (context) => AccountRemoveDialog(id: id),
      );

  const AccountRemoveDialog({required this.id, super.key});

  final String id;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    return AlertDialog.adaptive(
      content: Text(l10n.confirmAccountRemoval),
      title: Text(id),
      actions: [
        TextButton(
          onPressed: () async {
            await GetIt.I<AuthCubit>().removeAccount(id);
            // TBD: check if it is really needed
            if (context.mounted) Navigator.of(context).pop();
          },
          child: const Text('Remove'),
        ),
        TextButton(
          onPressed: Navigator.of(context).pop,
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
