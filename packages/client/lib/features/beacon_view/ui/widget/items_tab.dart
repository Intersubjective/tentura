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

class ItemsTab extends StatelessWidget {
  const ItemsTab({
    required this.state,
    super.key,
  });

  final BeaconViewState state;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;

    return BlocBuilder<ItemsTabCubit, ItemsTabState>(
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
              if (isOwner) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.tonalIcon(
                    onPressed: () => unawaited(
                      showPreparedAskEditorSheet(
                        context,
                        beaconId: beaconId,
                        onSaved: () => unawaited(
                          context.read<ItemsTabCubit>().fetch(),
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.edit_note_outlined),
                    label: Text(l10n.beaconPreparedAskPrepareAction),
                  ),
                ),
              ],
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
                  ItemCard(
                    item: item,
                    onResolve: () {
                      final cubit = context.read<ItemsTabCubit>();
                      if (item.kind == CoordinationItemKind.plan &&
                          item.isPlanStep) {
                        unawaited(cubit.resolvePlanStep(item.id));
                      } else if (item.kind == CoordinationItemKind.ask) {
                        unawaited(cubit.resolveAsk(item.id));
                      } else {
                        unawaited(cubit.resolveBlocker(item.id));
                      }
                    },
                    onCancel: () {
                      final cubit = context.read<ItemsTabCubit>();
                      if (item.kind == CoordinationItemKind.ask) {
                        unawaited(cubit.cancelAsk(item.id));
                      } else {
                        unawaited(cubit.cancelBlocker(item.id));
                      }
                    },
                    onAccept: switch (item.kind) {
                      CoordinationItemKind.ask => () => unawaited(
                            context.read<ItemsTabCubit>().acceptAsk(item.id),
                          ),
                      CoordinationItemKind.resolution => () => unawaited(
                            context
                                .read<ItemsTabCubit>()
                                .acceptResolution(item.id),
                          ),
                      _ => null,
                    },
                    onReject: item.kind == CoordinationItemKind.resolution
                        ? () => unawaited(
                              context
                                  .read<ItemsTabCubit>()
                                  .rejectResolution(item.id),
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
                      for (final item in closedItems) ItemCard(item: item),
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
          onTap: () => unawaited(openPublish()),
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
