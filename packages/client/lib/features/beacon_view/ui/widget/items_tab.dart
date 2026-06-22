import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart'
    show BeaconFactCardStatusBits;
import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/features/coordination_item/ui/widget/coordination_item_edit_sheet.dart';
import 'package:tentura/features/beacon_room/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_room/ui/widget/fact_actions_sheet.dart';
import 'package:tentura/features/beacon_room/ui/widget/room_file_attachment_open.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_accordion_sections.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/accordion_expansion.dart';
import 'package:tentura/ui/widget/beacon_pinned_fact_carousel.dart';
import 'package:tentura/ui/widget/coordination_item_presenter.dart';
import 'package:tentura/ui/widget/focus_flash_highlight.dart';

import 'package:tentura/features/coordination_item/ui/widget/item_card.dart';

import '../bloc/beacon_view_state.dart';
import '../bloc/items_tab_cubit.dart';
import '../bloc/items_tab_state.dart';
import 'beacon_definition_body.dart';
import 'beacon_hud_action_button.dart';
import 'coordination_item_composer_sheet.dart';

List<BeaconFactCard> _pinnedFactsForCarousel(List<BeaconFactCard> factCards) {
  return factCards
      .where((f) => f.status != BeaconFactCardStatusBits.removed)
      .toList(growable: false)
    ..sort((a, b) {
      final ta = a.updatedAt ?? a.createdAt;
      final tb = b.updatedAt ?? b.createdAt;
      return tb.compareTo(ta);
    });
}

List<CoordinationItem> _itemsTabVisibleItems(List<CoordinationItem> items) =>
    items.where((i) => i.kind != CoordinationItemKind.plan).toList();

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

List<CoordinationItem> _myDraftItems(ItemsTabState tabState, String myUserId) {
  final drafts = <CoordinationItem>[
    ...tabState.draftAskItems,
    ...tabState.draftPromiseItems,
    ...tabState.draftBlockerItems,
  ];
  return drafts.where((d) => d.creatorId == myUserId).toList()
    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
}

void _openCoordinationComposer(
  BuildContext context, {
  required BeaconViewState state,
  required CoordinationItemKind kind,
  CoordinationItem? existingDraft,
}) {
  unawaited(
    showCoordinationItemComposerSheet(
      context,
      kind: kind,
      beaconId: state.beacon.id,
      participants: state.roomParticipants,
      beaconAuthorId: state.beacon.author.id,
      myUserId: state.myProfile.id,
      isAuthorOrSteward: state.isAuthorOrSteward,
      existingDraft: existingDraft,
      onSaved: () => context.read<ItemsTabCubit>().fetch(),
    ),
  );
}

VoidCallback? _itemsTabEditHandler(
  BuildContext context, {
  required CoordinationItem item,
  required BeaconViewState state,
}) {
  if (state.beacon.lifecycle != BeaconLifecycle.open) {
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
          onSaved: () => context.read<ItemsTabCubit>().fetch(),
        ),
      );
}

class ItemsTab extends StatelessWidget {
  const ItemsTab({
    required this.state,
    required this.onOpenItemThread,
    this.focusItemId,
    super.key,
  });

  final BeaconViewState state;
  final void Function(CoordinationItem item) onOpenItemThread;

  /// When set, the matching item is scrolled into view, its fold expanded, and
  /// a brief highlight flash is played (Log row tap-to-focus).
  final String? focusItemId;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;

