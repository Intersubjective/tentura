import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_activity_event.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/features/beacon/ui/widget/beacon_lineage_parent_link.dart';
import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/threads_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/threads_state.dart';
import 'package:tentura/features/beacon_threads/ui/widget/threads_list.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/widget/activity_list.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_operational_header_card.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_view_app_bar_overflow.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_view_forward_overflow.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_current_line_sheet.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_people_tab_body.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_pinned_facts_sheet.dart';
import 'package:tentura/features/inbox/domain/enum.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import 'beacon_view_constants.dart';

class BeaconOperationalScrollView extends StatelessWidget {
  const BeaconOperationalScrollView({
    required this.beaconViewCubit,
    required this.screenCubit,
    required this.tabIndex,
    required this.onTabChanged,
    required this.peopleTabAttentionActive,
    required this.onPeopleTabAttentionCleared,
    required this.onActivatePeopleTabAttention,
    required this.onFocusCoordinationItem,
    required this.focusThreadId,
    required this.focusUserId,
    required this.onOperationalFocusCleared,
    required this.onTapCoordinationLogEvent,
    required this.onOpenThread,
    required this.onOpenGeneralThread,
    required this.onThreadsTabRefresh,
    required this.beaconState,
    this.peopleFoldEpoch = 0,
    this.threadsFoldEpoch = 0,
    this.onTabReselected,
    this.selectedThreadId,
    super.key,
  });

  final BeaconViewCubit beaconViewCubit;
  final ScreenCubit screenCubit;
  final int tabIndex;
  final ValueChanged<int> onTabChanged;

  /// Pulse/highlight People tab until first pointer interaction or tab change.
  final bool peopleTabAttentionActive;
  final VoidCallback onPeopleTabAttentionCleared;
  final VoidCallback onActivatePeopleTabAttention;
  final void Function(CoordinationItem item) onFocusCoordinationItem;

  /// Thread / participant to focus + flash (Log row tap-to-focus).
  final String? focusThreadId;
  final String? focusUserId;
  final VoidCallback onOperationalFocusCleared;
  final void Function(BeaconActivityEvent event) onTapCoordinationLogEvent;

  final void Function(RequestThread thread) onOpenThread;
  final VoidCallback onOpenGeneralThread;
  final VoidCallback onThreadsTabRefresh;

  /// Bumped on same-tab reselect to remount People folds to defaults.
  final int peopleFoldEpoch;

  /// Bumped on same-tab reselect to remount Threads folds to defaults.
  final int threadsFoldEpoch;

  /// Called when the already-selected People or Threads tab is tapped again.
  final ValueChanged<int>? onTabReselected;

  final BeaconViewState beaconState;
  final String? selectedThreadId;

  void _setTab(BuildContext context, int i) {
    if (tabIndex == i) {
      onPeopleTabAttentionCleared();
      if (i == kBeaconTabPeople || i == kBeaconTabThreads) {
        onOperationalFocusCleared();
        onTabReselected?.call(i);
        if (i == kBeaconTabThreads) {
          context.read<ThreadsCubit>().setActiveForMeOnly(false);
        }
      }
      return;
    }
    onTabChanged(i);
  }

