import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/features/profile_view/ui/widget/mutual_friends_button.dart';
import 'package:tentura/ui/widget/avatar_rated.dart';

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
    final theme = Theme.of(context);
    return AlertDialog.adaptive(
      title: Text(l10n.confirmFriendAccept),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AvatarRated(
            profile: profile,
            size: AvatarRated.sizeBig / 2,
            withRating: false,
          ),
          const SizedBox(height: kSpacingSmall),
          Text(
            profile.title,
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: kSpacingSmall),
          MutualFriendsButton(userId: profile.id),
        ],
      ),
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
