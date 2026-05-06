import 'package:flutter/material.dart';

import 'package:tentura/domain/capability/friend_context.dart';
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
    this.friendContext = FriendContext.empty,
    this.trailing,
    this.privateLabels = const [],
    this.forwardedForSlugs = const [],
    this.commitRoleSlugs = const [],
    this.closeAckSlugs = const [],
    super.key,
  });

  final Profile profile;

  final FriendContext friendContext;

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

                  _FriendContextCountsRow(
                    l10n: l10n,
                    theme: theme,
                    context: friendContext,
                  ),
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

class _FriendContextCountsRow extends StatelessWidget {
  const _FriendContextCountsRow({
    required this.l10n,
    required this.theme,
    required this.context,
  });

  final L10n l10n;
  final ThemeData theme;
  final FriendContext context;

  @override
  Widget build(BuildContext context) {
    final inbox = this.context.activeForwardsToCount;
    final shared = this.context.coInvolvedBeaconsCount;
    if (inbox <= 0 && shared <= 0) return const SizedBox.shrink();

    final style = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (inbox > 0) ...[
            Tooltip(
              message: '$inbox active beacons forwarded to them',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.send_outlined,
                    size: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text('$inbox', style: style),
                ],
              ),
            ),
          ],
          if (shared > 0) ...[
            if (inbox > 0) const SizedBox(width: 10),
            Tooltip(
              message: '$shared active beacons you both see',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.radio_button_checked,
                    size: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text('$shared', style: style),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
