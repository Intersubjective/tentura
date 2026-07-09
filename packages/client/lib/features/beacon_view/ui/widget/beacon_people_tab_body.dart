import 'dart:async';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:flutter/material.dart';

import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/domain/entity/beacon_people_lens.dart';
import 'package:tentura/domain/entity/beacon_people_row.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/dialog/help_offer_admission_reason_dialog.dart';
import 'package:tentura/features/beacon_view/ui/dialog/help_offer_message_dialog.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_accordion_sections.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_view_app_bar_overflow.dart';
import 'package:tentura/features/beacon_view/ui/widget/help_offer_tile.dart';
import 'package:tentura/features/beacon_view/ui/widget/unified_forward_row.dart';
import 'package:tentura/features/evaluation/ui/widget/beacon_evaluation_hooks.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/accordion_expansion.dart';
import 'package:tentura/ui/widget/focus_flash_highlight.dart';

class BeaconPeopleTabBody extends StatelessWidget {
  const BeaconPeopleTabBody({
    required this.state,
    required this.beaconViewCubit,
    required this.l10n,
    this.focusUserId,
    super.key,
  });

  final BeaconViewState state;
  final BeaconViewCubit beaconViewCubit;
  final L10n l10n;

  /// When set, the matching participant card is scrolled into view and flashed.
  final String? focusUserId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final beacon = state.beacon;
    final focusUid = focusUserId?.trim();
    final hasFocus = focusUid != null && focusUid.isNotEmpty;
    Widget focusWrap(String userId, Widget child) => FocusFlashHighlight(
      active: hasFocus && userId == focusUid,
      child: child,
    );
    final withdrawn = state.helpOffers
        .where((c) => c.isWithdrawn)
        .toList(growable: false);

    final helpOfferInputs = state.helpOffers
        .map(
          (c) => BeaconPeopleHelpOfferInput(
            userId: c.user.id,
            profile: c.user,
            isWithdrawn: c.isWithdrawn,
            roomAccess: c.roomAccess,
            coordinationResponse: c.coordinationResponse,
            admissionAction: c.admissionAction,
            lastDeclineReason: c.lastDeclineReason,
            lastRemoveReason: c.lastRemoveReason,
          ),
        )
        .toList(growable: false);

    final sections = classifyBeaconPeopleSections(
      beacon: beacon,
      helpOffers: helpOfferInputs,
      roomParticipants: state.roomParticipants,
      viewerUserId: state.myProfile.id,
    );

    final showWithdrawn = withdrawn.isNotEmpty;
    final requestedSectionId = peopleTabAccordionSectionId(
      sections: sections,
      focusUserId: focusUserId,
      showWithdrawn: showWithdrawn,
    );

    TimelineHelpOffer helpOfferForRow(BeaconPeopleRow row) {
      for (final c in state.helpOffers) {
        if (c.user.id == row.userId && !c.isWithdrawn) return c;
      }
      return TimelineHelpOffer(
        user: row.profile,
        message: '',
        createdAt: beacon.createdAt,
        updatedAt: row.participant?.updatedAt ?? beacon.updatedAt,
      );
    }

    HelpOfferTile peopleTile(BeaconPeopleRow row) {
      final c = helpOfferForRow(row);
      final isMine = row.userId == state.myProfile.id;
      final canManageOffer =
          beacon.status.isOpenFamily &&
          !row.isAuthor &&
          !isMine &&
          state.isAuthorOrSteward &&
          !c.isWithdrawn &&
          state.helpOffers.any(
            (ho) => ho.user.id == row.userId && !ho.isWithdrawn,
          );
      return HelpOfferTile(
        helpOffer: c,
        beaconId: beacon.id,
        beaconAuthor: beacon.author,
        beaconAuthorId: beacon.author.id,
        isMine: isMine,
        isAuthorView: state.isAuthorOrSteward && !isMine,
        participant: row.participant,
        showAuthorStar: row.isAuthor,
        onAccept: canManageOffer
            ? () => unawaited(
                beaconViewCubit.acceptHelpOffer(offerUserId: row.userId),
              )
            : null,
        onDecline: canManageOffer
            ? () async {
                final reason = await HelpOfferAdmissionReasonDialog.show(
                  context,
                  title: l10n.helpOfferDeclineDialogTitle,
                  hintText: l10n.helpOfferDeclineDialogHint,
                );
                if (reason != null && context.mounted) {
                  await beaconViewCubit.declineHelpOffer(
                    offerUserId: row.userId,
                    reason: reason,
                  );
                }
              }
            : null,
        onRemoveFromChat: canManageOffer
            ? () async {
                final reason = await HelpOfferAdmissionReasonDialog.show(
                  context,
                  title: l10n.helpOfferRemoveDialogTitle,
                  hintText: l10n.helpOfferRemoveDialogHint,
                );
                if (reason != null && context.mounted) {
                  await beaconViewCubit.removeFromRoom(
                    offerUserId: row.userId,
                    reason: reason,
                  );
                }
              }
            : null,
        onEdit: row.userId == state.myProfile.id && !c.isWithdrawn
            ? () async {
                await beaconViewRunEditHelpOfferDialog(
                  context,
                  beaconViewCubit,
                  l10n,
                );
              }
            : null,
        onWithdraw:
            row.userId == state.myProfile.id &&
                !c.isWithdrawn &&
                beacon.allowsWithdrawWhileHelpOffered
            ? () async {
                final outcome = await HelpOfferMessageDialog.show(
                  context,
                  title: l10n.dialogWithdrawHelpOfferTitle,
                  hintText: l10n.hintWithdrawReason,
                  allowEmptyMessage: true,
                  requireWithdrawReason: true,
                );
                if (outcome?.withdrawReasonWire != null && context.mounted) {
                  await beaconViewCubit.withdraw(
                    message: outcome!.message,
                    withdrawReason: outcome.withdrawReasonWire!,
                  );
                }
              }
            : null,
      );
    }

