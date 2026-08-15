import 'dart:async';

import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/threads_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/threads_state.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/features/beacon_threads/ui/util/thread_accordion_sections.dart';
import 'package:tentura/features/beacon_threads/ui/widget/item_card.dart';
import 'package:tentura/features/beacon_threads/ui/widget/stale_deadline_ticker.dart';
import 'package:tentura/features/coordination_item/ui/widget/coordination_item_edit_sheet.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/widget/accordion_expansion.dart';
import 'package:tentura/ui/widget/coordination_item_presenter.dart';
import 'package:tentura/ui/widget/focus_flash_highlight.dart';

import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_hud_action_button.dart';
import 'package:tentura/features/beacon_view/ui/widget/coordination_item_composer_sheet.dart';

BeaconParticipant? _participantForUser(
  List<BeaconParticipant> participants,
  String? userId,
) {
  if (userId == null || userId.isEmpty) return null;
  for (final p in participants) {
    if (p.userId == userId) return p;
  }
  return null;
}

List<RequestThread> _myDraftThreads(ThreadsState threadsState, String myUserId) =>
    threadsState.drafts
        .where((t) => t.item?.creatorId == myUserId)
        .toList()
      ..sort(
        (a, b) => b.item!.updatedAt.compareTo(a.item!.updatedAt),
      );

void _openCoordinationComposer(
  BuildContext context, {
  required BeaconViewState state,
  required CoordinationItemKind kind,
  CoordinationItem? existingDraft,
}) {
  final beaconViewCubit = context.read<BeaconViewCubit>();
  unawaited(
    showCoordinationItemComposerSheet(
      context,
      kind: kind,
      beaconId: state.beacon.id,
      participants: state.roomParticipants,
      participantsLoaded: state.roomParticipantsLoaded,
      participantsUpdates: beaconViewCubit.stream.map(
        (s) => (
          participants: s.roomParticipants,
          loaded: s.roomParticipantsLoaded,
        ),
      ),
      beaconAuthorId: state.beacon.author.id,
      myUserId: state.myProfile.id,
      isAuthorOrSteward: state.isAuthorOrSteward,
      existingDraft: existingDraft,
      onSaved: () => context.read<ThreadsCubit>().fetch(),
    ),
  );
}

VoidCallback? _threadsTabEditHandler(
  BuildContext context, {
  required CoordinationItem item,
  required BeaconViewState state,
}) {
  if (state.beacon.status != BeaconStatus.open) {
    return null;
  }
  if (!state.canCoordinateInBeaconRoom) {
    return null;
  }
  final myId = state.myProfile.id;

  if (!item.published &&
      item.creatorId == myId &&
      (item.kind == CoordinationItemKind.ask ||
          item.kind == CoordinationItemKind.promise ||
          item.kind == CoordinationItemKind.blocker)) {
    return () => _openCoordinationComposer(
      context,
      state: state,
      kind: item.kind,
      existingDraft: item,
    );
  }

  if (!item.published || !item.isActive) {
    return null;
  }

  return () => unawaited(
    showCoordinationItemEditSheet(
      context,
      item: item,
      onSaved: () => context.read<ThreadsCubit>().fetch(),
    ),
  );
}

class ThreadsList extends StatelessWidget {
  const ThreadsList({
    required this.beaconState,
    required this.onOpenThread,
    this.onSwitchToPeopleTab,
    this.focusThreadId,
    this.selectedThreadId,
    super.key,
  });

  final BeaconViewState beaconState;
  final void Function(RequestThread thread) onOpenThread;

  /// General card face pile tap — switches to People tab.
  final VoidCallback? onSwitchToPeopleTab;

  /// When set, the matching thread row is highlighted (Log row tap-to-focus).
  final String? focusThreadId;

  /// Selected-row indicator — only while an expanded split shows this thread.
  final String? selectedThreadId;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;

