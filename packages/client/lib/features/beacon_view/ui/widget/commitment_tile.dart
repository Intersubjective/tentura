import 'package:flutter/material.dart';

import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/avatar_rated.dart';
import 'package:tentura/ui/widget/show_more_text.dart';

import '../bloc/beacon_view_state.dart';

class CommitmentTile extends StatelessWidget {
  const CommitmentTile({
    required this.commitment,
    this.isMine = false,
    this.onEdit,
    super.key,
  });

  final TimelineCommitment commitment;
  final bool isMine;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final isWithdrawn = commitment.isWithdrawn;
    final opacity = isWithdrawn ? 0.65 : 1.0;
    final dateShown =
        isWithdrawn ? commitment.updatedAt : commitment.createdAt;
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
                    child: AvatarRated.small(profile: commitment.user),
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
                                  Chip(
                                    label: Text(l10n.labelWithdrawn),
                                    labelStyle:
                                        theme.textTheme.labelSmall?.copyWith(
                                      color: theme.colorScheme.error,
                                    ),
                                    visualDensity: VisualDensity.compact,
                                    padding: EdgeInsets.zero,
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    side: BorderSide(
                                      color: theme.colorScheme.error
                                          .withValues(alpha: 0.5),
                                    ),
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
                    ],
                  ),
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
