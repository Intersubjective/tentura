import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/help_offer_admission_action.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon/ui/widget/coordination_ui.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_people_labels.dart';
import 'package:tentura/ui/widget/self_aware_profile_avatar.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/features/capability/ui/widget/forward_capability_chips.dart';
import 'package:tentura/ui/widget/self_user_highlight.dart';
import 'package:tentura/ui/widget/show_more_text.dart';
import 'package:tentura/ui/widget/url_link_annotations.dart';

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
    this.onAccept,
    this.onDecline,
    this.onRemoveFromChat,
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
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;
  final VoidCallback? onRemoveFromChat;
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
    final roomAccess = helpOffer.roomAccess ?? participant?.roomAccess;
    final isAdmitted = roomAccess == RoomAccessBits.admitted;
    final helpTypeSlugs = helpOfferTypeSlugs(helpOffer.helpType);
    final showHelpTypeChips = helpTypeSlugs.isNotEmpty;
    final showForwardPathButton =
        !isWithdrawn && helpOffer.user.id != beaconAuthorId;
    final participantMeta = participant;
    final nextMove = participantMeta?.nextMoveText?.trim();
    final locale = Localizations.localeOf(context).toString();
    final participantUpdated = participantMeta == null
        ? null
        : DateFormat.yMMMd(
            locale,
          ).add_Hm().format(participantMeta.updatedAt.toLocal());

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
                              '${beaconPeopleRoleLabel(l10n, participantMeta.role)} · ${beaconPeopleStatusLabel(
                                l10n,
                                participantMeta.status,
                                helpOffer.coordinationResponse,
                                admissionAction: helpOffer.admissionAction,
                              )}',
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
                    if (isWithdrawn) TenturaStatusText(l10n.labelWithdrawn),
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
            ShowMoreText(
              helpOffer.message,
              style: TenturaText.body(theme.colorScheme.onSurface),
              colorClickableText: theme.colorScheme.primary,
              annotations: buildUrlAnnotations(linkColor: tt.info),
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
          if (!isWithdrawn && !showAuthorStar) ...[
            const SizedBox(height: _rowGap),
            const TenturaHairlineDivider(subtle: false),
            const SizedBox(height: 8),
            _AdmissionFooter(
              l10n: l10n,
              tt: tt,
              isAdmitted: isAdmitted,
              admissionAction: helpOffer.admissionAction,
              lastDeclineReason: helpOffer.lastDeclineReason,
              lastRemoveReason: helpOffer.lastRemoveReason,
              isAuthorView: isAuthorView,
              isMine: isMine,
              onAccept: onAccept,
              onDecline: onDecline,
              onRemoveFromChat: onRemoveFromChat,
            ),
          ],
          if (isMine && !isWithdrawn && (onEdit != null || onWithdraw != null))
            Padding(
              padding: EdgeInsets.only(top: tt.tightGap),
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

class _AdmissionFooter extends StatelessWidget {
  const _AdmissionFooter({
    required this.l10n,
    required this.tt,
    required this.isAdmitted,
    required this.admissionAction,
    required this.lastDeclineReason,
    required this.lastRemoveReason,
    required this.isAuthorView,
    required this.isMine,
    required this.onAccept,
    required this.onDecline,
    required this.onRemoveFromChat,
  });

  final L10n l10n;
  final TenturaTokens tt;
  final bool isAdmitted;
  final HelpOfferAdmissionAction? admissionAction;
  final String? lastDeclineReason;
  final String? lastRemoveReason;
  final bool isAuthorView;
  final bool isMine;
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;
  final VoidCallback? onRemoveFromChat;

  @override
  Widget build(BuildContext context) {
    final reason = switch (admissionAction) {
      HelpOfferAdmissionAction.decline => lastDeclineReason?.trim(),
      HelpOfferAdmissionAction.remove => lastRemoveReason?.trim(),
      _ => null,
    };

    if (isAuthorView) {
      return _AuthorAdmissionFooter(
        l10n: l10n,
        tt: tt,
        isAdmitted: isAdmitted,
        admissionAction: admissionAction,
        reason: reason,
        onAccept: onAccept,
        onDecline: onDecline,
        onRemoveFromChat: onRemoveFromChat,
      );
    }

    if (isMine) {
      return _CommitterAdmissionFooter(
        l10n: l10n,
        tt: tt,
        isAdmitted: isAdmitted,
        admissionAction: admissionAction,
        reason: reason,
      );
    }

    return Text(
      isAdmitted
          ? l10n.helpOfferAdmittedLabel
          : l10n.helpOffersTabNoAuthorLabelYet,
      style: TenturaText.bodySmall(tt.textMuted),
    );
  }
}

class _AuthorAdmissionFooter extends StatelessWidget {
  const _AuthorAdmissionFooter({
    required this.l10n,
    required this.tt,
    required this.isAdmitted,
    required this.admissionAction,
    required this.reason,
    required this.onAccept,
    required this.onDecline,
    required this.onRemoveFromChat,
  });

  final L10n l10n;
  final TenturaTokens tt;
  final bool isAdmitted;
  final HelpOfferAdmissionAction? admissionAction;
  final String? reason;
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;
  final VoidCallback? onRemoveFromChat;

  @override
  Widget build(BuildContext context) {
    if (isAdmitted) {
      final isAutomatic =
          admissionAction == null ||
          admissionAction == HelpOfferAdmissionAction.autoAdmit;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isAutomatic
                      ? l10n.helpOfferAdmittedAutomaticallyLabel
                      : l10n.helpOfferAdmittedLabel,
                  style: TenturaText.bodySmall(tt.textMuted),
                ),
                if (isAutomatic) ...[
                  SizedBox(height: tt.tightGap),
                  Text(
                    l10n.helpOfferAdmittedAutomaticallyHint,
                    style: TenturaText.bodySmall(tt.textFaint),
                  ),
                ],
              ],
            ),
          ),
          if (onRemoveFromChat != null) ...[
            SizedBox(width: tt.rowGap),
            TenturaTextAction(
              label: l10n.helpOfferAdmissionRemove,
              onPressed: onRemoveFromChat,
              tone: TenturaTone.neutral,
            ),
          ],
        ],
      );
    }

    final contextText = switch (admissionAction) {
      HelpOfferAdmissionAction.decline
          when reason != null && reason!.isNotEmpty =>
        l10n.helpOfferPreviousDeclineContext(reason!),
      HelpOfferAdmissionAction.remove
          when reason != null && reason!.isNotEmpty =>
        l10n.helpOfferPreviousRemoveContext(reason!),
      _ => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (contextText != null) ...[
          Text(
            contextText,
            style: TenturaText.bodySmall(tt.textMuted),
          ),
          SizedBox(height: tt.tightGap),
        ],
        Row(
          children: [
            if (onAccept != null)
              TenturaTextAction(
                label: l10n.helpOfferAdmissionAccept,
                onPressed: onAccept,
                tone: TenturaTone.good,
                icon: const Icon(Icons.check_outlined),
              ),
            if (onAccept != null && onDecline != null)
              SizedBox(width: tt.tightGap),
            if (onDecline != null)
              TenturaTextAction(
                label: l10n.helpOfferAdmissionDecline,
                onPressed: onDecline,
                tone: TenturaTone.danger,
                icon: const Icon(Icons.close_outlined),
              ),
          ],
        ),
      ],
    );
  }
}

class _CommitterAdmissionFooter extends StatelessWidget {
  const _CommitterAdmissionFooter({
    required this.l10n,
    required this.tt,
    required this.isAdmitted,
    required this.admissionAction,
    required this.reason,
  });

  final L10n l10n;
  final TenturaTokens tt;
  final bool isAdmitted;
  final HelpOfferAdmissionAction? admissionAction;
  final String? reason;

  @override
  Widget build(BuildContext context) {
    final text = switch (admissionAction) {
      HelpOfferAdmissionAction.decline
          when reason != null && reason!.isNotEmpty =>
        l10n.helpOfferDeclinedWithReason(reason!),
      HelpOfferAdmissionAction.remove
          when reason != null && reason!.isNotEmpty =>
        l10n.helpOfferRemovedWithReason(reason!),
      _ =>
        isAdmitted
            ? l10n.helpOfferAdmittedLabel
            : l10n.helpOffersTabNoAuthorLabelYet,
    };
    final color = switch (admissionAction) {
      HelpOfferAdmissionAction.decline ||
      HelpOfferAdmissionAction.remove => tt.danger,
      _ => tt.textMuted,
    };
    return Text(
      text,
      style: TenturaText.bodySmall(color),
    );
  }
}
