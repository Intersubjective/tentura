import 'package:get_it/get_it.dart';
import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import '../bloc/friends_cubit.dart';

class FriendRemoveDialog extends StatelessWidget {
  static Future<void> show(
    BuildContext context, {
    required Profile profile,
    Future<void> Function()? onRemove,
  }) =>
      showAdaptiveDialog(
        context: context,
        builder: (_) => FriendRemoveDialog(
          profile: profile,
          onRemove: onRemove,
        ),
      );

  const FriendRemoveDialog({
    required this.profile,
    this.onRemove,
    super.key,
  });

  final Profile profile;
  final Future<void> Function()? onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    return AlertDialog.adaptive(
      title: Text(l10n.confirmFriendRemoval(profile.shownName)),
      actions: [
        // Remove
        TextButton(
          onPressed: () async {
            final remove =
                onRemove ??
                () => GetIt.I<FriendsCubit>().removeFriend(profile);
            try {
              await remove();
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
