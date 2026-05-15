import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_state.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/features/beacon_room/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_room/ui/widget/beacon_room_next_move_sheet.dart';
import 'package:tentura/features/beacon_room/ui/widget/beacon_room_self_ask_sheet.dart';
import 'package:tentura/features/beacon_room/ui/widget/beacon_you_section_content.dart';
import 'package:tentura/features/beacon_room/ui/widget/fact_actions_sheet.dart';
import 'package:tentura/features/beacon_room/ui/widget/room_file_attachment_open.dart';
import 'package:tentura/features/beacon_room/ui/widget/room_now_section_content.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'package:tentura/features/coordination_item/ui/widget/item_card.dart';

import '../bloc/beacon_view_state.dart';
import '../bloc/items_tab_cubit.dart';
import '../bloc/items_tab_state.dart';
import 'beacon_definition_body.dart';
import 'beacon_prepared_ask_sheet.dart';

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
              prev.draftAskItems.isEmpty;
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
        final hasItems =
            openItems.isNotEmpty || closedItems.isNotEmpty || draftAskItems.isNotEmpty;
        final beaconId = state.beacon.id;
        final isOwner = state.beacon.author.id == state.myProfile.id;

        BeaconParticipant? myParticipant;
        for (final p in state.roomParticipants) {
          if (p.userId == state.myProfile.id) {
            myParticipant = p;
            break;
          }
        }

        final roomCue = state.beaconRoomCue;
        final showNow = roomCue != null &&
            RoomNowSectionContent.hasVisibleContent(
              roomState: roomCue,
              factCards: state.factCards,
              openCoordinationBlocker: state.openCoordinationBlocker,
              currentCoordinationPlan: tabState.currentCoordinationPlan,
            );

        // Parent CustomScrollView owns scrolling; nested ListView caused
        // parentDataDirty semantics asserts on web.
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _BeaconDefinitionSection(state: state),
              if (showNow)
                _BeaconNowSection(
                  roomState: roomCue,
                  factCards: state.factCards,
                  beaconId: beaconId,
                  openCoordinationBlocker: state.openCoordinationBlocker,
                  currentCoordinationPlan: tabState.currentCoordinationPlan,
                ),
              _BeaconYouSection(
                myParticipant: myParticipant,
                beaconId: beaconId,
                targetUserId: state.myProfile.id,
                viewerAcceptedAsk: tabState.viewerAcceptedAsk,
              ),
              if (isOwner && draftAskItems.isNotEmpty) ...[
                const SizedBox(height: 8),
                ExpansionTile(
                  title: Text(
                    '${l10n.myWorkSectionDrafts} (${draftAskItems.length})',
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
                  ],
                ),
              ],
              if (!hasItems)
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
              else ...[
                const SizedBox(height: 8),
                for (final item in openItems)
                  _ItemCardAnimatedRow(
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
                    onOpenItemThread: onOpenItemThread,
                    resolveAction: () async {
                      final cubit = context.read<ItemsTabCubit>();
                      if (item.kind == CoordinationItemKind.plan &&
                          item.isPlanStep) {
                        await cubit.resolvePlanStep(item.id);
                      } else if (item.kind == CoordinationItemKind.ask) {
                        await cubit.resolveAsk(item.id);
                      } else {
                        await cubit.resolveBlocker(item.id);
                      }
                    },
                    cancelAction: () async {
                      final cubit = context.read<ItemsTabCubit>();
                      if (item.kind == CoordinationItemKind.ask) {
                        await cubit.cancelAsk(item.id);
                      } else {
                        await cubit.cancelBlocker(item.id);
                      }
                    },
                    acceptAction: switch (item.kind) {
                      CoordinationItemKind.ask => () =>
                          context.read<ItemsTabCubit>().acceptAsk(item.id),
                      CoordinationItemKind.resolution => () =>
                          context.read<ItemsTabCubit>().acceptResolution(
                                item.id,
                              ),
                      _ => null,
                    },
                    rejectAction: item.kind == CoordinationItemKind.resolution
                        ? () =>
                            context.read<ItemsTabCubit>().rejectResolution(
                                  item.id,
                                )
                        : null,
                  ),
                if (closedItems.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ExpansionTile(
                    title: Text(
                      'Closed (${closedItems.length})',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    children: [
                      for (final item in closedItems)
                        ItemCard(
                          item: item,
                          creatorParticipant: _participantForUser(
                            state.roomParticipants,
                            item.creatorId,
                          ),
                          targetParticipant: _participantForUser(
                            state.roomParticipants,
                            item.targetPersonId,
                          ),
                          onOpenItemThread: onOpenItemThread,
                        ),
                    ],
                  ),
                ],
              ],
            ],
          ),
        );
      },
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
    super.key,
  });

  final CoordinationItem item;
  final BeaconParticipant? creatorParticipant;
  final BeaconParticipant? targetParticipant;
  final void Function(CoordinationItem item) onOpenItemThread;
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

class _BeaconNowSection extends StatelessWidget {
  const _BeaconNowSection({
    required this.roomState,
    required this.factCards,
    required this.beaconId,
    this.openCoordinationBlocker,
    this.currentCoordinationPlan,
  });

  final BeaconRoomState roomState;
  final List<BeaconFactCard> factCards;
  final String beaconId;
  final CoordinationItem? openCoordinationBlocker;
  final CoordinationItem? currentCoordinationPlan;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;

    return ExpansionTile(
      leading: const Icon(Icons.article_outlined),
      title: Text(
        l10n.beaconRoomStripNowTitle,
        style: Theme.of(context).textTheme.titleSmall,
      ),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: RoomNowSectionContent(
            roomState: roomState,
            factCards: factCards,
            openCoordinationBlocker: openCoordinationBlocker,
            currentCoordinationPlan: currentCoordinationPlan,
            onOpenFact: (f) => _showFactActionsFromItemsTab(
              context,
              beaconId: beaconId,
              fact: f,
            ),
            onOpenFileAttachment: (a) => openRoomFileAttachment(
              context,
              L10n.of(context)!,
              a,
            ),
          ),
        ),
      ],
    );
  }
}

class _BeaconYouSection extends StatelessWidget {
  const _BeaconYouSection({
    required this.myParticipant,
    required this.beaconId,
    required this.targetUserId,
    this.viewerAcceptedAsk,
  });

  final BeaconParticipant? myParticipant;
  final String beaconId;
  final String targetUserId;
  final CoordinationItem? viewerAcceptedAsk;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;

    return ExpansionTile(
      leading: const Icon(Icons.person_outline_rounded),
      title: Text(
        l10n.beaconRoomYouStripTitle,
        style: Theme.of(context).textTheme.titleSmall,
      ),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: BeaconYouSectionContent(
            myParticipant: myParticipant,
            viewerAcceptedAsk: viewerAcceptedAsk,
            onAddMyNextMove: () => unawaited(
              showBeaconRoomSelfAskSheet(
                context,
                beaconId: beaconId,
                onSaved: () => context.read<ItemsTabCubit>().fetch(),
              ),
            ),
            onEditNextMove: () => unawaited(
              showBeaconRoomNextMoveSheet(
                context,
                beaconId: beaconId,
                targetUserId: targetUserId,
                onSaved: () => context.read<ItemsTabCubit>().fetch(),
              ),
            ),
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
