import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/features/beacon/ui/widget/coordination_ui.dart';
import 'package:tentura/ui/widget/self_user_highlight.dart';

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

  static const double _contentGap = 10;
  static const double _rowGap = 12;

  Color _authorLabelColor(TenturaTokens tt, CoordinationResponseType r) {
    return switch (r) {
      CoordinationResponseType.useful => tt.good,
      CoordinationResponseType.needCoordination => tt.warn,
      CoordinationResponseType.overlapping => tt.info,
      CoordinationResponseType.needDifferentSkill => tt.danger,
      CoordinationResponseType.notSuitable => tt.danger,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final tt = context.tt;
    final isWithdrawn = commitment.isWithdrawn;
    final opacity = isWithdrawn ? 0.55 : 1.0;
    final dateShown = isWithdrawn ? commitment.updatedAt : commitment.createdAt;
    final coordinationLabel = coordinationResponseLabel(
      l10n,
      commitment.coordinationResponse,
    );
    final offerLabel = helpTypeLabel(l10n, commitment.helpType);
    // Active / Withdrawn only (spec allows more states later).
    final stateCaption =
        isWithdrawn ? l10n.labelWithdrawn : l10n.beaconsFilterActive;

    return Opacity(
      opacity: opacity,
      child: TenturaTechCardStatic(
        isOwned: isMine,
        showShadow: true,
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
                  child: TenturaAvatar(profile: commitment.user),
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
                                  style: theme.textTheme.titleSmall!.copyWith(
                                    color: theme.colorScheme.onSurface,
                                  ),
                                );
                              },
                            ),
                            if (isMine) ...[
                              const SizedBox(height: 2),
                              TenturaStatusText(
                                l10n.commitmentsTabMineLabel,
                                tone: TenturaTone.info,
                              ),
                            ],
                            const SizedBox(height: 2),
                            TenturaMetaText(
                              '${dateFormatYMD(dateShown.toLocal())} · ${timeFormatHm(dateShown.toLocal())}'
                              '${commitment.isEdited ? ' · ${l10n.labelEdited}' : ''}',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      if (isWithdrawn)
                        TenturaStatusText(
                          stateCaption,
                          tone: TenturaTone.danger,
                        )
                      else
                        TenturaStatusText(stateCaption),
                    ],
                  ),
                ),
              ],
            ),
            if (offerLabel != null) ...[
              const SizedBox(height: _rowGap),
              TenturaTypeLabel(offerLabel),
            ],
            if (commitment.message.isNotEmpty) ...[
              if (offerLabel == null) const SizedBox(height: _rowGap),
              if (offerLabel != null) const SizedBox(height: 6),
              Text(
                commitment.message,
                style: TenturaText.body(theme.colorScheme.onSurface),
              ),
            ],
            if (!isWithdrawn &&
                (coordinationLabel != null ||
                    (isAuthorView && onAuthorTapCoordination != null))) ...[
              const SizedBox(height: _rowGap),
              const TenturaHairlineDivider(subtle: false),
              const SizedBox(height: 8),
              _AuthorFooter(
                l10n: l10n,
                tt: tt,
                coordinationLabel: coordinationLabel,
                responseType: commitment.coordinationResponse,
                authorLabelColor: commitment.coordinationResponse != null
                    ? _authorLabelColor(
                        tt,
                        commitment.coordinationResponse!,
                      )
                    : tt.textMuted,
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
                      TenturaTextAction(
                        label: l10n.commitmentsTabActionEdit,
                        onPressed: onEdit,
                      ),
                    if (onEdit != null && onWithdraw != null)
                      const SizedBox(width: 4),
                    if (onWithdraw != null)
                      TenturaTextAction(
                        label: l10n.commitmentsTabActionWithdraw,
                        onPressed: onWithdraw,
                        tone: TenturaTone.danger,
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
                style: TenturaText.bodySmall(tt.textMuted),
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
    required this.tt,
    required this.coordinationLabel,
    required this.responseType,
    required this.authorLabelColor,
    required this.isAuthorView,
    required this.onAuthorTapCoordination,
  });

  final L10n l10n;
  final TenturaTokens tt;
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
              style: TenturaText.bodySmall(tt.textMuted),
              children: [
                TextSpan(
                  text: l10n.commitmentsTabAuthorLabelCaption,
                ),
                if (coordinationLabel != null && responseType != null) ...[
                  const TextSpan(text: '  '),
                  TextSpan(
                    text: coordinationLabel,
                    style: TenturaText.typeLabel(authorLabelColor),
                  ),
                ] else
                  TextSpan(
                    text: ' —',
                    style: TenturaText.bodySmall(tt.textMuted),
                  ),
              ],
            ),
          ),
        ),
        if (isAuthorView && onAuthorTapCoordination != null) ...[
          const SizedBox(width: 6),
          TenturaTextAction(
            label: l10n.labelSetCoordinationResponse,
            onPressed: onAuthorTapCoordination,
          ),
        ],
      ],
    );
  }
}
