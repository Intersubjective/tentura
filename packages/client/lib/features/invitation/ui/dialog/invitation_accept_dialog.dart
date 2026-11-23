import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/util/ui_utils.dart';
import 'package:tentura/features/profile_view/ui/widget/mutual_friends_button.dart';
import 'package:tentura/design_system/components/tentura_avatar.dart';

import '../../domain/entity/invite_preview.dart';

class InvitationAcceptDialog extends StatelessWidget {
  static Future<bool?> show(
    BuildContext context, {
    required Profile profile,
    InvitePreviewBeacon? beacon,
    bool signup = false,
  }) => showAdaptiveDialog<bool>(
    context: context,
    builder: (_) => InvitationAcceptDialog(
      profile: profile,
      beacon: beacon,
      signup: signup,
    ),
  );

  const InvitationAcceptDialog({
    required this.profile,
    this.beacon,
    this.signup = false,
    super.key,
  });

  final Profile profile;
  final InvitePreviewBeacon? beacon;
  final bool signup;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final beacon = this.beacon;
    final beaconTitle = beacon?.title ?? '';
    final beaconSnippet = beacon?.snippet;
    final lapsed = beacon?.lapsed ?? false;
    return AlertDialog.adaptive(
      scrollable: lapsed,
      title: Text(switch (beacon) {
        null => l10n.confirmFriendAccept,
        InvitePreviewBeacon(lapsed: true) => l10n.inviteLapsedTitle,
        InvitePreviewBeacon(isPost: true) => l10n.inviteAcceptPostTitle,
        _ => l10n.inviteAcceptBeaconTitle,
      }),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TenturaAvatar(
            profile: profile,
            size: kTenturaAvatarBigSize / 2,
          ),
          const SizedBox(height: kSpacingSmall),
          Text(
            profile.shownName,
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          if (lapsed) ...[
            const SizedBox(height: kSpacingSmall),
            Text(
              signup
                  ? l10n.inviteLapsedSignupBody(profile.shownName, beaconTitle)
                  : l10n.inviteLapsedExistingBody(
                      profile.shownName,
                      beaconTitle,
                    ),
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ] else if (beacon != null && beaconTitle.isNotEmpty) ...[
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
              signup
                  ? l10n.inviteAcceptBeaconBody(profile.shownName)
                  : beacon.isPost
                  ? l10n.inviteAcceptPostAccessBody
                  : l10n.inviteAcceptBeaconAccessBody,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
          if (!signup) ...[
            const SizedBox(height: kSpacingSmall),
            MutualFriendsButton(userId: profile.id),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(
            signup
                ? l10n.buttonNext
                : lapsed
                ? l10n.inviteAccept
                : l10n.buttonYes,
          ),
        ),
        TextButton(
          onPressed: Navigator.of(context).pop,
          child: Text(l10n.buttonCancel),
        ),
      ],
    );
  }
}