    return BlocBuilder<ItemsTabCubit, ItemsTabState>(
      buildWhen: (prev, curr) {
        if (curr.isLoading) {
          return prev.openItems.isEmpty &&
              prev.closedItems.isEmpty &&
              prev.draftAskItems.isEmpty &&
              prev.draftPromiseItems.isEmpty &&
              prev.draftBlockerItems.isEmpty;
        }
        return true;
      },
      builder: (context, tabState) {
        if (tabState.isLoading) {
          return const Center(child: CircularProgressIndicator.adaptive());
        }

        final openItems = _itemsTabVisibleItems(tabState.openItems);
        final closedItems = _itemsTabVisibleItems(tabState.closedItems);
        final myUserId = state.myProfile.id;
        final lookupItems = _itemsTabVisibleItems([
          ...tabState.openItems,
          ...tabState.closedItems,
        ]);
        final myDrafts = _myDraftItems(tabState, myUserId);
        final focusId = focusItemId?.trim();
        final hasFocus = focusId != null && focusId.isNotEmpty;
        final focusInClosed =
            hasFocus && closedItems.any((i) => i.id == focusId);
        final focusInDrafts = hasFocus && myDrafts.any((d) => d.id == focusId);
        final displayedOpenItems = filterActiveItemsForUser(
          openItems: openItems,
          lookupItems: lookupItems,
          userId: myUserId,
          forMeOnly: tabState.activeForMeOnly,
          alwaysIncludeItemId:
              hasFocus && openItems.any((i) => i.id == focusId) ? focusId : null,
        );
        final activeForMeOnly = tabState.activeForMeOnly;
        final activeFoldTitle = activeForMeOnly &&
                displayedOpenItems.length < openItems.length
            ? l10n.beaconItemsActiveFoldTitleFiltered(
                displayedOpenItems.length,
                openItems.length,
              )
            : l10n.beaconItemsActiveFoldTitle(
                activeForMeOnly ? displayedOpenItems.length : openItems.length,
              );
        final myDraftCount = myDrafts.length;
        final hasItems = openItems.isNotEmpty ||
            closedItems.isNotEmpty ||
            myDraftCount > 0;
        final beaconId = state.beacon.id;

        final canCoordinate = state.canCoordinateInBeaconRoom;
        final showCoordinationCtas = canCoordinate;
        final showActiveFold = canCoordinate || openItems.isNotEmpty;
        final showClosedFold = closedItems.isNotEmpty &&
            (canCoordinate || openItems.isNotEmpty);

        final pinnedFacts = _pinnedFactsForCarousel(state.factCards);
        final showFacts = pinnedFacts.isNotEmpty;
        final showDrafts = myDraftCount > 0;
        final requestedSectionId = itemsTabAccordionSectionId(
          focusInDrafts: focusInDrafts,
          focusInClosed: focusInClosed,
          showActiveFold: showActiveFold,
          showClosedFold: showClosedFold,
          showDrafts: showDrafts,
          showFacts: showFacts,
        );

        // Parent CustomScrollView owns scrolling; nested ListView caused
        // parentDataDirty semantics asserts on web.
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!hasItems && !showActiveFold)
                Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: Center(
                    child: Text(
                      l10n.beaconItemsEmptyPlaceholder,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                ),
              AccordionExpansionGroup(
                initialExpandedId: requestedSectionId,
                requestedExpandedId: requestedSectionId,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (showActiveFold) ...[
                      const SizedBox(height: 8),
                      AccordionExpansionTile(
                        id: BeaconItemsAccordionSection.active,
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
                                .read<ItemsTabCubit>()
                                .setActiveForMeOnly(!activeForMeOnly),
                          ),
                        ),
                        children: [
                      if (showCoordinationCtas) ...[
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _ActiveCoordinationCtas(state: state),
                        ),
                      ],
                      if (activeForMeOnly &&
                          displayedOpenItems.isEmpty &&
                          openItems.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Center(
                            child: Text(
                              l10n.beaconItemsActiveForMeEmpty,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                          ),
                        ),
                      _StaleDeadlineTicker(
                        items: displayedOpenItems,
                        child: Column(
                          children: [
                      for (final item in displayedOpenItems)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: FocusFlashHighlight(
                              active: hasFocus && item.id == focusId,
                              child: _ItemCardAnimatedRow(
                              key: ValueKey(item.id),
                              item: item,
                              viewerId: myUserId,
                              creatorParticipant: _participantForUser(
                                state.roomParticipants,
                                item.creatorId,
                              ),
                              targetParticipant: _participantForUser(
                                state.roomParticipants,
                                item.targetPersonId,
                              ),
                              responsibleParticipant: _participantForUser(
                                state.roomParticipants,
                                item.responsibleUserId,
                              ),
                              onEdit: _itemsTabEditHandler(
                                context,
                                item: item,
                                state: state,
                              ),
                              onOpenItemThread: onOpenItemThread,
                              resolveAction: () async {
                                final cubit = context.read<ItemsTabCubit>();
                                if (item.kind == CoordinationItemKind.plan &&
                                    item.isPlanStep) {
                                  await cubit.resolvePlanStep(item.id);
                                } else if (item.kind ==
                                    CoordinationItemKind.ask) {
                                  await cubit.resolveAsk(item.id);
                                } else if (item.kind ==
                                    CoordinationItemKind.promise) {
                                  await cubit.resolvePromise(item.id);
                                } else {
                                  await cubit.resolveBlocker(item.id);
                                }
                              },
                              cancelAction: () async {
                                final cubit = context.read<ItemsTabCubit>();
                                if (item.kind == CoordinationItemKind.ask) {
                                  await cubit.cancelAsk(item.id);
                                } else if (item.kind ==
                                    CoordinationItemKind.promise) {
                                  await cubit.cancelPromise(item.id);
                                } else {
                                  await cubit.cancelBlocker(item.id);
                                }
                              },
                              acceptAction: switch (item.kind) {
                                CoordinationItemKind.ask => () => context
                                    .read<ItemsTabCubit>()
                                    .acceptAsk(item.id),
                                CoordinationItemKind.promise =>
                                  item.isOpen &&
                                          item.targetPersonId == myUserId
                                      ? () => context
                                          .read<ItemsTabCubit>()
                                          .acceptPromise(item.id)
                                      : null,
                                CoordinationItemKind.resolution => () =>
                                    context
                                        .read<ItemsTabCubit>()
                                        .acceptResolution(item.id),
                                _ => null,
                              },
                              rejectAction:
                                  item.kind == CoordinationItemKind.resolution
                                      ? () => context
                                          .read<ItemsTabCubit>()
                                          .rejectResolution(item.id)
                                      : null,
                              remindAction: () => context
                                  .read<ItemsTabCubit>()
                                  .remindItem(item.id),
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
                      const SizedBox(height: 8),
                      AccordionExpansionTile(
                        id: BeaconItemsAccordionSection.closed,
                        initiallyExpanded: focusInClosed,
                        leading: const Icon(Icons.check_circle_outline),
                        title: Text(
                          'Closed (${closedItems.length})',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        children: [
                      for (final item in closedItems)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: FocusFlashHighlight(
                            active: hasFocus && item.id == focusId,
                            child: ItemCard(
                              item: item,
                              creatorParticipant: _participantForUser(
                                state.roomParticipants,
                                item.creatorId,
                              ),
                              targetParticipant: _participantForUser(
                                state.roomParticipants,
                                item.targetPersonId,
                              ),
                              onEdit: _itemsTabEditHandler(
                                context,
                                item: item,
                                state: state,
                              ),
                              onOpenItemThread: onOpenItemThread,
                            ),
                          ),
                        ),
                        ],
                      ),
                    ],
                    if (showDrafts) ...[
                      const SizedBox(height: 8),
                      AccordionExpansionTile(
                        id: BeaconItemsAccordionSection.drafts,
                        initiallyExpanded: focusInDrafts,
                        title: Text(
                          '${l10n.myWorkSectionDrafts} ($myDraftCount)',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        leading: const Icon(Icons.drafts_outlined),
                        children: [
                      for (final draft in myDrafts)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: FocusFlashHighlight(
                            active: hasFocus && draft.id == focusId,
                            child: _MyDraftItemRow(
                              draft: draft,
                              state: state,
                            ),
                          ),
                        ),
                        ],
                      ),
                    ],
                    if (showFacts) ...[
                      const SizedBox(height: 8),
                      _BeaconFactsSection(
                        pinnedFacts: pinnedFacts,
                        beaconId: beaconId,
                      ),
                    ],
                    const SizedBox(height: 8),
                    _BeaconDefinitionSection(state: state),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ActiveCoordinationCtas extends StatelessWidget {
  const _ActiveCoordinationCtas({required this.state});

  final BeaconViewState state;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;

    return Row(
      children: [
        Expanded(
          child: BeaconHudActionButton(
            icon: coordinationKindIcon(CoordinationItemKind.ask),
            label: l10n.coordinationAskCardLabel,
            onPressed: () => _openCoordinationComposer(
              context,
              state: state,
              kind: CoordinationItemKind.ask,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: BeaconHudActionButton(
            icon: coordinationKindIcon(CoordinationItemKind.promise),
            label: l10n.coordinationPromiseCardLabel,
            onPressed: () => _openCoordinationComposer(
              context,
              state: state,
              kind: CoordinationItemKind.promise,
            ),
          ),
        ),
        const SizedBox(width: 8),
        BeaconHudIconActionButton(
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

class _ItemCardAnimatedRow extends StatefulWidget {
  const _ItemCardAnimatedRow({
    required this.item,
    required this.viewerId,
    required this.creatorParticipant,
    required this.targetParticipant,
    required this.responsibleParticipant,
    required this.onOpenItemThread,
    required this.resolveAction,
    required this.cancelAction,
    this.acceptAction,
    this.rejectAction,
    this.remindAction,
    this.onEdit,
    super.key,
  });

  final CoordinationItem item;
  final String viewerId;
  final BeaconParticipant? creatorParticipant;
  final BeaconParticipant? targetParticipant;
  final BeaconParticipant? responsibleParticipant;
  final void Function(CoordinationItem item) onOpenItemThread;
  final VoidCallback? onEdit;
  final Future<void> Function() resolveAction;
  final Future<void> Function() cancelAction;
  final Future<void> Function()? acceptAction;
  final Future<void> Function()? rejectAction;
  final Future<void> Function()? remindAction;

  @override
  State<_ItemCardAnimatedRow> createState() => _ItemCardAnimatedRowState();
}

class _ItemCardAnimatedRowState extends State<_ItemCardAnimatedRow> {
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
    if (!mounted) {
      return;
    }
    await action();
    if (!mounted) {
      return;
    }
    if (context.read<ItemsTabCubit>().state.hasError) {
      setState(() => _visible = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      child: AnimatedOpacity(
        opacity: _visible && _entered ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 150),
        child: _visible
            ? ItemCard(
                item: widget.item,
                viewerId: widget.viewerId,
                creatorParticipant: widget.creatorParticipant,
                targetParticipant: widget.targetParticipant,
                responsibleParticipant: widget.responsibleParticipant,
                onOpenItemThread: widget.onOpenItemThread,
                onEdit: widget.onEdit,
                onRemind: widget.remindAction == null
                    ? null
                    : () => unawaited(
                          _animateThenCall(widget.remindAction!),
                        ),
                onResolve: () => unawaited(
                  _animateThenCall(widget.resolveAction),
                ),
                onCancel: () => unawaited(
                  _animateThenCall(widget.cancelAction),
                ),
                onAccept: widget.acceptAction == null
                    ? null
                    : () => unawaited(
                          _animateThenCall(widget.acceptAction!),
                        ),
                onReject: widget.rejectAction == null
                    ? null
                    : () => unawaited(
                          _animateThenCall(widget.rejectAction!),
                        ),
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}

class _BeaconDefinitionSection extends StatelessWidget {
  const _BeaconDefinitionSection({required this.state});

  final BeaconViewState state;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final beacon = state.beacon;

    return AccordionExpansionTile(
      id: BeaconItemsAccordionSection.definition,
      leading: const Icon(Icons.info_outline),
      title: Text(
        l10n.beaconDefinitionSectionTitle,
        style: Theme.of(context).textTheme.titleSmall,
      ),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: BeaconDefinitionBody(
            key: ValueKey('items-def-${beacon.id}'),
            beacon: beacon,
          ),
        ),
      ],
    );
  }
}

class _BeaconFactsSection extends StatelessWidget {
  const _BeaconFactsSection({
    required this.pinnedFacts,
    required this.beaconId,
  });

  final List<BeaconFactCard> pinnedFacts;
  final String beaconId;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    return AccordionExpansionTile(
      id: BeaconItemsAccordionSection.facts,
      leading: const Icon(Icons.article_outlined),
      title: Text(
        l10n.beaconItemsFactsFoldTitle,
        style: Theme.of(context).textTheme.titleSmall,
      ),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: BeaconPinnedFactCarousel(
            facts: pinnedFacts,
            factTextStyle: TenturaText.body(scheme.onSurface),
            onManageOverflow: (f) => _showFactActionsFromItemsTab(
              context,
              beaconId: beaconId,
              fact: f,
            ),
            onOpenFileAttachment: (a) => openRoomFileAttachment(
              context,
              l10n,
              a,
            ),
          ),
        ),
      ],
    );
  }
}

class _MyDraftItemRow extends StatelessWidget {
  const _MyDraftItemRow({
    required this.draft,
    required this.state,
  });

  final CoordinationItem draft;
  final BeaconViewState state;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final participants = state.roomParticipants;
    final cubit = context.read<ItemsTabCubit>();

    Future<void> refresh() => cubit.fetch();

    Future<void> onDelete() async {
      await confirmDeleteCoordinationDraft(
        context,
        kind: draft.kind,
        itemId: draft.id,
        onDeleted: refresh,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ItemCard(
          item: draft,
          creatorParticipant: _participantForUser(
            participants,
            draft.creatorId,
          ),
          targetParticipant: _participantForUser(
            participants,
            draft.targetPersonId,
          ),
          onEdit: () => _openCoordinationComposer(
            context,
            state: state,
            kind: draft.kind,
            existingDraft: draft,
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

/// Rebuilds when the nearest active-item [CoordinationItem.staleAt] passes so
/// stale chips and remind actions appear without leaving the Items tab.
class _StaleDeadlineTicker extends StatefulWidget {
  const _StaleDeadlineTicker({
    required this.items,
    required this.child,
  });

  final List<CoordinationItem> items;
  final Widget child;

  @override
  State<_StaleDeadlineTicker> createState() => _StaleDeadlineTickerState();
}

class _StaleDeadlineTickerState extends State<_StaleDeadlineTicker> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(covariant _StaleDeadlineTicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    final now = DateTime.now().toUtc();
    DateTime? nearest;
    for (final item in widget.items) {
      if (!item.isActive) continue;
      final at = item.staleAt;
      if (at == null || item.isStale) continue;
      final utc = at.toUtc();
      if (!utc.isAfter(now)) continue;
      if (nearest == null || utc.isBefore(nearest)) {
        nearest = utc;
      }
    }
    if (nearest == null) return;
    final delay = nearest.difference(now) + const Duration(milliseconds: 500);
    _timer = Timer(
      delay.isNegative ? Duration.zero : delay,
      () {
        if (!mounted) return;
        setState(() {});
        _schedule();
      },
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

Future<void> _showFactActionsFromItemsTab(
  BuildContext context, {
  required String beaconId,
  required BeaconFactCard fact,
}) async {
  final cubit = RoomCubit(beaconId: beaconId);
  try {
    await showFactActionsSheet(
      context,
      cubit: cubit,
      fact: fact,
    );
    if (context.mounted) {
      await context.read<ItemsTabCubit>().fetch();
    }
  } finally {
    await cubit.close();
  }
}
