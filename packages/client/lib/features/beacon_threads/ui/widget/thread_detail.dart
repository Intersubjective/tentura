import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_room_body.dart';
import 'package:tentura/features/beacon_threads/ui/widget/thread_host.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/coordination_item_presenter.dart';
import 'package:tentura/ui/widget/coordination_item_card_chrome.dart';

import 'package:tentura/features/coordination_item/ui/bloc/item_actions_cubit.dart';
import 'package:tentura/features/coordination_item/ui/bloc/item_actions_state.dart';
import 'package:tentura/features/coordination_item/ui/widget/coordination_item_overflow_menu.dart';

/// Thread body (optional semantic header + messages) without a [Scaffold].
class ThreadDetail extends StatelessWidget {
  const ThreadDetail({
    required this.thread,
    this.onOpenCoordinationItem,
    this.onCoordinationSaved,
    this.beaconAuthorId = '',
    super.key,
  });

  final RequestThread thread;
  final ValueChanged<CoordinationItem>? onOpenCoordinationItem;
  final VoidCallback? onCoordinationSaved;
  final String beaconAuthorId;

  @override
  Widget build(BuildContext context) {
    final item = thread.item;
    return ThreadHost(
      child: TenturaChatColumn(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (item != null)
              _ThreadDetailSemanticHeader(item: item),
            Expanded(
              child: BeaconRoomBody(
                beaconAuthorId: beaconAuthorId,
                onCoordinationSaved: onCoordinationSaved,
                onOpenCoordinationItem: onOpenCoordinationItem,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact header for a nested thread inside the ops|room split column.
class ThreadDetailColumnChrome extends StatelessWidget {
  const ThreadDetailColumnChrome({
    required this.onBack,
    super.key,
  });

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final tt = context.tt;
    final scheme = theme.colorScheme;

    return Material(
      color: scheme.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: scheme.outlineVariant),
          ),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: tt.tightGap,
            vertical: tt.tightGap,
          ),
          child: Row(
            children: [
              Semantics(
                label: l10n.beaconRoomBackToChat,
                button: true,
                child: IconButton(
                  tooltip: l10n.beaconRoomBackToChat,
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back),
                ),
              ),
              Expanded(
                child: ThreadDetailTitle(
                  fallback: l10n.coordinationItemDiscussionTitle,
                ),
              ),
              const ThreadDetailOverflowAction(),
            ],
          ),
        ),
      ),
    );
  }
}

class ThreadDetailTitle extends StatelessWidget {
  const ThreadDetailTitle({required this.fallback, super.key});

  final String fallback;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ItemActionsCubit, ItemActionsState>(
      buildWhen: (p, c) => p.item != c.item,
      builder: (context, state) => Text(
        state.item.title.isEmpty ? fallback : state.item.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class ThreadDetailOverflowAction extends StatelessWidget {
  const ThreadDetailOverflowAction({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ItemActionsCubit, ItemActionsState>(
      buildWhen: (p, c) => p.item != c.item || p.isLoading != c.isLoading,
      builder: (context, state) => CoordinationItemDiscussionOverflowMenu(
        item: state.item,
        isLoading: state.isLoading,
      ),
    );
  }
}

class _ThreadDetailSemanticHeader extends StatelessWidget {
  const _ThreadDetailSemanticHeader({required this.item});

  final CoordinationItem item;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final preview = item.contentPreview;
    if (preview.isEmpty) {
      return const SizedBox.shrink();
    }

    final tt = context.tt;
    final statusColor = coordinationItemColor(tt, item.kind, item.status);
    final kindLabel = switch (item.kind) {
      CoordinationItemKind.blocker => l10n.coordinationBlockerCardLabel,
      CoordinationItemKind.ask => l10n.coordinationAskCardLabel,
      CoordinationItemKind.promise => l10n.coordinationPromiseCardLabel,
      CoordinationItemKind.plan =>
        item.isPlanStep
            ? l10n.coordinationPlanStepCardLabel
            : l10n.coordinationPlanCardLabel,
    };
    final headerIcon = coordinationCompoundStatusIcon(
      kind: item.kind,
      status: item.status,
      isPlanStep: item.isPlanStep,
      tt: tt,
    );
    final body = item.body.trim();
    final title = item.title.trim();

    return Material(
      color: statusColor.withValues(alpha: 0.06),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: statusColor.withValues(alpha: 0.2),
            ),
          ),
        ),
        child: ExpansionTile(
          leading: Container(width: 3, color: statusColor),
          title: Text(
            preview,
            style: theme.textTheme.bodySmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: BlocBuilder<RoomCubit, RoomState>(
            buildWhen: (p, c) => p.participants != c.participants,
            builder: (context, roomState) {
              final avatarTrail = item.kind.hasDirectedParties
                  ? coordinationDirectedAvatarTrailForItem(
                      creatorId: item.creatorId,
                      targetPersonId: item.targetPersonId,
                      participants: roomState.participants,
                    )
                  : null;
              return Row(
                children: [
                  if (avatarTrail != null) ...[
                    avatarTrail,
                    SizedBox(width: tt.rowGap),
                  ],
                  headerIcon,
                  SizedBox(width: tt.iconTextGap),
                  Text(
                    kindLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: statusColor,
                    ),
                  ),
                  SizedBox(width: tt.rowGap),
                  Text(
                    coordinationItemStatusLabel(l10n, item.status),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: statusColor,
                    ),
                  ),
                ],
              );
            },
          ),
          children: [
            Padding(
              padding: EdgeInsets.zero.copyWith(
                left: tt.screenHPadding,
                right: tt.screenHPadding,
                bottom: tt.cardGap,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title.isNotEmpty && title != preview)
                    Padding(
                      padding: EdgeInsets.only(bottom: tt.tightGap * 2),
                      child: Text(
                        title,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: statusColor,
                        ),
                      ),
                    ),
                  if (body.isNotEmpty)
                    Text(body, style: theme.textTheme.bodySmall)
                  else if (title.isNotEmpty)
                    Text(title, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
