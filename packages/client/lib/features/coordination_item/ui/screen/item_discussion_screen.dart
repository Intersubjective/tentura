import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/domain/entity/coordination_item_message.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/basic_chat_body.dart';

import '../bloc/item_discussion_cubit.dart';
import '../bloc/item_discussion_state.dart';

@RoutePage()
class ItemDiscussionScreen extends StatelessWidget implements AutoRouteWrapper {
  const ItemDiscussionScreen({
    required this.item,
    super.key,
  });

  final CoordinationItem item;

  @override
  Widget wrappedRoute(BuildContext context) => BlocProvider(
        create: (_) {
          final cubit = ItemDiscussionCubit(item: item);
          unawaited(cubit.fetchMessages());
          return cubit;
        },
        child: this,
      );

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: BlocBuilder<ItemDiscussionCubit, ItemDiscussionState>(
          buildWhen: (p, c) => p.item != c.item,
          builder: (context, state) => Text(
            state.item.title.isEmpty
                ? l10n.coordinationItemDiscussionTitle
                : state.item.title,
          ),
        ),
        actions: [
          BlocBuilder<ItemDiscussionCubit, ItemDiscussionState>(
            buildWhen: (p, c) =>
                p.item.status != c.item.status ||
                p.pendingResolution != c.pendingResolution,
            builder: (context, state) {
              if (!state.item.isActive) return const SizedBox.shrink();
              final item = state.item;
              final hasPendingResolution = state.pendingResolution != null;
              final canProposeResolution =
                  !hasPendingResolution &&
                  (item.kind == CoordinationItemKind.blocker ||
                      item.kind == CoordinationItemKind.ask);

              // Resolution items manage accept/reject via the pending banner
              // inside the parent item's discussion — not via this overflow menu.
              if (item.kind == CoordinationItemKind.resolution) {
                return const SizedBox.shrink();
              }

              return PopupMenuButton<String>(
                onSelected: (v) {
                  final cubit = context.read<ItemDiscussionCubit>();
                  if (v == 'propose_resolution') {
                    unawaited(_showProposeResolutionSheet(context, cubit, l10n));
                    return;
                  }
                  if (item.kind == CoordinationItemKind.ask) {
                    if (v == 'accept') unawaited(cubit.acceptAsk());
                    if (v == 'resolve') unawaited(cubit.resolveAsk());
                    if (v == 'cancel') unawaited(cubit.cancelAsk());
                  } else {
                    if (v == 'resolve') unawaited(cubit.resolveBlocker());
                    if (v == 'cancel') unawaited(cubit.cancelBlocker());
                  }
                },
                itemBuilder: (_) {
                  if (item.kind == CoordinationItemKind.ask) {
                    return [
                      if (item.isOpen)
                        PopupMenuItem(
                          value: 'accept',
                          child: Text(l10n.coordinationAskAcceptLabel),
                        ),
                      PopupMenuItem(
                        value: 'resolve',
                        child: Text(l10n.coordinationBlockerActionResolve),
                      ),
                      PopupMenuItem(
                        value: 'cancel',
                        child: Text(l10n.coordinationBlockerActionCancel),
                      ),
                      if (canProposeResolution)
                        PopupMenuItem(
                          value: 'propose_resolution',
                          child: Text(l10n.beaconRoomActionCreateResolution),
                        ),
                    ];
                  }
                  return [
                    PopupMenuItem(
                      value: 'resolve',
                      child: Text(l10n.coordinationBlockerActionResolve),
                    ),
                    PopupMenuItem(
                      value: 'cancel',
                      child: Text(l10n.coordinationBlockerActionCancel),
                    ),
                    if (canProposeResolution)
                      PopupMenuItem(
                        value: 'propose_resolution',
                        child: Text(l10n.beaconRoomActionCreateResolution),
                      ),
                  ];
                },
              );
            },
          ),
        ],
      ),
      body: BlocBuilder<ItemDiscussionCubit, ItemDiscussionState>(
        buildWhen: (p, c) =>
            p.item != c.item ||
            p.messages != c.messages ||
            p.isLoading != c.isLoading ||
            p.status != c.status ||
            p.unreadAnchorAt != c.unreadAnchorAt ||
            p.pendingResolution != c.pendingResolution,
        builder: (context, state) {
          final cubit = context.read<ItemDiscussionCubit>();
          final theme = Theme.of(context);
          final sorted = [...state.messages]..sort(
                (a, b) => a.createdAt.compareTo(b.createdAt),
              );
          final roomMessages = sorted.map(_itemMessageToRoomMessage).toList();
          final myProfile = GetIt.I<ProfileCubit>().state.profile;
          final err = state.status is StateHasError
              ? (state.status as StateHasError).error.toString()
              : '';
          final firstUnreadIndex =
              state.firstUnreadIndexInRoomMessages(roomMessages);
          final pendingResolution = state.pendingResolution;

          return BasicChatBody(
            messages: roomMessages,
            myProfile: myProfile,
            participants: const [],
            isLoading: state.isLoading,
            hasError: state.hasError && roomMessages.isEmpty,
            errorText: err,
            firstUnreadIndex: firstUnreadIndex,
            unreadCount: state.unreadCount,
            onMarkSeenNearBottom: cubit.markSeenNowIfNeeded,
            onMessageActions: (msg) {
              if (msg.authorId != myProfile.id) return;
              unawaited(
                _confirmDeleteItemMessage(context, cubit, l10n, msg),
              );
            },
            onSend: pendingResolution != null
                ? null
                : (body, _) async {
                    await cubit.sendMessage(body);
                  },
            header: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                _ItemDiscussionHeader(
                  item: state.item,
                  theme: theme,
                  l10n: l10n,
                ),
                if (pendingResolution != null)
                  _PendingResolutionBanner(
                    resolution: pendingResolution,
                    theme: theme,
                    l10n: l10n,
                    onAccept: () => unawaited(cubit.acceptResolution()),
                    onReject: () => unawaited(cubit.rejectResolution()),
                  ),
              ],
            ),
            emptyPlaceholder: Center(
              child: Text(
                l10n.coordinationItemDiscussionComposerHint,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            imageRepository: GetIt.I<ImageRepository>(),
            enableComposerAttachments: false,
            enableParticipantMentions: false,
            jumpFabHeroTag: 'item_discussion_jump_latest',
          );
        },
      ),
    );
  }
}

