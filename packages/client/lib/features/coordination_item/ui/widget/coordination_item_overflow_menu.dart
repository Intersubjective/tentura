import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../bloc/item_actions_cubit.dart';

/// Menu action ids for [CoordinationItemDiscussionOverflowMenu].
enum CoordinationItemDiscussionMenuAction {
  remind,
  proposeResolution,
  accept,
  resolve,
  cancel,
}

/// Menu action ids for [CoordinationItemCardOverflowMenu].
enum CoordinationItemCardMenuAction {
  edit,
  remind,
  accept,
  resolve,
  cancel,
  reject,
}

String _participantDisplayName(BeaconParticipant? participant) {
  if (participant == null) return '';
  final title = participant.userTitle.trim();
  if (title.isNotEmpty) return title;
  final id = participant.userId;
  return id.length <= 16 ? id : '${id.substring(0, 14)}…';
}

/// Builds status/action entries for item discussion overflow (AppBar).
List<(CoordinationItemDiscussionMenuAction, String)>
coordinationItemDiscussionMenuEntries({
  required L10n l10n,
  required CoordinationItem item,
  required String viewerId,
  required bool hasPendingResolution,
}) {
  if (!item.isActive) return const [];
  if (item.kind == CoordinationItemKind.resolution) return const [];

  final canProposeResolution =
      !hasPendingResolution &&
      (item.kind == CoordinationItemKind.blocker ||
          item.kind == CoordinationItemKind.ask ||
          item.kind == CoordinationItemKind.promise);

  final remindLabel = item.canRemind(viewerId)
      ? l10n.remindAction(
          item.responsibleUserId?.substring(
                0,
                item.responsibleUserId!.length.clamp(0, 12),
              ) ??
              '',
        )
      : null;

  final entries = <(CoordinationItemDiscussionMenuAction, String)>[];

  void addRemind() {
    if (remindLabel != null) {
      entries.add((
        CoordinationItemDiscussionMenuAction.remind,
        remindLabel,
      ));
    }
  }

  if (item.kind == CoordinationItemKind.ask) {
    addRemind();
    if (item.isOpen) {
      entries.add((
        CoordinationItemDiscussionMenuAction.accept,
        l10n.coordinationAskAcceptLabel,
      ));
    }
    entries.addAll([
      (
        CoordinationItemDiscussionMenuAction.resolve,
        l10n.coordinationBlockerActionResolve,
      ),
      (
        CoordinationItemDiscussionMenuAction.cancel,
        l10n.coordinationBlockerActionCancel,
      ),
    ]);
    if (canProposeResolution) {
      entries.add((
        CoordinationItemDiscussionMenuAction.proposeResolution,
        l10n.beaconRoomActionCreateResolution,
      ));
    }
    return entries;
  }

  if (item.kind == CoordinationItemKind.promise) {
    addRemind();
    if (item.isOpen && item.targetPersonId == viewerId) {
      entries.add((
        CoordinationItemDiscussionMenuAction.accept,
        l10n.coordinationPromiseAcceptLabel,
      ));
    }
    entries.addAll([
      (
        CoordinationItemDiscussionMenuAction.resolve,
        l10n.coordinationBlockerActionResolve,
      ),
      (
        CoordinationItemDiscussionMenuAction.cancel,
        l10n.coordinationBlockerActionCancel,
      ),
    ]);
    if (canProposeResolution) {
      entries.add((
        CoordinationItemDiscussionMenuAction.proposeResolution,
        l10n.beaconRoomActionCreateResolution,
      ));
    }
    return entries;
  }

  addRemind();
  entries.addAll([
    (
      CoordinationItemDiscussionMenuAction.resolve,
      l10n.coordinationBlockerActionResolve,
    ),
    (
      CoordinationItemDiscussionMenuAction.cancel,
      l10n.coordinationBlockerActionCancel,
    ),
  ]);
  if (canProposeResolution) {
    entries.add((
      CoordinationItemDiscussionMenuAction.proposeResolution,
      l10n.beaconRoomActionCreateResolution,
    ));
  }
  return entries;
}

