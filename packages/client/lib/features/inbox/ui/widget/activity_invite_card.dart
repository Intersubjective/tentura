import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

/// The «Для вас» author-invite card (plan D3): who invites the viewer to help
/// on a Request, their note, and «Принять» / «Не смогу».
///
/// It replaces the pinned Request card for a row that carries a pending
/// invite; accepting is the viewer's own confirmation, so there is no
/// «Предложить помощь» here.
class ActivityInviteCard extends StatelessWidget {
  const ActivityInviteCard({
    required this.beaconId,
    required this.requestTitle,
    required this.onAccept,
    required this.onDecline,
    required this.onOpen,
    this.inviter,
    this.note = '',
    super.key,
  });

  final String beaconId;
  final String requestTitle;

  /// Null until the inviter's profile has loaded.
  final Profile? inviter;
  final String note;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final name = inviter?.shownName.trim() ?? '';
    final title = l10n.inviteCardTitle(
      name.isNotEmpty ? name : l10n.unknownPerson,
    );
    final trimmedNote = note.trim();

    return Semantics(
      identifier: TestIds.activityOffer(beaconId),
      child: TenturaTechCard(
        key: ValueKey('ActivityInviteCard.$beaconId'),
        onTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                if (inviter != null) ...[
                  ExcludeSemantics(
                    child: TenturaAvatar.small(profile: inviter!),
                  ),
                  SizedBox(width: tt.avatarTextGap),
                ],
                Expanded(
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TenturaText.titleSmall(tt.text),
                  ),
                ),
              ],
            ),
            if (requestTitle.trim().isNotEmpty) ...[
              SizedBox(height: tt.rowGap),
              Text(
                requestTitle.trim(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TenturaText.bodyMedium(tt.text),
              ),
            ],
            if (trimmedNote.isNotEmpty) ...[
              SizedBox(height: tt.tightGap),
              Text(
                trimmedNote,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: TenturaText.bodySmall(tt.textMuted),
              ),
            ],
            SizedBox(height: tt.rowGap),
            // Wraps on narrow widths and large text instead of overflowing.
            OverflowBar(
              alignment: MainAxisAlignment.end,
              overflowAlignment: OverflowBarAlignment.end,
              spacing: tt.tightGap,
              overflowSpacing: tt.tightGap,
              children: [
                TextButton(
                  key: const Key('ActivityInviteCard.Decline'),
                  onPressed: onDecline,
                  child: Text(l10n.inviteDecline),
                ),
                FilledButton(
                  key: const Key('ActivityInviteCard.Accept'),
                  onPressed: onAccept,
                  child: Text(l10n.inviteAccept),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