    return BlocBuilder<ThreadsCubit, ThreadsState>(
      buildWhen: (prev, curr) {
        if (curr.status is StateIsLoading && prev.threads.isEmpty) {
          return true;
        }
        return prev != curr;
      },
      builder: (context, threadsState) {
        if (threadsState.status is StateIsLoading &&
            threadsState.threads.isEmpty) {
          return const Center(child: CircularProgressIndicator.adaptive());
        }

        final general = threadsState.general;
        final activeThreads = threadsState.active;
        final closedThreads = threadsState.closed;
        final myUserId = beaconState.myProfile.id;
        final myDrafts = _myDraftThreads(threadsState, myUserId);
        final focusId = focusThreadId?.trim();
        final hasFocus = focusId != null && focusId.isNotEmpty;
        final focusInClosed =
            hasFocus && closedThreads.any((t) => t.threadId == focusId);
        final focusInDrafts =
            hasFocus && myDrafts.any((d) => d.threadId == focusId);
        final focusInActive =
            hasFocus && activeThreads.any((t) => t.threadId == focusId);
        final activeForMeOnly = threadsState.activeForMeOnly;
        final activeFoldTitle =
            activeForMeOnly &&
                    activeThreads.length <
                        threadsState.threads
                            .where(
                              (t) =>
                                  t.item != null &&
                                  t.item!.published &&
                                  t.item!.isActive,
                            )
                            .length
            ? l10n.beaconItemsActiveFoldTitleFiltered(
                activeThreads.length,
                threadsState.threads
                    .where(
                      (t) =>
                          t.item != null &&
                          t.item!.published &&
                          t.item!.isActive,
                    )
                    .length,
              )
            : l10n.beaconItemsActiveFoldTitle(
                activeForMeOnly
                    ? activeThreads.length
                    : threadsState.threads
                        .where(
                          (t) =>
                              t.item != null &&
                              t.item!.published &&
                              t.item!.isActive,
                        )
                        .length,
              );
        final myDraftCount = myDrafts.length;
        final hasSemanticItems = activeThreads.isNotEmpty ||
            closedThreads.isNotEmpty ||
            myDraftCount > 0;

        final canCoordinate = beaconState.canCoordinateInBeaconRoom;
        final showCoordinationCtas = canCoordinate;
        // Row/fold visibility follows the server's authorization union
        // (ThreadsState.threads), never the narrower client-side
        // canNavigateBeaconRoom/canCoordinateInBeaconRoom predicates — an
        // item-only participant who lacks room admission must still see
        // their own thread (architecture.md §4.4).
        final showActiveFold = canCoordinate || activeThreads.isNotEmpty;
        final showClosedFold = closedThreads.isNotEmpty;
        final showDrafts = myDraftCount > 0;
        final showGeneral = general != null;
        final requestedSectionId = threadsTabAccordionSectionId(
          focusInDrafts: focusInDrafts,
          focusInClosed: focusInClosed,
          showActiveFold: showActiveFold,
          showClosedFold: showClosedFold,
          showDrafts: showDrafts,
        );

        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: tt.screenHPadding,
            vertical: tt.rowGap,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showCoordinationCtas)
                Padding(
                  padding: EdgeInsets.only(
                    top: tt.rowGap,
                    bottom: tt.tightGap * 2,
                  ),
                  child: _ActiveCoordinationCtas(state: beaconState),
                ),
              if (beaconState.isRoomAdmissionBlocked)
                Padding(
                  padding: EdgeInsets.only(top: tt.sectionGap * 2),
                  child: Center(
                    child: Text(
                      beaconState.coordinationDeniesRoomAdmission
                          ? l10n.beaconRoomNoAdmission
                          : l10n.beaconRoomWaitingForApproval,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                )
              else if (!hasSemanticItems && !showActiveFold && !showGeneral)
                Padding(
                  padding: EdgeInsets.only(top: tt.sectionGap * 2),
                  child: Center(
                    child: Text(
                      l10n.beaconItemsEmptyPlaceholder,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              if (showGeneral) ...[
                SizedBox(height: tt.rowGap),
                FocusFlashHighlight(
                  active: hasFocus && focusId == RequestThread.generalId,
                  child: ItemCard(
                    key: threadRowKey(general),
                    thread: general,
                    viewerProfile: beaconState.myProfile,
                    participants: beaconState.roomParticipants,
                    resolvedUnreadCount:
                        threadsState.resolvedUnreadFor(general),
                    isSelected: selectedThreadId == general.threadId,
                    onOpenThread: onOpenThread,
                    generalBeacon: beaconState.beacon,
                    generalInvolvedProfiles: beaconState.activeHelpOfferUsers,
                    onGeneralFacePileTap: onSwitchToPeopleTab,
                  ),
                ),
              ],
              AccordionExpansionGroup(
                initialExpandedId: requestedSectionId,
                requestedExpandedId: requestedSectionId,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (showActiveFold) ...[
                      SizedBox(height: tt.rowGap),
                      AccordionExpansionTile(
                        id: ThreadAccordionSection.active,
                        initiallyExpanded: true,
                        title: Text(
                          activeFoldTitle,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        leading: const Icon(Icons.bolt_outlined),
                        headerAction: Semantics(
                          button: true,
                          checked: activeForMeOnly,
                          label: l10n.beaconItemsActiveForMeFilterSemantics,
                          child: BeaconHudActionButton(
                            icon: Icons.person_outline,
                            label: l10n.beaconItemsActiveForMeFilter,
                            filled: activeForMeOnly,
                            onPressed: () => context
                                .read<ThreadsCubit>()
                                .setActiveForMeOnly(!activeForMeOnly),
                          ),
                        ),
                        children: [
                          if (activeForMeOnly &&
                              activeThreads.isEmpty &&
                              threadsState.threads.any(
                                (t) =>
                                    t.item != null &&
                                    t.item!.published &&
                                    t.item!.isActive,
                              ))
                            Padding(
                              padding: EdgeInsets.only(bottom: tt.cardGap),
                              child: Center(
                                child: Text(
                                  l10n.beaconItemsActiveForMeEmpty,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                ),
                              ),
                            ),
                          if (activeThreads.isEmpty)
                            Padding(
                              padding: EdgeInsets.only(bottom: tt.cardGap),
                              child: Center(
                                child: Text(
                                  l10n.threadNoActiveItems,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                ),
                              ),
                            ),
                          StaleDeadlineTicker(
                            items: activeThreads
                                .map((t) => t.item!)
                                .toList(),
                            child: Column(
                              children: [
                                for (final thread in activeThreads)
                                  Padding(
                                    padding:
                                        EdgeInsets.only(bottom: tt.cardGap),
                                    child: FocusFlashHighlight(
                                      active:
                                          hasFocus &&
                                          focusInActive &&
                                          thread.threadId == focusId,
                                      child: _ThreadCardAnimatedRow(
                                        key: ValueKey(thread.threadId),
                                        thread: thread,
                                        beaconState: beaconState,
                                        threadsState: threadsState,
                                        selectedThreadId: selectedThreadId,
                                        onOpenThread: onOpenThread,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (showClosedFold) ...[
                      SizedBox(height: tt.rowGap),
                      AccordionExpansionTile(
                        id: ThreadAccordionSection.closed,
                        initiallyExpanded: focusInClosed,
                        leading: const Icon(Icons.check_circle_outline),
                        title: Text(
                          l10n.threadClosedFoldTitle(closedThreads.length),
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        children: [
                          for (final thread in closedThreads)
                            Padding(
                              padding: EdgeInsets.only(bottom: tt.cardGap),
                              child: FocusFlashHighlight(
                                active:
                                    hasFocus && thread.threadId == focusId,
                                child: _buildSemanticCard(
                                  context,
                                  thread: thread,
                                  beaconState: beaconState,
                                  threadsState: threadsState,
                                  selectedThreadId: selectedThreadId,
                                  onOpenThread: onOpenThread,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                    if (showDrafts) ...[
                      SizedBox(height: tt.rowGap),
                      AccordionExpansionTile(
                        id: ThreadAccordionSection.drafts,
                        initiallyExpanded: focusInDrafts,
                        title: Text(
                          l10n.threadDraftsFoldTitle(myDraftCount),
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        leading: const Icon(Icons.drafts_outlined),
                        children: [
                          for (final thread in myDrafts)
                            Padding(
                              padding: EdgeInsets.only(bottom: tt.cardGap),
                              child: FocusFlashHighlight(
                                active:
                                    hasFocus && thread.threadId == focusId,
                                child: _DraftThreadRow(
                                  thread: thread,
                                  beaconState: beaconState,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSemanticCard(
    BuildContext context, {
    required RequestThread thread,
    required BeaconViewState beaconState,
    required ThreadsState threadsState,
    required String? selectedThreadId,
    required void Function(RequestThread thread) onOpenThread,
  }) {
    final item = thread.item!;
    return ItemCard(
      key: threadRowKey(thread),
      thread: thread,
      viewerProfile: beaconState.myProfile,
      participants: beaconState.roomParticipants,
      resolvedUnreadCount: threadsState.resolvedUnreadFor(thread),
      creatorParticipant: _participantForUser(
        beaconState.roomParticipants,
        item.creatorId,
      ),
      targetParticipant: _participantForUser(
        beaconState.roomParticipants,
        item.targetPersonId,
      ),
      responsibleParticipant: _participantForUser(
        beaconState.roomParticipants,
        item.responsibleUserId,
      ),
      isSelected: selectedThreadId == thread.threadId,
      onOpenThread: onOpenThread,
      onEdit: _threadsTabEditHandler(
        context,
        item: item,
        state: beaconState,
      ),
    );
  }
}

class _ActiveCoordinationCtas extends StatelessWidget {
  const _ActiveCoordinationCtas({required this.state});

  final BeaconViewState state;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final wide = context.windowClass != WindowClass.compact;

    final askBtn = BeaconHudActionButton(
      key: TestIds.key(TestIds.coordinationAskCreate),
      icon: coordinationKindIcon(CoordinationItemKind.ask),
      label: l10n.coordinationAskCardLabel,
      onPressed: () => _openCoordinationComposer(
        context,
        state: state,
        kind: CoordinationItemKind.ask,
      ),
    );
    final promiseBtn = BeaconHudActionButton(
      key: TestIds.key(TestIds.coordinationPromiseCreate),
      icon: coordinationKindIcon(CoordinationItemKind.promise),
      label: l10n.coordinationPromiseCardLabel,
      onPressed: () => _openCoordinationComposer(
        context,
        state: state,
        kind: CoordinationItemKind.promise,
      ),
    );

    return Row(
      children: [
        if (wide) askBtn else Expanded(child: askBtn),
        SizedBox(width: context.tt.rowGap),
        if (wide) promiseBtn else Expanded(child: promiseBtn),
        SizedBox(width: context.tt.rowGap),
        BeaconHudIconActionButton(
          key: TestIds.key(TestIds.coordinationBlockerCreate),
          icon: coordinationKindIcon(CoordinationItemKind.blocker),
          tooltip: l10n.coordinationBlockerCardLabel,
          onPressed: () => _openCoordinationComposer(
            context,
            state: state,
            kind: CoordinationItemKind.blocker,
          ),
        ),
      ],
    );
  }
}

class _ThreadCardAnimatedRow extends StatefulWidget {
  const _ThreadCardAnimatedRow({
    required this.thread,
    required this.beaconState,
    required this.threadsState,
    required this.onOpenThread,
    required this.selectedThreadId,
    super.key,
  });

  final RequestThread thread;
  final BeaconViewState beaconState;
  final ThreadsState threadsState;
  final String? selectedThreadId;
  final void Function(RequestThread thread) onOpenThread;

  @override
  State<_ThreadCardAnimatedRow> createState() => _ThreadCardAnimatedRowState();
}

class _ThreadCardAnimatedRowState extends State<_ThreadCardAnimatedRow> {
  bool _visible = true;
  bool _entered = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() => _entered = true);
      }
    });
  }

  Future<void> _animateThenCall(Future<void> Function() action) async {
    setState(() => _visible = false);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    await action();
    if (!mounted) return;
    if (context.read<ThreadsCubit>().state.hasError) {
      setState(() => _visible = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final thread = widget.thread;
    final item = thread.item!;
    final beaconState = widget.beaconState;
    final myUserId = beaconState.myProfile.id;

    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      child: AnimatedOpacity(
        opacity: _visible && _entered ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 150),
        child: _visible
            ? ItemCard(
                key: threadRowKey(thread),
                thread: thread,
                viewerProfile: beaconState.myProfile,
                participants: beaconState.roomParticipants,
                resolvedUnreadCount:
                    widget.threadsState.resolvedUnreadFor(thread),
                creatorParticipant: _participantForUser(
                  beaconState.roomParticipants,
                  item.creatorId,
                ),
                targetParticipant: _participantForUser(
                  beaconState.roomParticipants,
                  item.targetPersonId,
                ),
                responsibleParticipant: _participantForUser(
                  beaconState.roomParticipants,
                  item.responsibleUserId,
                ),
                isSelected: widget.selectedThreadId == thread.threadId,
                onOpenThread: widget.onOpenThread,
                onEdit: _threadsTabEditHandler(
                  context,
                  item: item,
                  state: beaconState,
                ),
                onRemind: () => unawaited(
                  _animateThenCall(
                    () => context.read<ThreadsCubit>().remindItem(item.id),
                  ),
                ),
                onResolve: () => unawaited(
                  _animateThenCall(() async {
                    final cubit = context.read<ThreadsCubit>();
                    if (item.kind == CoordinationItemKind.plan &&
                        item.isPlanStep) {
                      await cubit.resolvePlanStep(item.id);
                    } else if (item.kind == CoordinationItemKind.ask) {
                      await cubit.resolveAsk(item.id);
                    } else if (item.kind == CoordinationItemKind.promise) {
                      await cubit.resolvePromise(item.id);
                    } else {
                      await cubit.resolveBlocker(item.id);
                    }
                  }),
                ),
                onCancel: () => unawaited(
                  _animateThenCall(() async {
                    final cubit = context.read<ThreadsCubit>();
                    if (item.kind == CoordinationItemKind.ask) {
                      await cubit.cancelAsk(item.id);
                    } else if (item.kind == CoordinationItemKind.promise) {
                      await cubit.cancelPromise(item.id);
                    } else {
                      await cubit.cancelBlocker(item.id);
                    }
                  }),
                ),
                onAccept: switch (item.kind) {
                  CoordinationItemKind.ask => () => unawaited(
                    _animateThenCall(
                      () => context.read<ThreadsCubit>().acceptAsk(item.id),
                    ),
                  ),
                  CoordinationItemKind.promise =>
                    item.isOpen && item.targetPersonId == myUserId
                        ? () => unawaited(
                            _animateThenCall(
                              () => context
                                  .read<ThreadsCubit>()
                                  .acceptPromise(item.id),
                            ),
                          )
                        : null,
                  _ => null,
                },
                onReject: null,
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}

class _DraftThreadRow extends StatelessWidget {
  const _DraftThreadRow({
    required this.thread,
    required this.beaconState,
  });

  final RequestThread thread;
  final BeaconViewState beaconState;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final item = thread.item!;
    final participants = beaconState.roomParticipants;
    final cubit = context.read<ThreadsCubit>();

    Future<void> refresh() => cubit.fetch();

    Future<void> onDelete() async {
      await confirmDeleteCoordinationDraft(
        context,
        kind: item.kind,
        itemId: item.id,
        onDeleted: refresh,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ItemCard(
          thread: thread,
          viewerProfile: beaconState.myProfile,
          participants: participants,
          creatorParticipant: _participantForUser(
            participants,
            item.creatorId,
          ),
          targetParticipant: _participantForUser(
            participants,
            item.targetPersonId,
          ),
          onEdit: () => _openCoordinationComposer(
            context,
            state: beaconState,
            kind: item.kind,
            existingDraft: item,
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TenturaTextAction(
            label: l10n.buttonDelete,
            tone: TenturaTone.danger,
            icon: const Icon(Icons.delete_outline),
            onPressed: () => unawaited(onDelete()),
          ),
        ),
      ],
    );
  }
}