/// Builds status/action entries for [ItemCard] overflow.
List<(CoordinationItemCardMenuAction, String)> coordinationItemCardMenuEntries({
  required L10n l10n,
  required CoordinationItem item,
  required String? viewerId,
  BeaconParticipant? responsibleParticipant,
  required bool includeEdit,
  required bool includeRemind,
  required bool canResolve,
  required bool canCancel,
  required bool canAccept,
  required bool canReject,
}) {
  final entries = <(CoordinationItemCardMenuAction, String)>[];
  if (includeEdit) {
    entries.add((
      CoordinationItemCardMenuAction.edit,
      l10n.helpOffersTabActionEdit,
    ));
  }
  if (includeRemind && viewerId != null && item.canRemind(viewerId)) {
    final name = _participantDisplayName(responsibleParticipant);
    entries.add((
      CoordinationItemCardMenuAction.remind,
      name.isEmpty ? l10n.itemNeedsAttention : l10n.remindAction(name),
    ));
  }
  if (!item.published || !item.isActive) return entries;

  if (item.kind == CoordinationItemKind.blocker) {
    if (canResolve) {
      entries.add((
        CoordinationItemCardMenuAction.resolve,
        l10n.coordinationBlockerActionResolve,
      ));
    }
    if (canCancel) {
      entries.add((
        CoordinationItemCardMenuAction.cancel,
        l10n.coordinationBlockerActionCancel,
      ));
    }
    return entries;
  }
  if (item.kind == CoordinationItemKind.resolution && item.isOpen) {
    if (canAccept) {
      entries.add((
        CoordinationItemCardMenuAction.accept,
        l10n.coordinationResolutionAcceptLabel,
      ));
    }
    if (canReject || canCancel) {
      entries.add((
        CoordinationItemCardMenuAction.reject,
        l10n.coordinationResolutionRejectLabel,
      ));
    }
    return entries;
  }
  if (item.kind == CoordinationItemKind.plan && item.isPlanStep) {
    if (canResolve) {
      entries.add((
        CoordinationItemCardMenuAction.resolve,
        l10n.coordinationBlockerActionResolve,
      ));
    }
    return entries;
  }
  if (item.kind == CoordinationItemKind.ask) {
    if (item.isOpen && canAccept) {
      entries.add((
        CoordinationItemCardMenuAction.accept,
        l10n.coordinationAskAcceptLabel,
      ));
    }
    if (item.isOpen || item.isAccepted) {
      if (canResolve) {
        entries.add((
          CoordinationItemCardMenuAction.resolve,
          l10n.coordinationBlockerActionResolve,
        ));
      }
      if (canCancel) {
        entries.add((
          CoordinationItemCardMenuAction.cancel,
          l10n.coordinationBlockerActionCancel,
        ));
      }
    }
    return entries;
  }
  if (item.kind == CoordinationItemKind.promise) {
    if (item.isOpen && canAccept) {
      entries.add((
        CoordinationItemCardMenuAction.accept,
        l10n.coordinationPromiseAcceptLabel,
      ));
    }
    if (item.isOpen || item.isAccepted) {
      if (canResolve) {
        entries.add((
          CoordinationItemCardMenuAction.resolve,
          l10n.coordinationBlockerActionResolve,
        ));
      }
      if (canCancel) {
        entries.add((
          CoordinationItemCardMenuAction.cancel,
          l10n.coordinationBlockerActionCancel,
        ));
      }
    }
  }
  return entries;
}

/// Overflow menu for [ItemDiscussionScreen] AppBar — wires [ItemActionsCubit].
class CoordinationItemDiscussionOverflowMenu extends StatelessWidget {
  const CoordinationItemDiscussionOverflowMenu({
    required this.item,
    required this.hasPendingResolution,
    required this.isLoading,
    required this.onProposeResolution,
    super.key,
  });

