import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/features/beacon/ui/widget/coordination_ui.dart';
import 'package:tentura/ui/widget/self_user_highlight.dart';

import 'commitment_avatar.dart';
import 'commitment_tokens.dart';
import '../bloc/beacon_view_state.dart';

// TODO(contract): [CommitmentState] inProgress / done when backend exposes lifecycle;
// for now only Active / Withdrawn are shown (see TimelineCommitment).
// TODO(contract): [CommitmentOfferType] wire keys vs product enum — map helpType strings when schema aligns.

/// Compact commitment row: technical / minimal, no pill badges, no filled in-card actions.
class CommitmentTile extends StatelessWidget {
  const CommitmentTile({
    required this.commitment,
    this.isMine = false,
    this.onEdit,
    this.onWithdraw,
    this.isAuthorView = false,
    this.onAuthorTapCoordination,
    super.key,
  });

  final TimelineCommitment commitment;
  final bool isMine;
  final VoidCallback? onEdit;
  final VoidCallback? onWithdraw;
  final bool isAuthorView;
  final VoidCallback? onAuthorTapCoordination;

  static const double _cardRadius = 12;
  static const double _contentGap = 10;
  static const double _rowGap = 12;

  Color _authorLabelColor(CommitmentToneColors t, CoordinationResponseType r) {
    return switch (r) {
      CoordinationResponseType.useful => t.good,
      CoordinationResponseType.needCoordination => t.warning,
      CoordinationResponseType.overlapping => t.info,
      CoordinationResponseType.needDifferentSkill => t.danger,
      CoordinationResponseType.notSuitable => t.danger,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final tones = CommitmentToneColors.of(context);
    final isWithdrawn = commitment.isWithdrawn;
    final opacity = isWithdrawn ? 0.55 : 1.0;
    final dateShown = isWithdrawn ? commitment.updatedAt : commitment.createdAt;
    final coordinationLabel = coordinationResponseLabel(
      l10n,
      commitment.coordinationResponse,
    );
    final offerLabel = helpTypeLabel(l10n, commitment.helpType);
    final borderColor = isMine ? tones.cardBorderMine : tones.cardBorder;
    // Active / Withdrawn only (spec allows more states later).
    final stateCaption =
        isWithdrawn ? l10n.labelWithdrawn : l10n.beaconsFilterActive;

    return Opacity(
      opacity: opacity,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(_cardRadius),
          border: Border.all(color: borderColor),
          boxShadow: kCommitmentCardShadows(context),
        ),
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
                  child: CommitmentAvatar(profile: commitment.user),
                ),
                const SizedBox(width: _contentGap),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                );
                              },
                            ),
                            if (isMine) ...[
                              const SizedBox(height: 2),
                              Text(
                                l10n.commitmentsTabMineLabel,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: tones.mine,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                            const SizedBox(height: 2),
                            Text(
                              '${dateFormatYMD(dateShown.toLocal())} · ${timeFormatHm(dateShown.toLocal())}'
                              '${commitment.isEdited ? ' · ${l10n.labelEdited}' : ''}',
                              style: kCommitmentMonoTimestamp(
                                context,
                                tones.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        stateCaption,
                        style: kCommitmentMonoStatus(
                          context,
                          isWithdrawn ? tones.danger : tones.neutral,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (offerLabel != null) ...[
              const SizedBox(height: _rowGap),
              Text(
                offerLabel.toUpperCase(),
                style: kCommitmentMonoOfferType(
                  context,
                  tones.neutral,
                ),
              ),
            ],
            if (commitment.message.isNotEmpty) ...[
              if (offerLabel == null) const SizedBox(height: _rowGap),
              if (offerLabel != null) const SizedBox(height: 6),
              Text(
                commitment.message,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 13,
                  height: 20 / 13,
                ),
              ),
            ],
            if (!isWithdrawn &&
                (coordinationLabel != null ||
                    (isAuthorView && onAuthorTapCoordination != null))) ...[
              const SizedBox(height: _rowGap),
              Divider(
                height: 1,
                thickness: 1,
                color: borderColor,
              ),
              const SizedBox(height: 8),
              _AuthorFooter(
                l10n: l10n,
                tones: tones,
                coordinationLabel: coordinationLabel,
                responseType: commitment.coordinationResponse,
                authorLabelColor: commitment.coordinationResponse != null
                    ? _authorLabelColor(
                        tones,
                        commitment.coordinationResponse!,
                      )
                    : tones.muted,
                isAuthorView: isAuthorView,
                onAuthorTapCoordination: onAuthorTapCoordination,
              ),
            ],
            if (isMine && !isWithdrawn && (onEdit != null || onWithdraw != null))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    if (onEdit != null)
                      TextButton(
                        onPressed: onEdit,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          minimumSize: const Size(44, 44),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          l10n.commitmentsTabActionEdit,
                          style: kCommitmentMonoAction(context, tones.mine),
                        ),
                      ),
                    if (onEdit != null && onWithdraw != null)
                      const SizedBox(width: 4),
                    if (onWithdraw != null)
                      TextButton(
                        onPressed: onWithdraw,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          minimumSize: const Size(44, 44),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          l10n.commitmentsTabActionWithdraw,
                          style: kCommitmentMonoAction(
                            context,
                            tones.danger,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            if (isWithdrawn &&
                uncommitReasonLabel(l10n, commitment.uncommitReason) !=
                    null) ...[
              const SizedBox(height: 8),
              Text(
                uncommitReasonLabel(l10n, commitment.uncommitReason)!,
                style: kCommitmentMonoCaption(
                  context,
                  tones.muted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AuthorFooter extends StatelessWidget {
  const _AuthorFooter({
    required this.l10n,
    required this.tones,
    required this.coordinationLabel,
    required this.responseType,
    required this.authorLabelColor,
    required this.isAuthorView,
    required this.onAuthorTapCoordination,
  });

  final L10n l10n;
  final CommitmentToneColors tones;
  final String? coordinationLabel;
  final CoordinationResponseType? responseType;
  final Color authorLabelColor;
  final bool isAuthorView;
  final VoidCallback? onAuthorTapCoordination;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: RichText(
            text: TextSpan(
              style: kCommitmentMonoCaption(
                context,
                tones.muted,
              ),
              children: [
                TextSpan(
                  text: l10n.commitmentsTabAuthorLabelCaption,
                ),
                if (coordinationLabel != null && responseType != null) ...[
                  const TextSpan(text: '  '),
                  TextSpan(
                    text: coordinationLabel,
                    style: kCommitmentMonoOfferType(
                      context,
                      authorLabelColor,
                    ),
                  ),
                ] else
                  TextSpan(
                    text: ' —',
                    style: kCommitmentMonoCaption(
                      context,
                      tones.muted,
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (isAuthorView && onAuthorTapCoordination != null) ...[
          const SizedBox(width: 6),
          TextButton(
            onPressed: onAuthorTapCoordination,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              minimumSize: const Size(44, 44),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              l10n.labelSetCoordinationResponse,
              style: kCommitmentMonoAction(
                context,
                tones.mine,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ],
    );
  }
}
