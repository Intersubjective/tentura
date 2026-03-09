import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/l10n/l10n.dart';

class InvitationAcceptDialog extends StatelessWidget {
  static Future<bool?> show(BuildContext context, {required Profile profile}) =>
      showAdaptiveDialog<bool>(
        context: context,
        builder: (_) => InvitationAcceptDialog(profile: profile),
      );

  const InvitationAcceptDialog({required this.profile, super.key});

  final Profile profile;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    return AlertDialog.adaptive(
      title: Text(l10n.confirmFriendAccept(profile.title)),
      actions: [
        // Accept
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.buttonYes),
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
