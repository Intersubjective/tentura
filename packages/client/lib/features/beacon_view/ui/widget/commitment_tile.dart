import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/avatar_rated.dart';
import 'package:tentura/features/beacon/ui/widget/coordination_ui.dart';
import 'package:tentura/ui/widget/beacon_card_primitives.dart';
import 'package:tentura/ui/widget/self_user_highlight.dart';

import '../bloc/beacon_view_state.dart';

/// Compact commitment roster row (not a comment thread).
class CommitmentTile extends StatelessWidget {
  const CommitmentTile({
    required this.commitment,
    required this.beaconAuthor,
    this.isMine = false,
    this.onEdit,
    this.onWithdraw,
    this.isAuthorView = false,
    this.onAuthorTapCoordination,
    super.key,
  });

  final TimelineCommitment commitment;
  final Profile beaconAuthor;
  final bool isMine;
  final VoidCallback? onEdit;
  final VoidCallback? onWithdraw;
  final bool isAuthorView;
  final VoidCallback? onAuthorTapCoordination;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final isWithdrawn = commitment.isWithdrawn;
    final opacity = isWithdrawn ? 0.55 : 1.0;
    final dateShown = isWithdrawn ? commitment.updatedAt : commitment.createdAt;
    final coordinationLabel = coordinationResponseLabel(
      l10n,
      commitment.coordinationResponse,
    );

    return Opacity(
      opacity: opacity,
      child: Card(
        margin: const EdgeInsets.only(bottom: kSpacingSmall),
        child: Padding(
          padding: kPaddingAllS,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: isMine
                        ? null
                        : () => context.read<ScreenCubit>().showProfile(
                              commitment.user.id,
                            ),
                    child: AvatarRated(
                      profile: commitment.user,
                    ),
                  ),
                  const SizedBox(width: kSpacingSmall),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        BlocBuilder<ProfileCubit, ProfileState>(
                          buildWhen: (p, c) => p.profile.id != c.profile.id,
                          builder: (context, state) {
                            return Text(
                              SelfUserHighlight.displayName(
                                l10n,
                                commitment.user,
                                state.profile.id,
                              ),
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            );
                          },
                        ),
                        Text(
                          '${dateFormatYMD(dateShown.toLocal())} · ${timeFormatHm(dateShown.toLocal())}'
                              '${commitment.isEdited ? ' · ${l10n.labelEdited}' : ''}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isWithdrawn)
                    BeaconCardPill(
                      label: l10n.labelWithdrawn,
                      backgroundColor: theme.colorScheme.errorContainer,
                      foregroundColor: theme.colorScheme.onErrorContainer,
                    ),
                ],
              ),
              if (helpTypeLabel(l10n, commitment.helpType) != null) ...[
                const SizedBox(height: kSpacingSmall),
                Align(
                  alignment: Alignment.centerLeft,
                  child: BeaconCardPill(
                    label: helpTypeLabel(l10n, commitment.helpType)!,
                    backgroundColor: theme.colorScheme.surfaceContainerHigh,
                    foregroundColor: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (commitment.message.isNotEmpty) ...[
                const SizedBox(height: kSpacingSmall),
                Text(
                  commitment.message,
                  style: theme.textTheme.bodySmall,
                ),
              ],
              if (coordinationLabel != null && !isWithdrawn) ...[
                const SizedBox(height: kSpacingSmall),
                Wrap(
                  spacing: kSpacingSmall,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      l10n.labelCoordinationStatus,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    BeaconCardPill(
                      label: coordinationLabel,
                      backgroundColor:
                          theme.colorScheme.secondaryContainer.withValues(
                        alpha: 0.85,
                      ),
                      foregroundColor: theme.colorScheme.onSecondaryContainer,
                    ),
                    if (isAuthorView && onAuthorTapCoordination != null)
                      TextButton(
                        onPressed: onAuthorTapCoordination,
                        child: Text(l10n.labelSetCoordinationResponse),
                      ),
                  ],
                ),
              ],
              if (isMine && !isWithdrawn && (onEdit != null || onWithdraw != null))
                Padding(
                  padding: const EdgeInsets.only(top: kSpacingSmall),
                  child: Wrap(
                    spacing: kSpacingSmall,
                    children: [
                      if (onEdit != null)
                        TextButton(
                          onPressed: onEdit,
                          child: Text(l10n.beaconCtaEditCommitment),
                        ),
                      if (onWithdraw != null)
                        TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: theme.colorScheme.error,
                          ),
                          onPressed: onWithdraw,
                          child: Text(l10n.dialogWithdrawTitle),
                        ),
                    ],
                  ),
                ),
              if (isWithdrawn &&
                  uncommitReasonLabel(l10n, commitment.uncommitReason) != null)
                Padding(
                  padding: const EdgeInsets.only(top: kSpacingSmall),
                  child: Text(
                    uncommitReasonLabel(l10n, commitment.uncommitReason)!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
