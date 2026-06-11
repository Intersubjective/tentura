import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/domain/entity/beacon_people_lens.dart';
import 'package:tentura/domain/entity/beacon_people_row.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/beacon_view/ui/dialog/help_offer_message_dialog.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_accordion_sections.dart';
import 'package:tentura/features/beacon_view/ui/util/help_offer_types_wire.dart';
import 'package:tentura/features/beacon_view/ui/widget/coordination_response_bottom_sheet.dart';
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
      return HelpOfferTile(
        helpOffer: c,
        beaconId: beacon.id,
        beaconAuthor: beacon.author,
        beaconAuthorId: beacon.author.id,
        isMine: row.userId == state.myProfile.id,
        isAuthorView: state.isAuthorOrSteward,
        participant: row.participant,
        showAuthorStar: row.isAuthor,
        onAuthorTapCoordination: !row.isAuthor &&
                state.isAuthorOrSteward &&
                !c.isWithdrawn &&
                state.helpOffers.any(
                  (ho) => ho.user.id == row.userId && !ho.isWithdrawn,
                )
            ? () => unawaited(
                showCoordinationResponseBottomSheet(
                  context: context,
                  offerUserTitle: row.profile.displayName,
                  initialResponse: c.coordinationResponse,
                  offerUserAdmittedToRoom: state.roomParticipants.any(
                    (p) =>
                        p.userId == row.userId &&
                        p.roomAccess == RoomAccessBits.admitted,
                  ),
                  onSave:
                      ({
                        required responseTypeSmallint,
                        required inviteToRoom,
                        required removeFromRoom,
                      }) => beaconViewCubit.setCoordinationResponse(
                        offerUserId: row.userId,
                        responseType: responseTypeSmallint,
                        inviteToRoom: inviteToRoom,
                        removeFromRoom: removeFromRoom,
                      ),
                ),
              )
            : null,
        onEdit: row.userId == state.myProfile.id && !c.isWithdrawn
            ? () async {
                final outcome = await HelpOfferMessageDialog.show(
                  context,
                  title: l10n.beaconHeaderUpdateHelpOffer,
                  hintText: l10n.hintOfferHelpMessage,
                  initialText: c.message,
                  allowEmptyMessage: true,
                  showHelpTypeChips: true,
                  initialHelpTypeSlugs: helpOfferStoredHelpTypeSlugs(
                    c.helpType,
                  ),
                  automaticSlugs: beacon.needs,
                );
                if (outcome != null && context.mounted) {
                  await beaconViewCubit.offerHelp(
                    message: outcome.message,
                    helpTypes: normalizeOfferHelpTypesWire(
                      outcome.helpTypesWire,
                    ),
                  );
                }
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
        BeaconEvaluationHooks(
          beaconId: beacon.id,
          lifecycle: beacon.lifecycle,
        ),
        const SizedBox(height: 12),
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
                  initiallyExpanded: false,
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
                          reasonSlugs: state.forwardReasonSlugs[
                                  '${e.sender.id}__${e.recipient.id}'] ??
                              const [],
                        )
                      : UnifiedForwardRow.inbound(
                          sender: e.sender,
                          note: e.note,
                          viewerUserId: viewerId,
                          reasonSlugs: state.forwardReasonSlugs[
                                  '${e.sender.id}__${e.recipient.id}'] ??
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
                          if (i > 0) SizedBox(height: kSpacingMedium),
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
          Center(
            child: Padding(
              padding: kPaddingSmallV,
              child: const CircularProgressIndicator.adaptive(),
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
