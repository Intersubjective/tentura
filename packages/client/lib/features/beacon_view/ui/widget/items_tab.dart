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
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/beacon_pinned_fact_carousel.dart';

import 'package:tentura/features/coordination_item/ui/widget/item_card.dart';

import '../bloc/beacon_view_state.dart';
import '../bloc/items_tab_cubit.dart';
import '../bloc/items_tab_state.dart';
import 'beacon_create_plan_sheet.dart';
import 'beacon_definition_body.dart';
import 'beacon_prepared_ask_sheet.dart';
import 'beacon_prepared_promise_sheet.dart';
import 'beacon_prepared_blocker_sheet.dart';

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

List<CoordinationItem> _planFirst(List<CoordinationItem> items) {
  final copy = [...items];
  copy.sort((a, b) {
    if (a.isRootPlan == b.isRootPlan) return 0;
    return a.isRootPlan ? -1 : 1;
  });
  return copy;
}

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

VoidCallback? _itemsTabEditHandler(
  BuildContext context, {
  required CoordinationItem item,
  required BeaconViewState state,
}) {
  if (state.beacon.lifecycle != BeaconLifecycle.open) {
    return null;
  }
  final myId = state.myProfile.id;
  final isOwner = state.beacon.author.id == myId;
  final isParticipant =
      state.roomParticipants.any((p) => p.userId == myId);
  if (!isOwner && !isParticipant) {
    return null;
  }

  if (!item.published && item.kind == CoordinationItemKind.ask) {
    return () => unawaited(
          showPreparedAskEditorSheet(
            context,
            beaconId: state.beacon.id,
            onSaved: () => context.read<ItemsTabCubit>().fetch(),
            existing: item,
          ),
        );
  }

  if (!item.published && item.kind == CoordinationItemKind.promise) {
    return () => unawaited(
          showPreparedPromiseEditorSheet(
            context,
            beaconId: state.beacon.id,
            onSaved: () => context.read<ItemsTabCubit>().fetch(),
            existing: item,
          ),
        );
  }

  if (!item.published && item.kind == CoordinationItemKind.blocker) {
    return () => unawaited(
          showPreparedBlockerEditorSheet(
            context,
            beaconId: state.beacon.id,
            onSaved: () => context.read<ItemsTabCubit>().fetch(),
            existing: item,
          ),
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
    super.key,
  });

  final BeaconViewState state;
  final void Function(CoordinationItem item) onOpenItemThread;

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

        final openItems = tabState.openItems;
        final closedItems = tabState.closedItems;
        final draftAskItems = tabState.draftAskItems;
        final draftPromiseItems = tabState.draftPromiseItems;
        final draftBlockerItems = tabState.draftBlockerItems;
        final draftCount = draftAskItems.length +
            draftPromiseItems.length +
            draftBlockerItems.length;
        final myUserId = state.myProfile.id;
        final hasItems = openItems.isNotEmpty ||
            closedItems.isNotEmpty ||
            draftCount > 0;
        final beaconId = state.beacon.id;
        final isOwner = state.beacon.author.id == state.myProfile.id;

        BeaconParticipant? myParticipant;
        for (final p in state.roomParticipants) {
          if (p.userId == state.myProfile.id) {
            myParticipant = p;
            break;
          }
        }

        final canCreatePlan = isOwner || myParticipant != null;
        final showCoordinationCtas = canCreatePlan &&
            state.beacon.lifecycle == BeaconLifecycle.open;
        final showActiveFold = canCreatePlan || openItems.isNotEmpty;
        final showClosedFold = closedItems.isNotEmpty &&
            (canCreatePlan || openItems.isNotEmpty);

        final pinnedFacts = _pinnedFactsForCarousel(state.factCards);
        final showFacts = pinnedFacts.isNotEmpty;

        // Parent CustomScrollView owns scrolling; nested ListView caused
        // parentDataDirty semantics asserts on web.
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isOwner && draftCount > 0) ...[
                const SizedBox(height: 8),
                ExpansionTile(
                  title: Text(
                    '${l10n.myWorkSectionDrafts} ($draftCount)',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  leading: const Icon(Icons.drafts_outlined),
                  children: [
                    for (final draft in draftAskItems)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _PreparedDraftAskRow(
                          draft: draft,
                          beaconId: beaconId,
                          participants: state.roomParticipants,
                          beaconAuthorId: state.beacon.author.id,
                        ),
                      ),
                    for (final draft in draftPromiseItems)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _PreparedDraftPromiseRow(
                          draft: draft,
                          beaconId: beaconId,
                          participants: state.roomParticipants,
                          beaconAuthorId: state.beacon.author.id,
                        ),
                      ),
                    for (final draft in draftBlockerItems)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _PreparedDraftBlockerRow(
                          draft: draft,
                          beaconId: beaconId,
                          participants: state.roomParticipants,
                        ),
                      ),
                  ],
                ),
              ],
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
                )
              else if (showActiveFold || showClosedFold) ...[
                if (showActiveFold) ...[
                  const SizedBox(height: 8),
                  ExpansionTile(
                    initiallyExpanded: true,
                    title: Text(
                      'Active (${openItems.length})',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    leading: const Icon(Icons.bolt_outlined),
                    children: [
                      if (showCoordinationCtas) ...[
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _ActiveCoordinationCtas(
                            beaconId: beaconId,
                            onSaved: () =>
                                context.read<ItemsTabCubit>().fetch(),
                          ),
                        ),
                      ],
                      if (openItems.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: _CreatePlanCta(),
                        )
                      else
                        for (final item in _planFirst(openItems))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _ItemCardAnimatedRow(
                              key: ValueKey(item.id),
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
                            ),
                          ),
                    ],
                  ),
                ],
                if (showClosedFold) ...[
                  const SizedBox(height: 8),
                  ExpansionTile(
                    title: Text(
                      'Closed (${closedItems.length})',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    children: [
                      for (final item in _planFirst(closedItems))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
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
                    ],
                  ),
                ],
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
        );
      },
    );
  }
}