  void _onPointerDown(PointerDownEvent _) {
    if (focusThreadId != null || focusUserId != null) {
      onOperationalFocusCleared();
    }
  }

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
    final idx = tabIndex.clamp(0, kBeaconTabCount - 1);
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
          p.beaconContextLoaded != c.beaconContextLoaded,
      builder: (context, state) {
        final beaconId = state.beacon.id;

        final tabBody = switch (idx) {
          kBeaconTabThreads => ThreadsList(
            beaconState: beaconState,
            onOpenThread: onOpenThread,
            onSwitchToPeopleTab: () => _setTab(context, kBeaconTabPeople),
            focusThreadId: focusThreadId,
            selectedThreadId: selectedThreadId,
          ),
          kBeaconTabPeople => BeaconPeopleTabBody(
            state: state,
            beaconViewCubit: beaconViewCubit,
            l10n: l10n,
            focusUserId: focusUserId,
            peopleTabAttentionActive: peopleTabAttentionActive,
          ),
          kBeaconTabLog => BeaconActivityList(
            timeline: const [],
            beacon: state.beacon,
            isAuthorView: state.isBeaconMine,
            roomActivityEvents: state.roomActivityEvents,
            coordinationLogOnly: true,
            onTapCoordinationEvent: onTapCoordinationLogEvent,
            actors: {
              for (final p in state.roomParticipants) p.userId: p,
            },
          ),
          _ => const SizedBox.shrink(),
        };

        final tt = context.tt;
        final tabPadding = idx == kBeaconTabPeople
            ? EdgeInsets.fromLTRB(
                tt.screenHPadding,
                tt.cardPadding.top,
                tt.screenHPadding,
                tt.cardPadding.bottom,
              )
            : EdgeInsets.zero;

        final peopleTabBadge =
            state.isBeaconMine && state.unansweredHelpOffersCount > 0
            ? state.unansweredHelpOffersCount
            : null;
        final peopleTabSecondaryBadge =
            state.needCoordinationHelpOffersCount > 0
            ? state.needCoordinationHelpOffersCount
            : null;

        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: _onPointerDown,
          child: CustomScrollView(
            physics: const ClampingScrollPhysics(),
            slivers: [
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
                              onOpenPeopleTab: () =>
                                  _setTab(context, kBeaconTabPeople),
                              onActivatePeopleAttention:
                                  onActivatePeopleTabAttention,
                              onFocusCoordinationItem: onFocusCoordinationItem,
                              onOpenItemsTab: () =>
                                  _setTab(context, kBeaconTabThreads),
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
                    onSwitchToPeopleTab: () =>
                        _setTab(context, kBeaconTabPeople),
                    onEditNowLine: state.canCoordinateInBeaconRoom
                        ? () => unawaited(
                            showBeaconCurrentLineSheet(
                              context,
                              beaconId: beaconId,
                              initialText:
                                  state.beaconRoomCue?.currentLine ?? '',
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
              SliverPersistentHeader(
                pinned: true,
                delegate: BeaconPinnedSegmentBarDelegate(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: context.tt.screenHPadding,
                    ),
                    child: Align(
                      child: SizedBox(
                        width: double.infinity,
                        child: BlocBuilder<ThreadsCubit, ThreadsState>(
                          buildWhen: (p, c) =>
                              p.threads != c.threads ||
                              p.resolvedUnreadByThreadId !=
                                  c.resolvedUnreadByThreadId,
                          builder: (context, threadsState) {
                            final threadsTabBadge =
                                threadsState.threadsTabUnreadCount > 0
                                ? threadsState.threadsTabUnreadCount
                                : null;
                            return TenturaUnderlineTabs(
                              tabs: [
                                l10n.labelBeaconTabThreads,
                                l10n.labelBeaconTabPeople,
                                l10n.labelBeaconTabLog,
                              ],
                              icons: kBeaconTabIcons,
                              tabIds: [
                                TestIds.beaconTabThreads,
                                TestIds.beaconTabPeople,
                                TestIds.beaconTabLog,
                              ],
                              selectedIndex: idx,
                              onChanged: (i) => _setTab(context, i),
                              badges: [
                                threadsTabBadge,
                                peopleTabBadge,
                                null,
                              ],
                              badgeBackgroundColors: [
                                null,
                                peopleTabBadge != null ? tt.danger : null,
                                null,
                              ],
                              secondaryBadges: [
                                null,
                                peopleTabSecondaryBadge,
                                null,
                              ],
                              attentionIndex: kBeaconTabPeople,
                              attentionActive: peopleTabAttentionActive,
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SliverPadding(
                key: ValueKey(
                  '$idx-${idx == kBeaconTabPeople
                      ? peopleFoldEpoch
                      : idx == kBeaconTabThreads
                      ? threadsFoldEpoch
                      : 0}',
                ),
                padding: tabPadding,
                sliver: SliverToBoxAdapter(child: tabBody),
              ),
              const SliverFillRemaining(
                hasScrollBody: false,
                child: SizedBox.shrink(),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Pinned tab bar: fixed height so layoutExtent matches paintExtent under
/// NestedScrollView (avoids invalid SliverGeometry on web).
class BeaconPinnedSegmentBarDelegate extends SliverPersistentHeaderDelegate {
  BeaconPinnedSegmentBarDelegate({required this.child});

  final Widget child;

  static const double _barHeight = 48;

  @override
  double get minExtent => _barHeight;

  @override
  double get maxExtent => _barHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final tt = context.tt;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: overlapsContent ? tt.borderSubtle : Colors.transparent,
          ),
        ),
      ),
      child: SizedBox(
        height: _barHeight,
        width: double.infinity,
        child: Material(color: Colors.transparent, child: child),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant BeaconPinnedSegmentBarDelegate oldDelegate) {
    return child != oldDelegate.child;
  }
}
