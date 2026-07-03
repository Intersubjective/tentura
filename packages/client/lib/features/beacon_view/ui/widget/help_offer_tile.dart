import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_people_labels.dart';
import 'package:tentura/ui/widget/self_aware_profile_avatar.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/features/beacon/ui/widget/coordination_ui.dart';
import 'package:tentura/features/capability/ui/widget/forward_capability_chips.dart';
import 'package:tentura/ui/widget/self_user_highlight.dart';

import '../bloc/beacon_view_state.dart';

// TODO(contract): [HelpOfferState] inProgress / done when backend exposes lifecycle;
// for now only withdrawn is labeled in-row; active helpOffers have no status chip.
// TODO(contract): [HelpOfferType] wire keys vs product enum — map helpType strings when schema aligns.

/// Compact helpOffer row: technical / minimal; capability help_type as read-only chips.
class HelpOfferTile extends StatelessWidget {
  const HelpOfferTile({
    required this.helpOffer,
    required this.beaconId,
    required this.beaconAuthor,
    required this.beaconAuthorId,
    this.isMine = false,
    this.onEdit,
    this.onWithdraw,
    this.isAuthorView = false,
    this.onAuthorTapCoordination,
    this.participant,
    this.showAuthorStar = false,
    super.key,
  });

  final TimelineHelpOffer helpOffer;
  final String beaconId;
  final Profile beaconAuthor;
  final String beaconAuthorId;
  final bool isMine;
  final VoidCallback? onEdit;
  final VoidCallback? onWithdraw;
  final bool isAuthorView;
  final VoidCallback? onAuthorTapCoordination;
  final BeaconParticipant? participant;
  final bool showAuthorStar;

  static const double _contentGap = 10;
  static const double _rowGap = 12;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final tt = context.tt;
    final isWithdrawn = helpOffer.isWithdrawn;
    final dateShown = isWithdrawn ? helpOffer.updatedAt : helpOffer.createdAt;
    final coordinationLabel = coordinationResponseLabel(
      l10n,
      helpOffer.coordinationResponse,
    );
    final helpTypeSlugs = helpOfferTypeSlugs(helpOffer.helpType);
    final showHelpTypeChips = helpTypeSlugs.isNotEmpty;
    final showForwardPathButton =
        !isWithdrawn && helpOffer.user.id != beaconAuthorId;
    final participantMeta = participant;
    final nextMove = participantMeta?.nextMoveText?.trim();
    final locale = Localizations.localeOf(context).toString();
    final participantUpdated = participantMeta == null
        ? null
        : DateFormat.yMMMd(locale)
            .add_Hm()
            .format(participantMeta.updatedAt.toLocal());

    final avatarWidget = SelfAwareAvatar.medium(
      profile: helpOffer.user,
      showAuthorStar: showAuthorStar,
    );

