import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/features/profile_view/ui/widget/mutual_friends_button.dart';
import 'package:tentura/design_system/components/tentura_avatar.dart';

import '../../domain/entity/invite_preview.dart';

class InvitationAcceptDialog extends StatelessWidget {
  static Future<bool?> show(
    BuildContext context, {
    required Profile profile,
    InvitePreviewBeacon? beacon,
  }) =>
      showAdaptiveDialog<bool>(
        context: context,
        builder: (_) => InvitationAcceptDialog(
          profile: profile,
          beacon: beacon,
        ),
      );

  const InvitationAcceptDialog({
    required this.profile,
    this.beacon,
    super.key,
  });

  final Profile profile;
  final InvitePreviewBeacon? beacon;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final beaconTitle = beacon?.title ?? '';
    final beaconSnippet = beacon?.snippet;
    return AlertDialog.adaptive(
      title: Text(
        beacon != null ? l10n.inviteAcceptBeaconTitle : l10n.confirmFriendAccept,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TenturaAvatar(
            profile: profile,
            size: kTenturaAvatarBigSize / 2,
          ),
          const SizedBox(height: kSpacingSmall),
          Text(
            profile.displayName,
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          if (beacon != null && beaconTitle.isNotEmpty) ...[
            const SizedBox(height: kSpacingSmall),
            Text(
              beaconTitle,
              style: theme.textTheme.titleSmall,
              textAlign: TextAlign.center,
            ),
            if (beaconSnippet != null && beaconSnippet.isNotEmpty) ...[
              const SizedBox(height: kSpacingSmall),
              Text(
                beaconSnippet,
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: kSpacingSmall),
            Text(
              l10n.inviteAcceptBeaconBody(profile.displayName),
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: kSpacingSmall),
          MutualFriendsButton(userId: profile.id),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.buttonYes),
        ),
        TextButton(
          onPressed: Navigator.of(context).pop,
          child: Text(l10n.buttonCancel),
        ),
      ],
    );
  }
}
