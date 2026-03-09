import 'package:get_it/get_it.dart';
import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import '../bloc/friends_cubit.dart';

class FriendRemoveDialog extends StatelessWidget {
  static Future<void> show(BuildContext context, {required Profile profile}) =>
      showAdaptiveDialog(
        context: context,
        builder: (_) => FriendRemoveDialog(profile: profile),
      );

  const FriendRemoveDialog({required this.profile, super.key});

  final Profile profile;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    return AlertDialog.adaptive(
      title: Text(l10n.confirmFriendRemoval(profile.title)),
      actions: [
        // Remove
        TextButton(
          onPressed: () async {
            try {
              await GetIt.I<FriendsCubit>().removeFriend(profile);
            } catch (e) {
              if (context.mounted) {
                showSnackBar(context, isError: true, text: e.toString());
              }
            }
            if (context.mounted) Navigator.of(context).pop();
          },
          child: Text(l10n.buttonRemove),
        ),

        // Cancel
        TextButton(
          onPressed: Navigator.of(context).pop,
          child: Text(l10n.buttonCancel),
        ),
      ],
    );
  }
}