class _ActiveCoordinationCtas extends StatelessWidget {
  const _ActiveCoordinationCtas({
    required this.beaconId,
    required this.onSaved,
  });

  final String beaconId;
  final VoidCallback onSaved;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;

    void refresh() => onSaved();

    return Row(
      children: [
        Expanded(
          child: TenturaCommandButton(
            label: l10n.coordinationAskCardLabel,
            icon: const Icon(Icons.help_outline),
            onPressed: () => unawaited(
              showPreparedAskEditorSheet(
                context,
                beaconId: beaconId,
                onSaved: refresh,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TenturaCommandButton(
            label: l10n.coordinationPromiseCardLabel,
            icon: const Icon(Icons.front_hand_outlined),
            onPressed: () => unawaited(
              showPreparedPromiseEditorSheet(
                context,
                beaconId: beaconId,
                onSaved: refresh,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _BlockerIconCommandButton(
          tooltip: l10n.coordinationBlockerCardLabel,
          onPressed: () => unawaited(
            showPreparedBlockerEditorSheet(
              context,
              beaconId: beaconId,
              onSaved: refresh,
            ),
          ),
        ),
      ],
    );
  }
}

class _BlockerIconCommandButton extends StatelessWidget {
  const _BlockerIconCommandButton({
    required this.tooltip,
    required this.onPressed,
  });

  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final color = tt.info;

    return Semantics(
      button: true,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(44, 44),
            padding: EdgeInsets.zero,
            side: BorderSide(color: tt.skyBorder),
            foregroundColor: color,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(tt.buttonRadius),
            ),
          ),
          child: const Icon(Icons.block, size: 20),
        ),
      ),
    );
  }
}

class _CreatePlanCta extends StatelessWidget {
  const _CreatePlanCta();

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;

    return FilledButton.tonal(
      onPressed: () => unawaited(
        showBeaconCreatePlanSheet(
          context,
          onSaved: () => context.read<ItemsTabCubit>().fetch(),
        ),
      ),
      child: Text(l10n.itemsTabCreatePlanCta),
    );
  }
}

class _ItemCardAnimatedRow extends StatefulWidget {
  const _ItemCardAnimatedRow({
    required this.item,
    required this.creatorParticipant,
    required this.targetParticipant,
    required this.onOpenItemThread,
    required this.resolveAction,
    required this.cancelAction,
    this.acceptAction,
    this.rejectAction,
    this.onEdit,
    super.key,
  });

  final CoordinationItem item;
  final BeaconParticipant? creatorParticipant;
  final BeaconParticipant? targetParticipant;
  final void Function(CoordinationItem item) onOpenItemThread;
  final VoidCallback? onEdit;
  final Future<void> Function() resolveAction;
  final Future<void> Function() cancelAction;
  final Future<void> Function()? acceptAction;
  final Future<void> Function()? rejectAction;

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
                creatorParticipant: widget.creatorParticipant,
                targetParticipant: widget.targetParticipant,
                onOpenItemThread: widget.onOpenItemThread,
                onEdit: widget.onEdit,
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

