import 'package:flutter/material.dart';

import 'package:tentura/design_system/components/tentura_avatar.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Shared rows explaining [TenturaAvatar] contact badges (mutual / eye).
///
/// Used on the graph legend and profile trust-info sheet so copy stays aligned.
class ContactBadgeLegend extends StatelessWidget {
  const ContactBadgeLegend({
    this.showTextLabelNote = false,
    super.key,
  });

  /// When true, adds a note that profile/People text labels distinguish states
  /// the closed eye merges.
  final bool showTextLabelNote;

  static const _mutualProfile = Profile(
    id: 'legend-mutual',
    displayName: 'M',
    isMutualFriend: true,
  );

  static const _eyeOpenProfile = Profile(
    id: 'legend-seeing',
    displayName: 'O',
    score: 1,
    rScore: 1,
  );

  static const _eyeClosedProfile = Profile(
    id: 'legend-unseen',
    displayName: 'C',
  );

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.graphLegendBadgesTitle,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        SizedBox(height: tt.rowGap),
        _BadgeRow(
          label: l10n.graphLegendMutual,
          profile: _mutualProfile,
        ),
        SizedBox(height: tt.tightGap),
        _BadgeRow(
          label: l10n.graphLegendEyeOpen,
          profile: _eyeOpenProfile,
        ),
        SizedBox(height: tt.tightGap),
        _BadgeRow(
          label: l10n.graphLegendEyeClosed,
          profile: _eyeClosedProfile,
        ),
        if (showTextLabelNote) ...[
          SizedBox(height: tt.rowGap),
          Text(
            l10n.graphLegendNoteTextLabels,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _BadgeRow extends StatelessWidget {
  const _BadgeRow({
    required this.label,
    required this.profile,
  });

  final String label;
  final Profile profile;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return Semantics(
      label: label,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TenturaAvatar.medium(
            profile: profile,
            withContactBadge: true,
            withRating: false,
          ),
          SizedBox(width: tt.avatarTextGap),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: tt.tightGap),
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
