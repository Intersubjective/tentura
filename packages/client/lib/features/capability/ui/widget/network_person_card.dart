import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/self_aware_profile_avatar.dart';
import 'package:tentura/ui/widget/self_user_highlight.dart';

import 'capability_cue_strip.dart';

/// Network/Friends surface card for a peer.
///
/// Tapping anywhere opens the peer's profile. No chat navigation is wired here.
/// Signal-strength order: closeAck > commitRole > forwardReason > privateLabel.
class NetworkPersonCard extends StatelessWidget {
  const NetworkPersonCard({
    required this.profile,
    this.trailing,
    this.privateLabels = const [],
    this.forwardedForSlugs = const [],
    this.commitRoleSlugs = const [],
    this.closeAckSlugs = const [],
    super.key,
  });

  final Profile profile;

  /// Optional trailing widget (e.g. a Forward button).
  final Widget? trailing;

  /// Private-label slugs this viewer has set for [profile] (Phase 1+).
  final List<String> privateLabels;

  /// Forward-reason slugs (aggregated by count) — "Often forwarded for" (Phase 2+).
  final List<String> forwardedForSlugs;

  /// Commit-role slugs — "Committed" (Phase 3+).
  final List<String> commitRoleSlugs;

  /// Close-acknowledgement slugs — strongest signal (Phase 4+).
  final List<String> closeAckSlugs;

  @override
  Widget build(BuildContext context) {
    final screenCubit = context.read<ScreenCubit>();
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => screenCubit.showProfile(profile.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            SelfAwareAvatar.small(profile: profile),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  BlocBuilder<ProfileCubit, ProfileState>(
                    buildWhen: (p, c) => p.profile.id != c.profile.id,
                    builder: (context, state) {
                      final isSelf = SelfUserHighlight.profileIsSelf(
                        profile,
                        state.profile.id,
                      );
                      return Text(
                        SelfUserHighlight.displayName(
                          l10n,
                          profile,
                          state.profile.id,
                        ),
                        style: SelfUserHighlight.nameStyle(
                          theme,
                          theme.textTheme.bodyLarge,
                          isSelf,
                        ),
                      );
                    },
                  ),
                  // Signal-strength order: closeAck > commitRole > forwardReason > privateLabel
                  if (closeAckSlugs.isNotEmpty)
                    Text(
                      l10n.capabilityCueAcknowledged(
                        closeAckSlugs.join(' · '),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    )
                  else if (commitRoleSlugs.isNotEmpty)
                    Text(
                      l10n.capabilityCueCommitted(
                        commitRoleSlugs.join(' · '),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    )
                  else if (forwardedForSlugs.isNotEmpty)
                    Text(
                      l10n.capabilityCueForwardedFor(
                        forwardedForSlugs.join(' · '),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    )
                  else if (privateLabels.isNotEmpty)
                    CapabilityCueStrip(slugs: privateLabels),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}
