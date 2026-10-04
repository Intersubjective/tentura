import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/features/beacon/ui/widget/beacon_lineage_parent_link.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/beacon_hierarchy_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/beacon_hierarchy_state.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_child_requests_section.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_hierarchy_parent_link.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_operational_header_card.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_view_app_bar_overflow.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_view_forward_overflow.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_current_line_sheet.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_pinned_facts_sheet.dart';
import 'package:tentura/features/beacon_view/ui/widget/declined_offer_notice.dart';
import 'package:tentura/features/beacon_view/ui/presenter/beacon_hud_author_action.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_request_modes.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_hud_pinned_block.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_hud_team_section.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_view_details_sheet.dart';
import 'package:tentura/features/inbox/domain/enum.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'beacon_view_constants.dart';

/// NOW surface: operational header, state, actions, and child request cards.
class BeaconNowSurface extends StatefulWidget {
  const BeaconNowSurface({
    required this.beaconViewCubit,
    required this.screenCubit,
    required this.beaconState,
    required this.onSurfaceSelected,
    required this.onActivatePeopleTabAttention,
    required this.onFocusCoordinationItem,
    required this.onOpenGeneralThread,
    super.key,
  });

  final BeaconViewCubit beaconViewCubit;
  final ScreenCubit screenCubit;
  final BeaconViewState beaconState;
  final ValueChanged<BeaconSurface> onSurfaceSelected;
  final VoidCallback onActivatePeopleTabAttention;
  final void Function(CoordinationItem item) onFocusCoordinationItem;
  final VoidCallback onOpenGeneralThread;

  @override
  State<BeaconNowSurface> createState() => _BeaconNowSurfaceState();
}

class _BeaconNowSurfaceState extends State<BeaconNowSurface> {
  final _subrequestsKey = GlobalKey();
  final _teamKey = GlobalKey();

  BeaconViewCubit get beaconViewCubit => widget.beaconViewCubit;
  ScreenCubit get screenCubit => widget.screenCubit;
  ValueChanged<BeaconSurface> get onSurfaceSelected => widget.onSurfaceSelected;
  VoidCallback get onActivatePeopleTabAttention =>
      widget.onActivatePeopleTabAttention;
  void Function(CoordinationItem item) get onFocusCoordinationItem =>
      widget.onFocusCoordinationItem;
  VoidCallback get onOpenGeneralThread => widget.onOpenGeneralThread;

