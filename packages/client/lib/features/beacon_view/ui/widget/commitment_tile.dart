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
import 'package:tentura/ui/widget/show_more_text.dart';

import '../bloc/beacon_view_state.dart';
import 'self_aware_plain_mini_avatar.dart';

/// Committer avatar column width (matches default mini-avatar size + trailing gap).
double _commitmentAvatarColumnWidth() =>
    AvatarRated.sizeSmall + kSpacingMedium;

/// Sits in the avatar column beside author coordination text.
const double _authorReactionAvatarSize = AvatarRated.sizeSmall * 0.55;

class CommitmentTile extends StatelessWidget {
  const CommitmentTile({
    required this.commitment,
    required this.beaconAuthor,
    this.isMine = false,
    this.onEdit,
    this.isAuthorView = false,
    this.onAuthorTapCoordination,
    super.key,
  });

  final TimelineCommitment commitment;
  final Profile beaconAuthor;
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
    final coordinationLabel = coordinationResponseLabel(
      l10n,
      commitment.coordinationResponse,
    );
    final showCoordinationRow = coordinationLabel != null;
    final trailingIconSlots =
        (isAuthorView && onAuthorTapCoordination != null && !isWithdrawn
            ? 1
            : 0) +
        (isMine && onEdit != null ? 1 : 0);
    const kIconButtonWidth = 48.0;
    final trailingIconsWidth = trailingIconSlots * kIconButtonWidth;

    return Opacity(
      opacity: opacity,
      child: Column(
        children: [
          const Divider(),
          Padding(
            key: const Key('CommitmentHeader'),
            padding: kPaddingSmallT,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: _commitmentAvatarColumnWidth(),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: GestureDetector(
                          onTap: isMine
                              ? null
                              : () => context.read<ScreenCubit>().showProfile(
                                  commitment.user.id,
                                ),
                          child: SelfAwarePlainMiniAvatar(profile: commitment.user),
                        ),
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
                                  child: BlocBuilder<ProfileCubit, ProfileState>(
                                    buildWhen: (p, c) =>
                                        p.profile.id != c.profile.id,
                                    builder: (context, state) {
                                      final isSelf =
                                          SelfUserHighlight.profileIsSelf(
                                        commitment.user,
                                        state.profile.id,
                                      );
                                      return Text(
                                        SelfUserHighlight.displayName(
                                          l10n,
                                          commitment.user,
                                          state.profile.id,
                                        ),
                                        style: SelfUserHighlight.nameStyle(
                                          theme,
                                          theme.textTheme.headlineMedium,
                                          isSelf,
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                    if (isWithdrawn) ...[
                                      const SizedBox(width: kSpacingSmall),
                                      BeaconCardPill(
                                        label: l10n.labelWithdrawn,
                                        backgroundColor:
                                            theme.colorScheme.errorContainer,
                                        foregroundColor: theme
                                            .colorScheme.onErrorContainer,
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
                              style:
                                  ShowMoreText.buildTextStyle(context).copyWith(
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
                                foregroundColor:
                                    theme.colorScheme.onSurfaceVariant,
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
                if (showCoordinationRow)
                  Padding(
                    padding: kPaddingSmallT,
                    child: Row(
                      children: [
                        SizedBox(
                          width: _commitmentAvatarColumnWidth(),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: GestureDetector(
                              onTap: () => context
                                  .read<ScreenCubit>()
                                  .showProfile(beaconAuthor.id),
                              child: SelfAwarePlainMiniAvatar(
                                profile: beaconAuthor,
                                size: _authorReactionAvatarSize,
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer
                                  .withValues(alpha: 0.72),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: theme.colorScheme.primary
                                    .withValues(alpha: 0.35),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              child: Text(
                                coordinationLabel,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color:
                                      theme.colorScheme.onPrimaryContainer,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: trailingIconsWidth),
                      ],
                    ),
                  ),
                if (isWithdrawn &&
                    uncommitReasonLabel(l10n, commitment.uncommitReason) !=
                        null)
                  Padding(
                    padding: kPaddingSmallT,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: _commitmentAvatarColumnWidth()),
                        Expanded(
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}