    return TenturaTechCardStatic(
      isOwned: isMine && !isWithdrawn,
      showShadow: !isWithdrawn,
      surfaceOverride: isWithdrawn ? tt.bg : null,
      borderOverride: isWithdrawn ? tt.borderSubtle : null,
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
                        helpOffer.user.id,
                      ),
                child: avatarWidget,
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
                              final titleSmall = theme.textTheme.titleSmall!;
                              final isSelf = SelfUserHighlight.profileIsSelf(
                                helpOffer.user,
                                state.profile.id,
                              );
                              return Text(
                                SelfUserHighlight.displayName(
                                  l10n,
                                  helpOffer.user,
                                  state.profile.id,
                                ),
                                style: isSelf
                                    ? SelfUserHighlight.nameStyle(
                                        theme,
                                        titleSmall,
                                        true,
                                      )
                                    : titleSmall.copyWith(
                                        color: theme.colorScheme.onSurface,
                                      ),
                              );
                            },
                          ),
                          const SizedBox(height: 2),
                          if (participantMeta != null) ...[
                            Text(
                              '${beaconPeopleRoleLabel(l10n, participantMeta.role)} · ${beaconPeopleStatusLabel(l10n, participantMeta.status, helpOffer.coordinationResponse)}',
                              style: TenturaText.status(
                                theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 2),
                          ] else if (showAuthorStar) ...[
                            Text(
                              beaconPeopleRoleLabel(
                                l10n,
                                BeaconParticipantRoleBits.author,
                              ),
                              style: TenturaText.status(
                                theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 2),
                          ],
                          TenturaMetaText(
                            '${dateFormatYMD(dateShown.toLocal())} · ${timeFormatHm(dateShown.toLocal())}'
                            '${helpOffer.isEdited ? ' · ${l10n.labelEdited}' : ''}',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                      if (isWithdrawn)
                        TenturaStatusText(l10n.labelWithdrawn),
                  ],
                ),
              ),
              if (showForwardPathButton)
                IconButton(
                  icon: const Icon(TenturaIcons.graph),
                  tooltip: l10n.helpOffererForwardPathTooltip,
                  onPressed: () =>
                      context.read<ScreenCubit>().showHelpOffererForwardPathFor(
                        beaconId: beaconId,
                        helpOffererId: helpOffer.user.id,
                        helpOffererName: helpOffer.user.shownName,
                      ),
                ),
            ],
          ),
          if (showHelpTypeChips) ...[
            const SizedBox(height: _rowGap),
            ForwardCapabilityChips(slugs: helpTypeSlugs),
          ],
          if (helpOffer.message.isNotEmpty) ...[
            if (!showHelpTypeChips) const SizedBox(height: _rowGap),
            if (showHelpTypeChips) const SizedBox(height: 6),
            Text(
              helpOffer.message,
              style: TenturaText.body(theme.colorScheme.onSurface),
            ),
          ],
          if (nextMove != null && nextMove.isNotEmpty) ...[
            const SizedBox(height: _rowGap),
            Text(
              nextMove,
              style: TenturaText.bodySmall(theme.colorScheme.onSurface),
            ),
          ],
          if (participantUpdated != null) ...[
            const SizedBox(height: 6),
            Text(
              l10n.beaconPeopleParticipantUpdated(participantUpdated),
              style: TenturaText.status(theme.colorScheme.onSurfaceVariant),
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
              beaconAuthor: beaconAuthor,
              coordinationLabel: coordinationLabel,
              responseType: helpOffer.coordinationResponse,
              authorLabelColor: helpOffer.coordinationResponse != null
                  ? coordinationResponseInkColor(
                      tt,
                      helpOffer.coordinationResponse!,
                    )
                  : tt.danger,
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
                      label: l10n.helpOffersTabActionEdit,
                      onPressed: onEdit,
                    ),
                  if (onEdit != null && onWithdraw != null)
                    const SizedBox(width: 4),
                  if (onWithdraw != null)
                    TenturaTextAction(
                      label: l10n.helpOffersTabActionWithdraw,
                      onPressed: onWithdraw,
                      tone: TenturaTone.neutral,
                    ),
                ],
              ),
            ),
          if (isWithdrawn &&
              withdrawReasonLabel(l10n, helpOffer.withdrawReason) != null) ...[
            const SizedBox(height: 8),
            Text(
              withdrawReasonLabel(l10n, helpOffer.withdrawReason)!,
              style: TenturaText.bodySmall(tt.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

class _AuthorFooter extends StatelessWidget {
  const _AuthorFooter({
    required this.l10n,
    required this.tt,
    required this.beaconAuthor,
    required this.coordinationLabel,
    required this.responseType,
    required this.authorLabelColor,
    required this.isAuthorView,
    required this.onAuthorTapCoordination,
  });

  final L10n l10n;
  final TenturaTokens tt;
  final Profile beaconAuthor;
  final String? coordinationLabel;
  final CoordinationResponseType? responseType;
  final Color authorLabelColor;
  final bool isAuthorView;
  final VoidCallback? onAuthorTapCoordination;

  @override
  Widget build(BuildContext context) {
    final hasResponse = coordinationLabel != null && responseType != null;

    return Row(
      children: [
        Expanded(
          child: hasResponse
              ? Row(
                  children: [
                    SelfAwareAvatar.small(
                      profile: beaconAuthor,
                      showAuthorStar: true,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        ' - "$coordinationLabel"',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TenturaText.typeLabel(authorLabelColor),
                      ),
                    ),
                  ],
                )
              : Text(
                  l10n.helpOffersTabNoAuthorLabelYet,
                  style: TenturaText.bodySmall(authorLabelColor),
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
