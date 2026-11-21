import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/util/profile_member_since.dart';
import 'package:tentura/ui/util/ui_utils.dart';

/// Calm metadata under the profile summary: join date plus tenure on Tentura.
class ProfileMemberSinceLine extends StatelessWidget {
  const ProfileMemberSinceLine({
    required this.profile,
    this.now,
    super.key,
  });

  final Profile profile;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final joinedAt = profile.joinedAt;
    if (joinedAt == null) {
      return const SizedBox.shrink();
    }
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final line = profileMemberSinceDisplayLine(
      l10n: l10n,
      joinedAt: joinedAt,
      now: now ?? DateTime.now(),
    );
    return Padding(
      padding: kPaddingSmallT,
      child: Text(
        line,
        key: const Key('profile_member_since_line'),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
        softWrap: true,
      ),
    );
  }
}