    Widget peopleSectionFold({
      required String sectionId,
      required String title,
      required List<BeaconPeopleRow> rows,
      required bool initiallyExpanded,
    }) {
      if (rows.isEmpty) return const SizedBox.shrink();
      return AccordionExpansionTile(
        id: sectionId,
        initiallyExpanded: initiallyExpanded,
        title: Text(
          '$title (${rows.length})',
          style: theme.textTheme.titleSmall,
        ),
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i != 0) const SizedBox(height: 12),
            focusWrap(rows[i].userId, peopleTile(rows[i])),
          ],
        ],
      );
    }

    final sectionHeaderStyle = theme.textTheme.titleSmall!.copyWith(
      color: theme.colorScheme.onSurface,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (beacon.status == BeaconStatus.closed) ...[
          BeaconEvaluationHooks(
            beaconId: beacon.id,
            status: beacon.status,
          ),
          const SizedBox(height: 12),
        ],
        AccordionExpansionGroup(
          initialExpandedId: requestedSectionId,
          requestedExpandedId: requestedSectionId,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              peopleSectionFold(
                sectionId: BeaconPeopleAccordionSection.activeHelpers,
                title: l10n.beaconPeopleLensActiveHelpersHeading,
                rows: sections.activeHelpers,
                initiallyExpanded: true,
              ),
              if (sections.activeHelpers.isNotEmpty &&
                  (sections.willingToHelp.isNotEmpty ||
                      sections.notFitting.isNotEmpty))
                const SizedBox(height: 8),
              peopleSectionFold(
                sectionId: BeaconPeopleAccordionSection.willingToHelp,
                title: l10n.beaconPeopleLensWillingToHelpHeading,
                rows: sections.willingToHelp,
                initiallyExpanded: true,
              ),
              if (sections.willingToHelp.isNotEmpty &&
                  sections.notFitting.isNotEmpty)
                const SizedBox(height: 8),
              peopleSectionFold(
                sectionId: BeaconPeopleAccordionSection.notFitting,
                title: l10n.beaconPeopleLensNotFittingHeading,
                rows: sections.notFitting,
                initiallyExpanded: false,
              ),
              if (showWithdrawn) ...[
                const SizedBox(height: 8),
                AccordionExpansionTile(
                  id: BeaconPeopleAccordionSection.withdrawn,
                  title: Text(l10n.beaconShowWithdrawn(withdrawn.length)),
                  children: [
                    for (var j = 0; j < withdrawn.length; j++) ...[
                      if (j != 0) const SizedBox(height: 12),
                      HelpOfferTile(
                        helpOffer: withdrawn[j],
                        beaconId: beacon.id,
                        beaconAuthor: beacon.author,
                        beaconAuthorId: beacon.author.id,
                        isMine: withdrawn[j].user.id == state.myProfile.id,
                        isAuthorView: state.isAuthorOrSteward,
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (state.forwardsLoaded) ...[
          Builder(
            builder: (context) {
              final edges = state.viewerForwardEdges;
              final hasAny = edges.isNotEmpty;
              final viewerId = state.myProfile.id;
              final feedRows = <Widget>[
                for (final e in edges)
                  e.sender.id == viewerId
                      ? UnifiedForwardRow.outgoing(
                          edge: e,
                          viewerUserId: viewerId,
                          helpOffered: state.involvementHelpOfferedIds,
                          watching: state.involvementWatchingIds,
                          onward: state.involvementOnwardForwarderIds,
                          reasonSlugs:
                              state
                                  .forwardReasonSlugs['${e.sender.id}__${e.recipient.id}'] ??
                              const [],
                        )
                      : UnifiedForwardRow.inbound(
                          sender: e.sender,
                          note: e.note,
                          viewerUserId: viewerId,
                          reasonSlugs:
                              state
                                  .forwardReasonSlugs['${e.sender.id}__${e.recipient.id}'] ??
                              const [],
                        ),
              ];
              if (hasAny) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${l10n.labelForwards} (${edges.length})',
                      style: sectionHeaderStyle,
                    ),
                    const SizedBox(height: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < feedRows.length; i++) ...[
                          if (i > 0) const SizedBox(height: kSpacingMedium),
                          feedRows[i],
                        ],
                      ],
                    ),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${l10n.labelForwards} (0)',
                    style: sectionHeaderStyle,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.beaconForwardsEmpty,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              );
            },
          ),
        ] else if (state.forwardsLoading)
          const Center(
            child: Padding(
              padding: kPaddingSmallV,
              child: CircularProgressIndicator.adaptive(),
            ),
          )
        else
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.forward_to_inbox),
              label: Text(l10n.beaconPeopleShowForwards),
              onPressed: () => unawaited(beaconViewCubit.loadForwards()),
            ),
          ),
      ],
    );
  }
}