  void _scrollTo(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return;
    unawaited(
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      ),
    );
  }

  VoidCallback? _editStepAction(BuildContext context, BeaconViewState state) =>
      state.canCoordinateInBeaconRoom
      ? () => unawaited(
          showBeaconCurrentLineSheet(
            context,
            beaconId: state.beacon.id,
            initialText: state.beaconRoomCue?.currentLine ?? '',
            onSaved: (line) => unawaited(
              beaconViewCubit.refreshBeaconRoomCue(savedCurrentLine: line),
            ),
          ),
        )
      : null;

  Future<void> _runOfferHelpFlow(BuildContext context, L10n l10n) async {
    await beaconViewRunInitialHelpOfferDialog(
      context,
      beaconViewCubit,
      l10n,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final tt = context.tt;

    return BlocBuilder<BeaconViewCubit, BeaconViewState>(
      bloc: beaconViewCubit,
      buildWhen: (p, c) =>
          p.beacon != c.beacon ||
          p.beacon.status != c.beacon.status ||
          p.timeline != c.timeline ||
          p.roomActivityEvents != c.roomActivityEvents ||
          p.helpOffers != c.helpOffers ||
          p.isHelpOffered != c.isHelpOffered ||
          p.isLoading != c.isLoading ||
          p.forwardProvenance != c.forwardProvenance ||
          p.inboxStatus != c.inboxStatus ||
          p.viewerForwardEdges != c.viewerForwardEdges ||
          p.forwardsLoaded != c.forwardsLoaded ||
          p.forwardsLoading != c.forwardsLoading ||
          p.factCards != c.factCards ||
          p.pinnedFactsSeenAt != c.pinnedFactsSeenAt ||
          p.roomParticipants.length != c.roomParticipants.length ||
          (p.roomParticipants
                  .map(
                    (e) =>
                        '${e.userId}|${e.userTitle}|${e.nextMoveText}|${e.status}|${e.nextMoveStatus}|${e.roomAccess}|${e.role}',
                  )
                  .join() !=
              c.roomParticipants
                  .map(
                    (e) =>
                        '${e.userId}|${e.userTitle}|${e.nextMoveText}|${e.status}|${e.nextMoveStatus}|${e.roomAccess}|${e.role}',
                  )
                  .join()) ||
          p.beaconRoomCue?.lastRoomMeaningfulChange !=
              c.beaconRoomCue?.lastRoomMeaningfulChange ||
          p.beaconRoomCue?.currentLine != c.beaconRoomCue?.currentLine ||
          p.beaconRoomCue?.openBlockerTitle !=
              c.beaconRoomCue?.openBlockerTitle ||
          p.unansweredHelpOffersCount != c.unansweredHelpOffersCount ||
          p.needCoordinationHelpOffersCount !=
              c.needCoordinationHelpOffersCount ||
          p.closureState != c.closureState ||
          p.beaconContextLoaded != c.beaconContextLoaded ||
          p.isRoomAdmissionBlocked != c.isRoomAdmissionBlocked ||
          p.coordinationDeniesRoomAdmission !=
              c.coordinationDeniesRoomAdmission,
      builder: (context, state) {
        final admitted = !state.isRoomAdmissionBlocked;

        final authorHudAction = state.isBeaconMine
            ? (BeaconHudAuthorAction action) => unawaited(
                beaconViewHandleAuthorHudAction(
                  context: context,
                  cubit: beaconViewCubit,
                  l10n: l10n,
                  action: action,
                  onOpenPeopleTab: () =>
                      onSurfaceSelected(BeaconSurface.people),
                  onActivatePeopleAttention: onActivatePeopleTabAttention,
                  onFocusCoordinationItem: onFocusCoordinationItem,
                  onOpenItemsTab: () => onSurfaceSelected(BeaconSurface.room),
                  onOpenGeneralThread: onOpenGeneralThread,
                ),
              )
            : null;
        final team = beaconHudTeam(state);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BlocBuilder<BeaconHierarchyCubit, BeaconHierarchyState>(
              buildWhen: (p, c) =>
                  p.active.items.length != c.active.items.length,
              builder: (context, hierarchyState) => BeaconHudPinnedBlock(
                state: state,
                subrequestCount: admitted
                    ? hierarchyState.active.items.length
                    : 0,
                onEditStep: _editStepAction(context, state),
                onReviewAuthorOffers: authorHudAction == null
                    ? null
                    : () => authorHudAction(
                        BeaconHudAuthorAction.reviewOffers,
                      ),
                onOpenTeam: admitted
                    ? () => _scrollTo(_teamKey)
                    : () => onSurfaceSelected(BeaconSurface.people),
                onOpenSubrequests: () => _scrollTo(_subrequestsKey),
                onOpenFacts: () => unawaited(
                  showBeaconPinnedFactsSheet(context, cubit: beaconViewCubit),
                ),
              ),
            ),
            Expanded(
              child: CustomScrollView(
                physics: const ClampingScrollPhysics(),
                slivers: [
                  BlocBuilder<BeaconHierarchyCubit, BeaconHierarchyState>(
                    buildWhen: (p, c) => p.parentReference != c.parentReference,
                    builder: (context, hierarchyState) {
                      final reference = hierarchyState.parentReference;
                      if (reference == null) {
                        return const SliverToBoxAdapter(
                          child: SizedBox.shrink(),
                        );
                      }
                      return SliverToBoxAdapter(
                        child: ColoredBox(
                          color: scheme.surface,
                          child: BeaconHierarchyParentLink(
                            reference: reference,
                          ),
                        ),
                      );
                    },
                  ),
                  if (state.beacon.lineageParentBeaconId != null &&
                      state.beacon.lineageParentBeaconId!.isNotEmpty)
                    SliverToBoxAdapter(
                      child: ColoredBox(
                        color: scheme.surface,
                        child: BeaconLineageParentLink(
                          parentBeaconId: state.beacon.lineageParentBeaconId!,
                        ),
                      ),
                    ),
                  SliverToBoxAdapter(
                    child: ColoredBox(
                      color: scheme.surface,
                      child: BeaconOperationalHeaderCard(
                        state: state,
                        showHudRows: false,
                        onAuthorTap: () =>
                            screenCubit.showProfile(state.beacon.author.id),
                        onAuthorHudAction: authorHudAction,
                        onOfferHelp:
                            !state.isBeaconMine &&
                                state.beacon.status.isOpenFamily &&
                                !state.isHelpOffered &&
                                state.beacon.allowsNewHelpOfferAsNonAuthor
                            ? () => _runOfferHelpFlow(context, l10n)
                            : null,
                        onLeavePostChat: state.isPostOriginParticipant
                            ? () => unawaited(beaconViewCubit.leavePostChat())
                            : null,
                        onEditHelpOffer:
                            !state.isBeaconMine &&
                                state.isRoomAdmissionBlocked &&
                                !state.coordinationDeniesRoomAdmission
                            ? () => unawaited(
                                beaconViewRunEditHelpOfferDialog(
                                  context,
                                  beaconViewCubit,
                                  l10n,
                                ),
                              )
                            : null,
                        onWatch:
                            !state.isBeaconMine &&
                                !state.isHelpOffered &&
                                state.inboxStatus == InboxItemStatus.needsMe
                            ? () => unawaited(beaconViewCubit.moveToWatching())
                            : null,
                        onStopWatching:
                            !state.isBeaconMine &&
                                !state.isHelpOffered &&
                                state.inboxStatus == InboxItemStatus.watching
                            ? () => unawaited(beaconViewCubit.stopWatching())
                            : null,
                        onSwitchToPeopleTab: () => onSurfaceSelected(
                          BeaconSurface.people,
                        ),
                        onEditNowLine: _editStepAction(context, state),
                        onOpenPinnedFacts: () => unawaited(
                          showBeaconPinnedFactsSheet(
                            context,
                            cubit: beaconViewCubit,
                          ),
                        ),
                        onForward: state.beacon.viewerCanForward
                            ? () => unawaited(
                                beaconViewOpenForwardThenMaybeNudgeOfferHelp(
                                  context,
                                  beaconViewCubit,
                                  l10n,
                                ),
                              )
                            : null,
                      ),
                    ),
                  ),
                  if (state.myDeclinedHelpOffer case final declined?)
                    SliverPadding(
                      padding: EdgeInsets.symmetric(
                        horizontal: tt.screenHPadding,
                      ).copyWith(top: tt.cardGap),
                      sliver: SliverToBoxAdapter(
                        child: DeclinedOfferNotice(
                          reason: declined.lastDeclineReason,
                          canOfferAgain:
                              state.beacon.status.isOpenFamily &&
                              state.beacon.allowsNewHelpOfferAsNonAuthor,
                        ),
                      ),
                    ),
                  if (admitted) ...[
                    const SliverToBoxAdapter(child: _HierarchyBootstrap()),
                    SliverPadding(
                      // A section of its own: on the column edge with the Details /
                      // Facts cards and the Forward action above it, not on the HUD
                      // rows' text line (which left it 32 dp in from everything).
                      padding: EdgeInsets.symmetric(
                        horizontal: tt.screenHPadding,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: KeyedSubtree(
                          key: _subrequestsKey,
                          child: BeaconChildRequestsSection(beaconState: state),
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: EdgeInsets.symmetric(
                        horizontal: tt.screenHPadding,
                      ).copyWith(top: tt.cardGap),
                      sliver: SliverToBoxAdapter(
                        child: KeyedSubtree(
                          key: _teamKey,
                          child: BeaconHudTeamSection(
                            members: team,
                            onOpenProfile: screenCubit.showProfile,
                            onOpenPeople: () =>
                                onSurfaceSelected(BeaconSurface.people),
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (beaconViewHasDetailsContent(state.beacon))
                    SliverPadding(
                      padding: EdgeInsets.symmetric(
                        horizontal: tt.screenHPadding,
                      ).copyWith(top: tt.cardGap, bottom: tt.sectionGap),
                      sliver: SliverToBoxAdapter(
                        child: BeaconHudEssenceRow(
                          beacon: state.beacon,
                          onOpenDetails: () => unawaited(
                            showBeaconViewDetailsSheet(
                              context,
                              beacon: state.beacon,
                            ),
                          ),
                        ),
                      ),
                    ),
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _HierarchyBootstrap extends StatefulWidget {
  const _HierarchyBootstrap();

  @override
  State<_HierarchyBootstrap> createState() => _HierarchyBootstrapState();
}

class _HierarchyBootstrapState extends State<_HierarchyBootstrap> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(context.read<BeaconHierarchyCubit>().load());
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