    return ExpansionTile(
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

    return ExpansionTile(
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

class _PreparedDraftPromiseRow extends StatelessWidget {
  const _PreparedDraftPromiseRow({
    required this.draft,
    required this.beaconId,
    required this.participants,
    required this.beaconAuthorId,
  });

  final CoordinationItem draft;
  final String beaconId;
  final List<BeaconParticipant> participants;
  final String beaconAuthorId;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final cubit = context.read<ItemsTabCubit>();

    Future<void> refresh() => cubit.fetch();

    Future<void> openPublish() => showPreparedPromisePublishSheet(
          context,
          draft: draft,
          participants: participants,
          beaconAuthorId: beaconAuthorId,
          onSaved: refresh,
        );

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
          onEdit: () => unawaited(
            showPreparedPromiseEditorSheet(
              context,
              beaconId: beaconId,
              onSaved: refresh,
              existing: draft,
            ),
          ),
          onOpenItemThread: (_) => unawaited(openPublish()),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            alignment: WrapAlignment.end,
            children: [
              TenturaTextAction(
                label: l10n.buttonPublish,
                icon: const Icon(Icons.send_outlined),
                onPressed: () => unawaited(openPublish()),
              ),
              TenturaTextAction(
                label: l10n.myWorkEditDraft,
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => unawaited(
                  showPreparedPromiseEditorSheet(
                    context,
                    beaconId: beaconId,
                    onSaved: refresh,
                    existing: draft,
                  ),
                ),
              ),
              TenturaTextAction(
                label: l10n.buttonDelete,
                tone: TenturaTone.danger,
                icon: const Icon(Icons.delete_outline),
                onPressed: () => unawaited(
                  confirmDeletePreparedPromise(
                    context,
                    itemId: draft.id,
                    onDeleted: refresh,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PreparedDraftBlockerRow extends StatelessWidget {
  const _PreparedDraftBlockerRow({
    required this.draft,
    required this.beaconId,
    required this.participants,
  });

  final CoordinationItem draft;
  final String beaconId;
  final List<BeaconParticipant> participants;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final cubit = context.read<ItemsTabCubit>();

    Future<void> refresh() => cubit.fetch();

    Future<void> openPublish() => showPreparedBlockerPublishSheet(
          context,
          draft: draft,
          onSaved: refresh,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ItemCard(
          item: draft,
          creatorParticipant: _participantForUser(
            participants,
            draft.creatorId,
          ),
          onEdit: () => unawaited(
            showPreparedBlockerEditorSheet(
              context,
              beaconId: beaconId,
              onSaved: refresh,
              existing: draft,
            ),
          ),
          onOpenItemThread: (_) => unawaited(openPublish()),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            alignment: WrapAlignment.end,
            children: [
              TenturaTextAction(
                label: l10n.buttonPublish,
                icon: const Icon(Icons.send_outlined),
                onPressed: () => unawaited(openPublish()),
              ),
              TenturaTextAction(
                label: l10n.myWorkEditDraft,
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => unawaited(
                  showPreparedBlockerEditorSheet(
                    context,
                    beaconId: beaconId,
                    onSaved: refresh,
                    existing: draft,
                  ),
                ),
              ),
              TenturaTextAction(
                label: l10n.buttonDelete,
                tone: TenturaTone.danger,
                icon: const Icon(Icons.delete_outline),
                onPressed: () => unawaited(
                  confirmDeletePreparedBlocker(
                    context,
                    itemId: draft.id,
                    onDeleted: refresh,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PreparedDraftAskRow extends StatelessWidget {
  const _PreparedDraftAskRow({
    required this.draft,
    required this.beaconId,
    required this.participants,
    required this.beaconAuthorId,
  });

  final CoordinationItem draft;
  final String beaconId;
  final List<BeaconParticipant> participants;
  final String beaconAuthorId;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final cubit = context.read<ItemsTabCubit>();

    Future<void> refresh() => cubit.fetch();

    Future<void> openPublish() => showPreparedAskPublishSheet(
          context,
          draft: draft,
          participants: participants,
          beaconAuthorId: beaconAuthorId,
          onSaved: refresh,
        );

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
          onEdit: () => unawaited(
                showPreparedAskEditorSheet(
                  context,
                  beaconId: beaconId,
                  onSaved: refresh,
                  existing: draft,
                ),
              ),
          onOpenItemThread: (_) => unawaited(openPublish()),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            alignment: WrapAlignment.end,
            children: [
              TenturaTextAction(
                label: l10n.buttonPublish,
                icon: const Icon(Icons.send_outlined),
                onPressed: () => unawaited(openPublish()),
              ),
              TenturaTextAction(
                label: l10n.myWorkEditDraft,
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => unawaited(
                  showPreparedAskEditorSheet(
                    context,
                    beaconId: beaconId,
                    onSaved: refresh,
                    existing: draft,
                  ),
                ),
              ),
              TenturaTextAction(
                label: l10n.buttonDelete,
                tone: TenturaTone.danger,
                icon: const Icon(Icons.delete_outline),
                onPressed: () => unawaited(
                  confirmDeletePreparedAsk(
                    context,
                    itemId: draft.id,
                    onDeleted: refresh,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
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
