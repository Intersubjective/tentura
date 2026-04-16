import 'package:flutter/material.dart';

import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/features/beacon/ui/widget/coordination_ui.dart';
import 'package:tentura/ui/widget/beacon_card_primitives.dart';
import 'package:tentura/ui/widget/show_more_text.dart';

import '../bloc/beacon_view_state.dart';
import 'plain_mini_avatar.dart';

class CommitmentTile extends StatelessWidget {
  const CommitmentTile({
    required this.commitment,
    this.isMine = false,
    this.onEdit,
    this.isAuthorView = false,
    this.onAuthorTapCoordination,
    super.key,
  });

  final TimelineCommitment commitment;
  final bool isMine;
  final VoidCallback? onEdit;
  final bool isAuthorView;
  final VoidCallback? onAuthorTapCoordination;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final isWithdrawn = commitment.isWithdrawn;
    final opacity = isWithdrawn ? 0.65 : 1.0;
    final dateShown = isWithdrawn ? commitment.updatedAt : commitment.createdAt;
    return Opacity(
      opacity: opacity,
      child: Column(
        children: [
          const Divider(),
          Padding(
            key: const Key('CommitmentHeader'),
            padding: kPaddingSmallT,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: isMine
                      ? null
                      : () => context.read<ScreenCubit>().showProfile(
                          commitment.user.id,
                        ),
                  child: Padding(
                    padding: const EdgeInsets.only(right: kSpacingMedium),
                    child: PlainMiniAvatar(profile: commitment.user),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    isMine
                                        ? l10n.labelMe
                                        : commitment.user.title,
                                    style: theme.textTheme.headlineMedium,
                                  ),
                                ),
                                if (isWithdrawn) ...[
                                  const SizedBox(width: kSpacingSmall),
                                  BeaconCardPill(
                                    label: l10n.labelWithdrawn,
                                    backgroundColor:
                                        theme.colorScheme.errorContainer,
                                    foregroundColor:
                                        theme.colorScheme.onErrorContainer,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Text(
                            dateFormatYMD(dateShown),
                            style: theme.textTheme.labelSmall,
                          ),
                        ],
                      ),
                      Padding(
                        padding: kPaddingSmallT,
                        child: ShowMoreText(
                          commitment.message,
                          style: ShowMoreText.buildTextStyle(context).copyWith(
                            color: isWithdrawn
                                ? theme.colorScheme.onSurfaceVariant
                                : null,
                          ),
                          colorClickableText: theme.colorScheme.primary,
                        ),
                      ),
                      if (commitment.isEdited)
                        Padding(
                          padding: kPaddingSmallT,
                          child: Text(
                            l10n.labelEdited,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      if (helpTypeLabel(l10n, commitment.helpType) != null)
                        Padding(
                          padding: kPaddingSmallT,
                          child: BeaconCardPill(
                            label: helpTypeLabel(
                              l10n,
                              commitment.helpType,
                            )!,
                            backgroundColor:
                                theme.colorScheme.surfaceContainerHigh,
                            foregroundColor: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      if (coordinationResponseLabel(
                            l10n,
                            commitment.coordinationResponse,
                          ) !=
                          null)
                        Padding(
                          padding: kPaddingSmallT,
                          child: Text(
                            coordinationResponseLabel(
                              l10n,
                              commitment.coordinationResponse,
                            )!,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      if (isWithdrawn &&
                          uncommitReasonLabel(
                                l10n,
                                commitment.uncommitReason,
                              ) !=
                              null)
                        Padding(
                          padding: kPaddingSmallT,
                          child: Text(
                            uncommitReasonLabel(
                              l10n,
                              commitment.uncommitReason,
                            )!,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (isAuthorView &&
                    onAuthorTapCoordination != null &&
                    !isWithdrawn)
                  IconButton(
                    tooltip: l10n.labelSetCoordinationResponse,
                    icon: const Icon(Icons.flag_outlined, size: 20),
                    onPressed: onAuthorTapCoordination,
                  ),
                if (isMine && onEdit != null)
                  IconButton(
                    icon: const Icon(Icons.edit, size: 18),
                    onPressed: onEdit,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
