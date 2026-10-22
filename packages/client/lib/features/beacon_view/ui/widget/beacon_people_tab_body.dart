import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tentura_root/domain/entity/beacon_access.dart';

import 'package:tentura/domain/coordination/viewer_offer_accepted.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/domain/entity/beacon_people_lens.dart';
import 'package:tentura/domain/entity/beacon_people_row.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/commitment_stake_state.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/domain/plan_assignable_people.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/dialog/decline_remaining_offers_flow.dart';
import 'package:tentura/features/beacon_view/ui/dialog/help_offer_admission_reason_dialog.dart';
import 'package:tentura/features/beacon_view/ui/dialog/help_offer_message_dialog.dart';
import 'package:tentura/features/beacon_view/ui/dialog/help_offer_role_label_dialog.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_accordion_sections.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_view_app_bar_overflow.dart';
import 'package:tentura/features/beacon_view/ui/widget/help_offer_tile.dart';
import 'package:tentura/features/beacon_view/ui/widget/unified_forward_row.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/accordion_expansion.dart';
import 'package:tentura/ui/widget/focus_flash_highlight.dart';
import 'package:tentura/ui/widget/offer_accepted_event_subcard.dart';
import 'package:tentura/ui/widget/self_aware_profile_avatar.dart';
import 'package:tentura/ui/widget/self_user_highlight.dart';

/// PageStorage / ExpansionTile id for the People-tab Forwards fold (exclusive by userId).
const _forwardsFoldId = 'forwards';

class BeaconPeopleTabBody extends StatelessWidget {
  const BeaconPeopleTabBody({
    required this.state,
    required this.beaconViewCubit,
    required this.l10n,
    this.focusUserId,
    this.peopleTabAttentionActive = false,
    super.key,
  });

  final BeaconViewState state;
  final BeaconViewCubit beaconViewCubit;
  final L10n l10n;

  /// When set, the matching participant card is scrolled into view and flashed.
  final String? focusUserId;

  /// Highlights all unanswered offers; scroll/focus only the first.
  final bool peopleTabAttentionActive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final beacon = state.beacon;
    final focusUid = focusUserId?.trim();
    final hasFocus = focusUid != null && focusUid.isNotEmpty;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    String? firstUnansweredUserId;
    if (peopleTabAttentionActive) {
      for (final c in state.helpOffers) {
        if (!c.isWithdrawn && c.coordinationResponse == null) {
          firstUnansweredUserId = c.user.id;
          break;
        }
      }
    }

    bool isUnansweredOffer(String userId) {
      for (final c in state.helpOffers) {
        if (c.user.id == userId &&
            !c.isWithdrawn &&
            c.coordinationResponse == null) {
          return true;
        }
      }
      return false;
    }