  final CoordinationItem item;
  final bool hasPendingResolution;
  final bool isLoading;
  final Future<void> Function() onProposeResolution;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    if (!item.isActive) return const SizedBox.shrink();
    if (item.kind == CoordinationItemKind.resolution) {
      return const SizedBox.shrink();
    }
    if (isLoading) {
      return SizedBox(
        width: 48,
        height: 48,
        child: Center(
          child: SizedBox(
            width: context.tt.iconSize,
            height: context.tt.iconSize,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      );
    }

    final viewerId = GetIt.I<ProfileCubit>().state.profile.id;
    final actionsCubit = context.read<ItemActionsCubit>();
    final entries = coordinationItemDiscussionMenuEntries(
      l10n: l10n,
      item: item,
      viewerId: viewerId,
      hasPendingResolution: hasPendingResolution,
    );
    if (entries.isEmpty) return const SizedBox.shrink();

    return PopupMenuButton<CoordinationItemDiscussionMenuAction>(
      tooltip: l10n.beaconHudOverflowMore,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      onSelected: (action) {
        switch (action) {
          case CoordinationItemDiscussionMenuAction.remind:
            unawaited(actionsCubit.remindItem());
          case CoordinationItemDiscussionMenuAction.proposeResolution:
            unawaited(onProposeResolution());
          case CoordinationItemDiscussionMenuAction.accept:
            if (item.kind == CoordinationItemKind.ask) {
              unawaited(actionsCubit.acceptAsk());
            } else {
              unawaited(actionsCubit.acceptPromise());
            }
          case CoordinationItemDiscussionMenuAction.resolve:
            switch (item.kind) {
              case CoordinationItemKind.ask:
                unawaited(actionsCubit.resolveAsk());
              case CoordinationItemKind.promise:
                unawaited(actionsCubit.resolvePromise());
              default:
                unawaited(actionsCubit.resolveBlocker());
            }
          case CoordinationItemDiscussionMenuAction.cancel:
            switch (item.kind) {
              case CoordinationItemKind.ask:
                unawaited(actionsCubit.cancelAsk());
              case CoordinationItemKind.promise:
                unawaited(actionsCubit.cancelPromise());
              default:
                unawaited(actionsCubit.cancelBlocker());
            }
        }
      },
      itemBuilder: (_) => [
        for (final e in entries)
          PopupMenuItem(
            value: e.$1,
            child: Text(e.$2),
          ),
      ],
    );
  }
}

/// Overflow menu for [ItemCard].
class CoordinationItemCardOverflowMenu extends StatelessWidget {
  const CoordinationItemCardOverflowMenu({
    required this.item,
    required this.menuEntries,
    required this.onSelected,
    super.key,
  });

  final CoordinationItem item;
  final List<(CoordinationItemCardMenuAction, String)> menuEntries;
  final void Function(CoordinationItemCardMenuAction action) onSelected;

  @override
  Widget build(BuildContext context) {
    if (menuEntries.isEmpty) return const SizedBox.shrink();
    final l10n = L10n.of(context)!;
    return PopupMenuButton<CoordinationItemCardMenuAction>(
      key: TestIds.key(TestIds.coordinationItemMenu(item.id)),
      tooltip: l10n.beaconHudOverflowMore,
      padding: EdgeInsets.zero,
      icon: Icon(Icons.more_vert, size: context.tt.iconSize),
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      itemBuilder: (_) => [
        for (final e in menuEntries)
          PopupMenuItem(
            key: e.$1 == CoordinationItemCardMenuAction.resolve
                ? TestIds.key(TestIds.coordinationItemResolve(item.id))
                : null,
            value: e.$1,
            child: Text(e.$2),
          ),
      ],
      onSelected: onSelected,
    );
  }
}