RoomMessage _itemMessageToRoomMessage(CoordinationItemMessage m) {
  return RoomMessage(
    id: m.id,
    beaconId: m.beaconId,
    authorId: m.senderId,
    body: m.body,
    createdAt: m.createdAt,
    editedAt: m.editedAt,
    author: Profile(id: m.senderId),
  );
}

class _ItemDiscussionHeader extends StatelessWidget {
  const _ItemDiscussionHeader({
    required this.item,
    required this.theme,
    required this.l10n,
  });

  final CoordinationItem item;
  final ThemeData theme;
  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    final preview = item.contentPreview;
    if (preview.isEmpty) {
      return const SizedBox.shrink();
    }

    final colorScheme = theme.colorScheme;
    final statusColor = item.isOpen
        ? colorScheme.error
        : item.isAccepted
            ? colorScheme.primary
            : item.isResolved
                ? colorScheme.primary
                : colorScheme.outline;
    final kindLabel = switch (item.kind) {
      CoordinationItemKind.blocker => l10n.coordinationBlockerCardLabel,
      CoordinationItemKind.ask => l10n.coordinationAskCardLabel,
      _ => l10n.coordinationItemCardTitle,
    };
    final headerIcon = switch (item.kind) {
      CoordinationItemKind.ask => Icons.help_outline,
      _ => item.isOpen ? Icons.block : Icons.check_circle,
    };
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
          initiallyExpanded: false,
          leading: Container(width: 3, color: statusColor),
          title: Text(
            preview,
            style: theme.textTheme.bodySmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Row(
            children: [
              Icon(headerIcon, size: 16, color: statusColor),
              const SizedBox(width: 6),
              Text(
                kindLabel,
                style: theme.textTheme.labelSmall?.copyWith(color: statusColor),
              ),
              const SizedBox(width: 8),
              Text(
                item.status.name.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(color: statusColor),
              ),
            ],
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title.isNotEmpty && title != preview)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
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

class _PendingResolutionBanner extends StatelessWidget {
  const _PendingResolutionBanner({
    required this.resolution,
    required this.theme,
    required this.l10n,
    required this.onAccept,
    required this.onReject,
  });

  final CoordinationItem resolution;
  final ThemeData theme;
  final L10n l10n;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final colorScheme = theme.colorScheme;
    return Material(
      color: colorScheme.primaryContainer.withValues(alpha: 0.3),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: colorScheme.primary.withValues(alpha: 0.2),
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.fact_check_outlined,
                    size: 16,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    l10n.coordinationSemanticResolutionOpened,
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: colorScheme.primary),
                  ),
                ],
              ),
              if (resolution.title.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(resolution.title, style: theme.textTheme.bodySmall),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  FilledButton(
                    onPressed: onAccept,
                    child: Text(l10n.coordinationResolutionAcceptLabel),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: onReject,
                    child: Text(l10n.coordinationResolutionRejectLabel),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _showProposeResolutionSheet(
  BuildContext context,
  ItemDiscussionCubit cubit,
  L10n l10n,
) async {
  final titleController = TextEditingController();
  try {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.beaconRoomActionCreateResolution),
        content: TextField(
          controller: titleController,
          decoration: InputDecoration(
            hintText: l10n.coordinationMarkResolutionHint,
          ),
          maxLines: 3,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      final title = titleController.text.trim();
      if (title.isEmpty) return;
      await cubit.promoteResolution(title: title);
    }
  } finally {
    titleController.dispose();
  }
}

Future<void> _confirmDeleteItemMessage(
  BuildContext context,
  ItemDiscussionCubit cubit,
  L10n l10n,
  RoomMessage message,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.beaconRoomDeleteMessageConfirmTitle),
      content: Text(l10n.beaconRoomDeleteMessageConfirmBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(ctx).colorScheme.error,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l10n.beaconRoomDeleteMessageConfirmAction),
        ),
      ],
    ),
  );
  if (ok == true && context.mounted) {
    await cubit.deleteMessage(messageId: message.id);
  }
}
