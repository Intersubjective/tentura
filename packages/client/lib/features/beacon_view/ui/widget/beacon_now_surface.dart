import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

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
import 'package:tentura/features/inbox/domain/enum.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'beacon_view_constants.dart';

/// NOW surface: operational header, state, actions, and child request cards.
class BeaconNowSurface extends StatelessWidget {
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
          p.showDraftEvaluationCta != c.showDraftEvaluationCta ||
          p.unansweredHelpOffersCount != c.unansweredHelpOffersCount ||
          p.needCoordinationHelpOffersCount !=
              c.needCoordinationHelpOffersCount ||
          p.reviewWindowInfo != c.reviewWindowInfo ||
          p.beaconContextLoaded != c.beaconContextLoaded ||
          p.isRoomAdmissionBlocked != c.isRoomAdmissionBlocked ||
          p.coordinationDeniesRoomAdmission != c.coordinationDeniesRoomAdmission,
      builder: (context, state) {
        final beaconId = state.beacon.id;
        final admitted = !state.isRoomAdmissionBlocked;

        return CustomScrollView(
          physics: const ClampingScrollPhysics(),
          slivers: [
            BlocBuilder<BeaconHierarchyCubit, BeaconHierarchyState>(
              buildWhen: (p, c) => p.parentReference != c.parentReference,
              builder: (context, hierarchyState) {
                final reference = hierarchyState.parentReference;
                if (reference == null) {
                  return const SliverToBoxAdapter(child: SizedBox.shrink());
                }
                return SliverToBoxAdapter(
                  child: ColoredBox(
                    color: scheme.surface,
                    child: BeaconHierarchyParentLink(reference: reference),
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
                  onAuthorTap: () =>
                      screenCubit.showProfile(state.beacon.author.id),
                  onAuthorHudAction: state.isBeaconMine
                      ? (action) => unawaited(
                          beaconViewHandleAuthorHudAction(
                            context: context,
                            cubit: beaconViewCubit,
                            l10n: l10n,
                            action: action,
                            onOpenPeopleTab: () => onSurfaceSelected(
                              BeaconSurface.people,
                            ),
                            onActivatePeopleAttention:
                                onActivatePeopleTabAttention,
                            onFocusCoordinationItem: onFocusCoordinationItem,
                            onOpenItemsTab: () => onSurfaceSelected(
                              BeaconSurface.room,
                            ),
                            onOpenGeneralThread: onOpenGeneralThread,
                          ),
                        )
                      : null,
                  onOfferHelp:
                      !state.isBeaconMine &&
                          state.beacon.status.isOpenFamily &&
                          !state.isHelpOffered &&
                          state.beacon.allowsNewHelpOfferAsNonAuthor
                      ? () => _runOfferHelpFlow(context, l10n)
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
                  onEditNowLine: state.canCoordinateInBeaconRoom
                      ? () => unawaited(
                          showBeaconCurrentLineSheet(
                            context,
                            beaconId: beaconId,
                            initialText: state.beaconRoomCue?.currentLine ?? '',
                            onSaved: (line) => unawaited(
                              beaconViewCubit.refreshBeaconRoomCue(
                                savedCurrentLine: line,
                              ),
                            ),
                          ),
                        )
                      : null,
                  onOpenPinnedFacts: () => unawaited(
                    showBeaconPinnedFactsSheet(
                      context,
                      cubit: beaconViewCubit,
                    ),
                  ),
                  onForward: state.beacon.allowsForward
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
            if (admitted) ...[
              const SliverToBoxAdapter(child: _HierarchyBootstrap()),
              SliverToBoxAdapter(
                child: BeaconChildRequestsSection(beaconState: state),
              ),
            ],
            const SliverFillRemaining(
              hasScrollBody: false,
              child: SizedBox.shrink(),
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
