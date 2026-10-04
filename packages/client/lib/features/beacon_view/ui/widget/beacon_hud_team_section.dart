import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_request_modes.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// HUD team as party frames (#104): one row per member, avatar, name and
/// their current move.
class BeaconHudTeamSection extends StatelessWidget {
  const BeaconHudTeamSection({
    required this.members,
    required this.onOpenProfile,
    this.onOpenPeople,
    super.key,
  });

  final List<BeaconHudTeamMember> members;
  final ValueChanged<String> onOpenProfile;

  /// Opens the People tab (section header tap).
  final VoidCallback? onOpenPeople;

  @override
  Widget build(BuildContext context) {
    if (members.isEmpty) return const SizedBox.shrink();
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onOpenPeople,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: tt.tightGap),
            child: TenturaSectionHeader(
              label: l10n.beaconHudTeamSection,
              count: members.length,
            ),
          ),
        ),
        for (final m in members)
          _PartyFrame(member: m, onTap: () => onOpenProfile(m.profile.id)),
      ],
    );
  }
}

class _PartyFrame extends StatelessWidget {
  const _PartyFrame({required this.member, required this.onTap});

  final BeaconHudTeamMember member;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final move = member.nextMove;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(tt.buttonRadius),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
        child: Row(
          children: [
            TenturaAvatar(
              profile: member.profile,
              sizeBucket: TenturaAvatarSize.small,
            ),
            SizedBox(width: tt.avatarTextGap),
            Flexible(
              child: Text(
                member.profile.shownName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TenturaText.bodySmall(tt.text),
              ),
            ),
            if (member.isAuthor) ...[
              SizedBox(width: tt.tightGap),
              Text(
                l10n.beaconPeopleRoleAuthor,
                style: TenturaText.typeLabel(tt.textMuted),
              ),
            ],
            SizedBox(width: tt.rowGap),
            Expanded(
              flex: 2,
              child: Text(
                move ?? l10n.beaconHudTeamNoMove,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TenturaText.bodySmall(
                  move == null ? tt.textFaint : tt.textMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "ABOUT  first line of the description ▸" — the HUD keeps the pitch at
/// the very bottom, one tap from the full Details sheet.
class BeaconHudEssenceRow extends StatelessWidget {
  const BeaconHudEssenceRow({
    required this.beacon,
    required this.onOpenDetails,
    super.key,
  });

  final Beacon beacon;
  final VoidCallback onOpenDetails;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final text = beacon.description.trim().split('\n').first.trim();
    return InkWell(
      onTap: onOpenDetails,
      borderRadius: BorderRadius.circular(tt.buttonRadius),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
        child: Row(
          children: [
            Text(
              l10n.beaconHudEssenceLabel,
              style: TenturaText.typeLabel(tt.textMuted),
            ),
            SizedBox(width: tt.rowGap),
            Expanded(
              child: Text(
                text.isEmpty ? l10n.beaconDetailsSection : text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TenturaText.bodySmall(tt.text),
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: tt.iconSize,
              color: tt.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}