    Widget focusWrap(String userId, Widget child) {
      final attentionTarget =
          peopleTabAttentionActive && isUnansweredOffer(userId);
      if (!hasFocus && !attentionTarget) return child;

      final isFirstAttentionTarget =
          attentionTarget && userId == firstUnansweredUserId;
      final wrapped = FocusFlashHighlight(
        active: hasFocus ? userId == focusUid : attentionTarget,
        autoScroll:
            (hasFocus && userId == focusUid) ||
            (attentionTarget && isFirstAttentionTarget),
        animateFlash: hasFocus && !reduceMotion,
        staticHighlight: attentionTarget,
        child: child,
      );

      if (!attentionTarget) return wrapped;

      final unansweredCount = state.unansweredHelpOffersCount;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            liveRegion: true,
            label: l10n.beaconHudNeedsResponse,
            child: Padding(
              padding: EdgeInsets.only(bottom: context.tt.tightGap * 2),
              child: Row(
                children: [
                  Icon(
                    Icons.notifications_active_outlined,
                    size: theme.textTheme.labelMedium?.fontSize ?? 14,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      l10n.beaconHudNeedsResponse,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (unansweredCount > 0)
                    Text(
                      '$unansweredCount',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
          ),
          wrapped,
        ],
      );
    }

    final helpOfferInputs = state.helpOffers
        .where(
          (c) =>
              c.offerKind == 0 ||
              c.roomAccess == RoomAccessBits.admitted ||
              c.coordinationResponse != null,
        )
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

    final isObserver = beacon.accessLevel == BeaconAccessLevel.observer;

    // B077: the helper whose offer was accepted sees it here too, as the same
    // dismissible event sub-card as on their Requests tab, by the same rule
    // (isViewerOfferAccepted).
    final myAcceptedOffer = state.isAuthorOrSteward
        ? null
        : state.helpOffers
              .where(
                (c) =>
                    c.user.id == state.myProfile.id &&
                    isViewerOfferAccepted(
                      hasActiveOffer: !c.isWithdrawn,
                      viewerAccessReasons: beacon.accessReasons,
                    ),
              )
              .firstOrNull;
    final offerAcceptedEvent = myAcceptedOffer == null
        ? null
        : OfferAcceptedEventSubcard(
            beaconId: beacon.id,
            viewerId: state.myProfile.id,
            author: beacon.author,
            // #507: name the one who accepted (a steward may have).
            acceptorId: myAcceptedOffer.coordinationResponseAuthorId,
            acceptor:
                planAssignablePeople(
                      author: beacon.author,
                      admittedHelpers: state.admittedHelperRoster,
                      roomParticipants: state.roomParticipants,
                    )
                    .where(
                      (p) =>
                          p.id == myAcceptedOffer.coordinationResponseAuthorId,
                    )
                    .firstOrNull,
            // As on the Requests tab: when the author responded, not when
            // the offer was last edited.
            acceptedAt:
                myAcceptedOffer.coordinationResponseAt ??
                myAcceptedOffer.updatedAt,
            requestTitle: beacon.title,
            padding: EdgeInsets.only(bottom: context.tt.rowGap),
          );

    if (isObserver) {
      final observerRows = activeHelpersFromAdmittedRoster(
        beacon: beacon,
        admittedHelpers: state.admittedHelperRoster,
      );
      // A pending offerer is an observer; it still sees its own offer and
      // the author-seen footer on it.
      final myOffer = state.helpOffers
          .where((c) => !c.isWithdrawn && c.user.id == state.myProfile.id)
          .firstOrNull;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ?offerAcceptedEvent,
          if (myOffer != null) ...[
            HelpOfferTile(
              helpOffer: myOffer,
              beaconId: beacon.id,
              beaconAuthor: beacon.author,
              beaconAuthorId: beacon.author.id,
              isMine: true,
            ),
            const SizedBox(height: 12),
          ],
          AccordionExpansionGroup(
            accordionMode: false,
            child: AccordionExpansionTile(
              framed: false,
              id: BeaconPeopleAccordionSection.activeHelpers,
              initiallyExpanded: true,
              title: Text(
                '${l10n.beaconPeopleLensActiveHelpersHeading} '
                '(${activeHelperCount(observerRows)})',
                style: theme.textTheme.titleSmall,
              ),
              children: [
                for (var i = 0; i < observerRows.length; i++) ...[
                  if (i != 0) const SizedBox(height: 12),
                  focusWrap(
                    observerRows[i].userId,
                    _ObserverActiveHelperTile(
                      row: observerRows[i],
                      viewerId: state.myProfile.id,
                      onOpenProfile: () => context
                          .read<ScreenCubit>()
                          .showProfile(observerRows[i].userId),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      );
    }

    final sections = classifyBeaconPeopleSections(
      beacon: beacon,
      helpOffers: helpOfferInputs,
      roomParticipants: state.roomParticipants,
      viewerUserId: state.myProfile.id,
      admittedHelpers: state.admittedHelperRoster,
    );

    // A person belongs to their highest-priority section, never to two rows.
    final assignedUserIds = {
      for (final row in sections.activeHelpers) row.userId,
      for (final row in sections.notFitting) row.userId,
      for (final row in sections.willingToHelp) row.userId,
    };
    final backupOffers = state.helpOffers
        .where(
          (c) =>
              !c.isWithdrawn &&
              c.offerKind == 1 &&
              assignedUserIds.add(c.user.id),
        )
        .toList(growable: false);
    // The section each person's card is in (one category per person), used
    // to tell the viewer where a person they forwarded to went (#496).
    final sectionTitleByUserId = <String, String>{};
    void putSection(Iterable<String> userIds, String title) {
      for (final id in userIds) {
        sectionTitleByUserId.putIfAbsent(id, () => title);
      }
    }

    putSection(
      sections.activeHelpers.map((r) => r.userId),
      l10n.beaconPeopleLensActiveHelpersHeading,
    );
    putSection(
      sections.notFitting.map((r) => r.userId),
      l10n.beaconPeopleLensNotFittingHeading,
    );
    putSection(
      sections.willingToHelp.map((r) => r.userId),
      l10n.beaconPeopleLensWillingToHelpHeading,
    );
    putSection(
      backupOffers.map((c) => c.user.id),
      l10n.helpOffersBackupGroupTitle,
    );
    // Forward edges are claimed before the withdrawn fold: the spread of a
    // request is history, so a recipient who later withdrew keeps their
    // forward row (marked withdrawn) instead of vanishing from Forwards.
    final viewerId = state.myProfile.id;
    // People the viewer forwarded to whose card is in another section: they
    // get no Forwards row, but Forwards says where they are (#496).
    final movedRecipientIds = <String>{};
    final forwardEdges = state.viewerForwardEdges
        .where((edge) {
          final personId = edge.sender.id == viewerId
              ? edge.recipient.id
              : edge.sender.id;
          if (assignedUserIds.add(personId)) return true;
          if (edge.sender.id == viewerId &&
              sectionTitleByUserId.containsKey(personId)) {
            movedRecipientIds.add(personId);
          }
          return false;
        })
        .toList(growable: false);
    // Section title -> how many of the viewer's recipients are in it, in
    // section order.
    final movedCountBySection = <String, int>{};
    for (final title in sectionTitleByUserId.values.toSet()) {
      final n = movedRecipientIds
          .where((id) => sectionTitleByUserId[id] == title)
          .length;
      if (n > 0) movedCountBySection[title] = n;
    }
    final withdrawn = state.helpOffers
        .where((c) => c.isWithdrawn && assignedUserIds.add(c.user.id))
        .toList(growable: false);
    // People whose only help offers are withdrawn (no live offer).
    final liveOfferUserIds = {
      for (final c in state.helpOffers)
        if (!c.isWithdrawn) c.user.id,
    };
    final withdrawnOnlyUserIds = {
      for (final c in state.helpOffers)
        if (c.isWithdrawn && !liveOfferUserIds.contains(c.user.id)) c.user.id,
    };

    bool isDirectAuthorForward(String userId) {
      for (final c in state.helpOffers) {
        if (c.user.id == userId && !c.isWithdrawn) {
          return c.isDirectAuthorForward;
        }
      }
      return false;
    }

    List<BeaconPeopleRow> sortDirectForwardUp(List<BeaconPeopleRow> rows) {
      if (rows.length < 2) return rows;
      return [...rows]..sort((a, b) {
        final aDirect = isDirectAuthorForward(a.userId);
        final bDirect = isDirectAuthorForward(b.userId);
        if (aDirect == bDirect) return 0;
        return aDirect ? -1 : 1;
      });
    }

    final postOriginRows = state.isBeaconMine
        ? [
            for (final p in state.roomParticipants)
              if (p.role == BeaconParticipantRoleBits.addressee &&
                  p.roomAccess == RoomAccessBits.admitted)
                BeaconPeopleRow(
                  userId: p.userId,
                  profile: Profile(id: p.userId, displayName: p.userTitle),
                  participant: p,
                ),
          ]
        : const <BeaconPeopleRow>[];

    final peopleSections = BeaconPeopleSections(
      activeHelpers: sections.activeHelpers,
      willingToHelp: sortDirectForwardUp(sections.willingToHelp),
      notFitting: sections.notFitting,
    );

    final showWithdrawn = withdrawn.isNotEmpty;
    final requestedSectionId = peopleTabAttentionActive
        ? BeaconPeopleAccordionSection.willingToHelp
        : peopleTabAccordionSectionId(
            sections: sections,
            focusUserId: focusUserId,
            showWithdrawn: showWithdrawn,
            viewerIsAuthor: state.isAuthorOrSteward,
          );

    /// The row's live (non-withdrawn) help offer, or null when there is none
    /// (e.g. the author's own row).
    TimelineHelpOffer? liveHelpOfferForRow(BeaconPeopleRow row) {
      for (final c in state.helpOffers) {
        if (c.user.id == row.userId && !c.isWithdrawn) return c;
      }
      return null;
    }

    HelpOfferTile peopleTile(BeaconPeopleRow row) {
      final liveOffer = liveHelpOfferForRow(row);
      final hasHelpOffer = liveOffer != null;
      // No help offer behind this row: there is nothing that could have been
      // edited, so do not derive an "edited" marker from the participant
      // row's timestamp. The tile still needs an offer to render the row.
      final c =
          liveOffer ??
          TimelineHelpOffer(
            user: row.profile,
            message: '',
            createdAt: beacon.createdAt,
            updatedAt: beacon.createdAt,
          );
      final isMine = row.userId == state.myProfile.id;
      final canManageOffer =
          beacon.status.isOpenFamily &&
          !row.isAuthor &&
          !isMine &&
          state.isAuthorOrSteward &&
          hasHelpOffer;
      // Ending participation stays possible in Wrapping up (#489); admitting
      // new offers does not.
      final canEndParticipation =
          beacon.status.allowsCoordination &&
          !row.isAuthor &&
          !isMine &&
          state.isAuthorOrSteward &&
          hasHelpOffer;
      return HelpOfferTile(
        helpOffer: c,
        beaconId: beacon.id,
        beaconAuthor: beacon.author,
        beaconAuthorId: beacon.author.id,
        isMine: isMine,
        isAuthorView: state.isAuthorOrSteward && !isMine,
        participant: row.participant,
        showAuthorStar: row.isAuthor,
        hasHelpOffer: hasHelpOffer,
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
                  submitLabel: l10n.helpOfferAdmissionDecline,
                  destructive: true,
                );
                if (reason != null && context.mounted) {
                  await beaconViewCubit.declineHelpOffer(
                    offerUserId: row.userId,
                    reason: reason,
                  );
                }
              }
            : null,
        onReleaseCommitment:
            canEndParticipation &&
                c.stakeState == CommitmentStakeState.acknowledged
            ? () async {
                final reason = await HelpOfferAdmissionReasonDialog.show(
                  context,
                  title: l10n.helpOfferReleaseDialogTitle,
                  hintText: l10n.helpOfferReleaseDialogHint,
                );
                if (reason != null && context.mounted) {
                  await beaconViewCubit.releaseCommitment(
                    offerUserId: row.userId,
                    reason: reason,
                  );
                }
              }
            : null,
        // Edit and Withdraw act on the viewer's own help offer; a row without
        // one (the author's own card) has nothing to edit or withdraw.
        onEdit: isMine && hasHelpOffer
            ? () async {
                await beaconViewRunEditHelpOfferDialog(
                  context,
                  beaconViewCubit,
                  l10n,
                );
              }
            : null,
        onEditRole:
            !row.isAuthor &&
                !c.isWithdrawn &&
                (isMine || state.isAuthorOrSteward) &&
                state.helpOffers.any((ho) => ho.user.id == row.userId)
            ? () async {
                final next = await HelpOfferRoleLabelDialog.show(
                  context,
                  initialText: c.roleLabel ?? '',
                );
                if (next != null && context.mounted) {
                  await beaconViewCubit.setRoleLabel(
                    offerUserId: row.userId,
                    roleLabel: next,
                  );
                }
              }
            : null,
        onWithdraw:
            isMine && hasHelpOffer && beacon.allowsWithdrawWhileHelpOffered
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
        framed: false,
        id: sectionId,
        initiallyExpanded: initiallyExpanded,
        title: Text(
          '$title (${activeHelperCount(rows)})',
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
    final tt = context.tt;
    final graphHit = tt.buttonHeight < kMinInteractiveDimension
        ? kMinInteractiveDimension
        : tt.buttonHeight;

    final forwardsTitle = state.forwardsLoaded
        ? '${l10n.labelForwards} (${forwardEdges.length})'
        : l10n.labelForwards;

    final List<Widget> forwardsChildren;
    if (state.forwardsLoading) {
      forwardsChildren = const [
        Center(
          child: Padding(
            padding: kPaddingSmallV,
            child: CircularProgressIndicator.adaptive(),
          ),
        ),
      ];
    } else if (state.forwardsLoaded) {
      final edges = forwardEdges;
      final movedLines = <Widget>[
        for (final entry in movedCountBySection.entries)
          Text(
            l10n.beaconForwardsRecipientsMoved(entry.value, entry.key),
            style: TenturaText.bodyMedium(tt.textMuted),
          ),
      ];
      if (edges.isEmpty && movedLines.isNotEmpty) {
        forwardsChildren = [
          for (var i = 0; i < movedLines.length; i++) ...[
            if (i > 0) SizedBox(height: context.tt.tightGap),
            movedLines[i],
          ],
        ];
      } else if (edges.isEmpty) {
        forwardsChildren = [
          Text(
            l10n.beaconForwardsEmpty,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ];
      } else {
        final feedRows = <Widget>[
          for (final e in edges)
            if (e.sender.id == viewerId)
              UnifiedForwardRow.outgoing(
                showSender: false,
                edge: e,
                viewerUserId: viewerId,
                helpOffered: state.involvementHelpOfferedIds,
                watching: state.involvementWatchingIds,
                onward: state.involvementOnwardForwarderIds,
                withdrawn: withdrawnOnlyUserIds,
                reasonSlugs:
                    state
                        .forwardReasonSlugs['${e.sender.id}__${e.recipient.id}'] ??
                    const [],
              )
            else
              UnifiedForwardRow.inbound(
                sender: e.sender,
                note: e.note,
                viewerUserId: viewerId,
                reasonSlugs:
                    state
                        .forwardReasonSlugs['${e.sender.id}__${e.recipient.id}'] ??
                    const [],
              ),
        ];
        forwardsChildren = [
          for (var i = 0; i < feedRows.length; i++) ...[
            if (i > 0) const SizedBox(height: kSpacingMedium),
            feedRows[i],
          ],
          for (final line in movedLines) ...[
            const SizedBox(height: kSpacingMedium),
            line,
          ],
        ];
      }
    } else {
      forwardsChildren = const [SizedBox.shrink()];
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ?offerAcceptedEvent,
        AccordionExpansionGroup(
          accordionMode: false,
          child: AccordionExpansionTile(
            framed: false,
            id: _forwardsFoldId,
            title: Text(
              forwardsTitle,
              style: theme.textTheme.titleSmall,
            ),
            headerAction: SizedBox(
              width: graphHit,
              height: graphHit,
              child: IconButton(
                icon: const Icon(TenturaIcons.graph),
                tooltip: l10n.forwardsGraphMenuTitle,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: BoxConstraints(
                  minWidth: graphHit,
                  minHeight: graphHit,
                ),
                onPressed: () =>
                    context.read<ScreenCubit>().showForwardsGraphFor(beacon.id),
              ),
            ),
            onExpansionChanged: (open) {
              if (open) {
                unawaited(beaconViewCubit.loadForwards());
              }
            },
            children: forwardsChildren,
          ),
        ),
        SizedBox(height: tt.rowGap),
        if (postOriginRows.isNotEmpty) ...[
          Text(
            l10n.postOriginPeopleSection(postOriginRows.length),
            style: sectionHeaderStyle,
          ),
          SizedBox(height: tt.tightGap),
          for (final row in postOriginRows) ...[
            _ObserverActiveHelperTile(
              row: row,
              viewerId: viewerId,
              onOpenProfile: () =>
                  context.read<ScreenCubit>().showProfile(row.userId),
            ),
            const SizedBox(height: 12),
          ],
        ],
        Builder(
          builder: (context) {
            // Author with open offers: decisions first (UI review).
            final pendingFirst =
                state.isAuthorOrSteward &&
                peopleSections.willingToHelp.isNotEmpty;
            final activeFold = peopleSectionFold(
              sectionId: BeaconPeopleAccordionSection.activeHelpers,
              title: l10n.beaconPeopleLensActiveHelpersHeading,
              rows: peopleSections.activeHelpers,
              initiallyExpanded: true,
            );
            final willingRows = peopleSectionFold(
              sectionId: BeaconPeopleAccordionSection.willingToHelp,
              title: l10n.beaconPeopleLensWillingToHelpHeading,
              rows: peopleSections.willingToHelp,
              initiallyExpanded: true,
            );
            // Offers waiting for the author (#268): the shared-discussion
            // model in one line, and, after «Enough help», releasing the
            // rest in one step.
            final showPendingFooter =
                state.isAuthorOrSteward &&
                beacon.status.isOpenFamily &&
                (peopleSections.willingToHelp.isNotEmpty ||
                    state.canDeclineRemainingOffers);
            final willingFold = showPendingFooter
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      willingRows,
                      _PendingOffersFooter(
                        canDeclineRemaining: state.canDeclineRemainingOffers,
                        onDeclineRemaining: () => unawaited(
                          beaconViewOfferDeclineRemainingOffers(
                            context,
                            beaconViewCubit,
                          ),
                        ),
                      ),
                    ],
                  )
                : willingRows;
            return AccordionExpansionGroup(
              initialExpandedId: requestedSectionId,
              requestedExpandedId: requestedSectionId,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (pendingFirst) willingFold else activeFold,
                  if (peopleSections.activeHelpers.isNotEmpty &&
                      peopleSections.willingToHelp.isNotEmpty)
                    SizedBox(height: tt.rowGap),
                  if (pendingFirst) activeFold else willingFold,
                  if ((peopleSections.activeHelpers.isNotEmpty ||
                          peopleSections.willingToHelp.isNotEmpty) &&
                      peopleSections.notFitting.isNotEmpty)
                    SizedBox(height: tt.rowGap),
                  peopleSectionFold(
                    sectionId: BeaconPeopleAccordionSection.notFitting,
                    title: l10n.beaconPeopleLensNotFittingHeading,
                    rows: peopleSections.notFitting,
                    initiallyExpanded: false,
                  ),
                  if (backupOffers.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      '${l10n.helpOffersBackupGroupTitle} (${backupOffers.length})',
                      style: sectionHeaderStyle,
                    ),
                    SizedBox(height: tt.tightGap),
                    Text(
                      l10n.helpOffersBackupGroupHint,
                      style: TenturaText.bodySmall(tt.textMuted),
                    ),
                    const SizedBox(height: 8),
                    for (var k = 0; k < backupOffers.length; k++) ...[
                      if (k != 0) const SizedBox(height: 12),
                      focusWrap(
                        backupOffers[k].user.id,
                        HelpOfferTile(
                          helpOffer: backupOffers[k],
                          beaconId: beacon.id,
                          beaconAuthor: beacon.author,
                          beaconAuthorId: beacon.author.id,
                          isMine: backupOffers[k].user.id == state.myProfile.id,
                          isAuthorView: state.isAuthorOrSteward,
                          showBackupHint: false,
                          onEditRole:
                              !backupOffers[k].isWithdrawn &&
                                  (backupOffers[k].user.id ==
                                          state.myProfile.id ||
                                      state.isAuthorOrSteward)
                              ? () async {
                                  final offer = backupOffers[k];
                                  final next =
                                      await HelpOfferRoleLabelDialog.show(
                                        context,
                                        initialText: offer.roleLabel ?? '',
                                      );
                                  if (next != null && context.mounted) {
                                    await beaconViewCubit.setRoleLabel(
                                      offerUserId: offer.user.id,
                                      roleLabel: next,
                                    );
                                  }
                                }
                              : null,
                        ),
                      ),
                    ],
                  ],
                  if (showWithdrawn) ...[
                    const SizedBox(height: 8),
                    AccordionExpansionTile(
                      framed: false,
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
            );
          },
        ),
      ],
    );
  }
}

/// Read-only Active helper row for observers (no offer actions / forward path).
class _ObserverActiveHelperTile extends StatelessWidget {
  const _ObserverActiveHelperTile({
    required this.row,
    required this.viewerId,
    required this.onOpenProfile,
  });

  final BeaconPeopleRow row;
  final String viewerId;
  final VoidCallback onOpenProfile;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final name = SelfUserHighlight.displayName(l10n, row.profile, viewerId);
    final nameStyle = SelfUserHighlight.nameStyle(
      theme,
      theme.textTheme.titleSmall,
      SelfUserHighlight.profileIsSelf(row.profile, viewerId),
    );

    return TenturaTechCardStatic(
      showShadow: true,
      child: InkWell(
        onTap: onOpenProfile,
        borderRadius: BorderRadius.circular(TenturaRadii.card),
        child: Row(
          children: [
            SelfAwareAvatar.medium(
              profile: row.profile,
              showAuthorStar: row.isAuthor,
            ),
            SizedBox(width: context.tt.rowGap),
            Expanded(
              child: Text(
                name,
                style: nameStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Under the offers waiting for the author (#268): one line on the shared
/// discussion (accepting someone never opens a private chat) and, after
/// «Enough help», «Decline remaining offers».
class _PendingOffersFooter extends StatelessWidget {
  const _PendingOffersFooter({
    required this.canDeclineRemaining,
    required this.onDeclineRemaining,
  });

  final bool canDeclineRemaining;
  final VoidCallback onDeclineRemaining;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    return Padding(
      padding: EdgeInsets.only(top: tt.tightGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.helpOfferAcceptSharedChatHint,
            style: TenturaText.bodySmall(tt.textMuted),
          ),
          if (canDeclineRemaining)
            TenturaTextAction(
              label: l10n.declineRemainingOffersAction,
              tone: TenturaTone.danger,
              flushStart: true,
              onPressed: onDeclineRemaining,
            ),
        ],
      ),
    );
  }
}
