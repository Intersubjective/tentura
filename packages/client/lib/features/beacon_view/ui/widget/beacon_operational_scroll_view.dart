import 'dart:async';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:flutter/material.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_activity_event.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/features/beacon/ui/widget/beacon_lineage_parent_link.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/bloc/items_tab_cubit.dart';
import 'package:tentura/features/beacon_view/ui/bloc/items_tab_state.dart';
import 'package:tentura/features/beacon_view/ui/widget/activity_list.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_operational_header_card.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_pinned_facts_strip.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_current_line_sheet.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_people_tab_body.dart';
import 'package:tentura/features/beacon_view/ui/widget/items_tab.dart';
import 'package:tentura/features/inbox/domain/enum.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'beacon_view_constants.dart';
import 'beacon_view_status_bottom_sheet.dart';
import 'beacon_view_app_bar_overflow.dart';
import '../util/pinned_facts.dart';

class BeaconOperationalScrollView extends StatelessWidget {
  const BeaconOperationalScrollView({
    required this.beaconViewCubit,
    required this.screenCubit,
    required this.tabIndex,
    required this.onTabChanged,
    required this.peopleTabAttentionActive,
    required this.onPeopleTabAttentionCleared,
    required this.focusItemId,
    required this.focusUserId,
    required this.onOperationalFocusCleared,
    required this.onTapCoordinationLogEvent,
    required this.onEnterRoomSurface,
    required this.onOpenItemDiscussion,
  });

  final BeaconViewCubit beaconViewCubit;
  final ScreenCubit screenCubit;
  final int tabIndex;
  final ValueChanged<int> onTabChanged;

  /// Pulse/highlight People tab until first pointer interaction or tab change.
  final bool peopleTabAttentionActive;
  final VoidCallback onPeopleTabAttentionCleared;

  /// Coordination item / participant to focus + flash (Log row tap-to-focus).
  final String? focusItemId;
  final String? focusUserId;
  final VoidCallback onOperationalFocusCleared;
  final void Function(BeaconActivityEvent event) onTapCoordinationLogEvent;

  final void Function([CoordinationItem? focusItem]) onEnterRoomSurface;

  final void Function(CoordinationItem item) onOpenItemDiscussion;

  void _setTab(int i) {
    if (tabIndex == i) {
      onPeopleTabAttentionCleared();
      return;
    }
    onTabChanged(i);
  }

  void _onPointerDown(PointerDownEvent _) {
    if (peopleTabAttentionActive) {
      onPeopleTabAttentionCleared();
    }
    if (focusItemId != null || focusUserId != null) {
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
          p.roomParticipants.length != c.roomParticipants.length ||
          (p.roomParticipants
                  .map(
                    (e) =>
                        '${e.userId}|${e.userTitle}|${e.nextMoveText}|${e.status}|${e.nextMoveStatus}',
                  )
                  .join() !=
              c.roomParticipants
                  .map(
                    (e) =>
                        '${e.userId}|${e.userTitle}|${e.nextMoveText}|${e.status}|${e.nextMoveStatus}',
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
              c.needCoordinationHelpOffersCount,
      builder: (context, state) {
        final beaconId = state.beacon.id;
        final pinnedFacts = pinnedFactsForStrip(state.factCards);

        final tabBody = switch (idx) {
          kBeaconTabItems => ItemsTab(
            state: state,
            onOpenItemThread: onOpenItemDiscussion,
            focusItemId: focusItemId,
          ),
          kBeaconTabPeople => BeaconPeopleTabBody(
            state: state,
            beaconViewCubit: beaconViewCubit,
            l10n: l10n,
            focusUserId: focusUserId,
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
            : EdgeInsets.all(tt.screenHPadding);

        final peopleTabBadge =
            state.isBeaconMine && state.unansweredHelpOffersCount > 0
            ? state.unansweredHelpOffersCount
            : null;
        final peopleTabSecondaryBadge =
            state.needCoordinationHelpOffersCount > 0
            ? state.needCoordinationHelpOffersCount
            : null;

        // Single CustomScrollView (no NestedScrollView) so the scroll position
        // is unified: there is no outer/inner coordinator that can let the
        // body scroll past its end when the tab content fits the viewport.
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
                    onUpdateStatus:
                        state.isAuthorOrSteward &&
                            (state.beacon.status == BeaconStatus.draft ||
                                state.beacon.status.isOpenFamily ||
                                state.beacon.status ==
                                    BeaconStatus.reviewOpen)
                        ? () => unawaited(
                            showBeaconViewUpdateStatusSheet(
                              context,
                              state,
                              beaconViewCubit,
                              onOpenPeopleTab: () =>
                                  _setTab(kBeaconTabPeople),
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
                    onForward: () => unawaited(
                      beaconViewOpenForwardThenMaybeNudgeOfferHelp(
                        context,
                        beaconViewCubit,
                        l10n,
                      ),
                    ),
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
                    onSwitchToPeopleTab: () => _setTab(kBeaconTabPeople),
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
                  ),
                ),
              ),
              if (pinnedFacts.isNotEmpty)
                SliverToBoxAdapter(
                  child: ColoredBox(
                    color: scheme.surface,
                    child: BeaconPinnedFactsStrip(
                      facts: pinnedFacts,
                      beaconId: beaconId,
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
                        child: BlocBuilder<ItemsTabCubit, ItemsTabState>(
                          buildWhen: (p, c) =>
                              p.openItems != c.openItems ||
                              p.unreadDiscussionCount !=
                                  c.unreadDiscussionCount,
                          builder: (context, itemsTabState) {
                            final itemsTabBadge =
                                itemsTabState.unreadDiscussionCount > 0
                                ? itemsTabState.unreadDiscussionCount
                                : null;
                            return TenturaUnderlineTabs(
                              tabs: [
                                l10n.labelBeaconTabItems,
                                l10n.labelBeaconTabPeople,
                                l10n.labelBeaconTabLog,
                              ],
                              selectedIndex: idx,
                              onChanged: _setTab,
                              badges: [
                                itemsTabBadge,
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
                key: ValueKey<int>(idx),
                padding: tabPadding,
                sliver: SliverToBoxAdapter(child: tabBody),
              ),
              // Pads any remaining viewport so short tab content cannot be
              // scrolled out of view; collapses to zero when content overflows.
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
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: overlapsContent ? 0.5 : 0,
      child: SizedBox(
        height: _barHeight,
        width: double.infinity,
        child: child,
      ),
    );
  }

  @override
  bool shouldRebuild(covariant BeaconPinnedSegmentBarDelegate oldDelegate) {
    return child != oldDelegate.child;
  }
}
