import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/ui/l10n/l10n.dart';

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
    final theme = Theme.of(context);

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
            buildWhen: (p, c) => p.item.status != c.item.status,
            builder: (context, state) {
              if (!state.item.isActive) return const SizedBox.shrink();
              final item = state.item;
              return PopupMenuButton<String>(
                onSelected: (v) {
                  final cubit = context.read<ItemDiscussionCubit>();
                  if (item.kind == CoordinationItemKind.resolution) {
                    if (v == 'accept') unawaited(cubit.acceptResolution());
                    if (v == 'reject') unawaited(cubit.rejectResolution());
                  } else if (item.kind == CoordinationItemKind.ask) {
                    if (v == 'accept') unawaited(cubit.acceptAsk());
                    if (v == 'resolve') unawaited(cubit.resolveAsk());
                    if (v == 'cancel') unawaited(cubit.cancelAsk());
                  } else {
                    if (v == 'resolve') unawaited(cubit.resolveBlocker());
                    if (v == 'cancel') unawaited(cubit.cancelBlocker());
                  }
                },
                itemBuilder: (_) {
                  if (item.kind == CoordinationItemKind.resolution) {
                    return [
                      PopupMenuItem(
                        value: 'accept',
                        child: Text(l10n.coordinationResolutionAcceptLabel),
                      ),
                      PopupMenuItem(
                        value: 'reject',
                        child: Text(l10n.coordinationResolutionRejectLabel),
                      ),
                    ];
                  }
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
                  ];
                },
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Item header
          BlocBuilder<ItemDiscussionCubit, ItemDiscussionState>(
            buildWhen: (p, c) => p.item != c.item,
            builder: (context, state) {
              final item = state.item;
              final colorScheme = theme.colorScheme;
              final statusColor = item.isOpen
                  ? colorScheme.error
                  : item.isAccepted
                      ? colorScheme.primary
                      : item.isResolved
                          ? colorScheme.primary
                          : colorScheme.outline;
              final kindLabel = switch (item.kind) {
                CoordinationItemKind.blocker =>
                  l10n.coordinationBlockerCardLabel,
                CoordinationItemKind.ask => l10n.coordinationAskCardLabel,
                _ => l10n.coordinationItemCardTitle,
              };
              final headerIcon = switch (item.kind) {
                CoordinationItemKind.ask => Icons.help_outline,
                _ => item.isOpen ? Icons.block : Icons.check_circle,
              };
              return Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.06),
                  border: Border(
                    bottom: BorderSide(
                      color: statusColor.withValues(alpha: 0.2),
                    ),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(headerIcon, size: 16, color: statusColor),
                        const SizedBox(width: 6),
                        Text(
                          kindLabel,
                          style: theme.textTheme.labelMedium
                              ?.copyWith(color: statusColor),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          item.status.name.toUpperCase(),
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: statusColor),
                        ),
                      ],
                    ),
                    if (item.body.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(item.body, style: theme.textTheme.bodySmall),
                    ],
                  ],
                ),
              );
            },
          ),
          // Messages list
          Expanded(
            child: BlocBuilder<ItemDiscussionCubit, ItemDiscussionState>(
              buildWhen: (p, c) =>
                  p.messages != c.messages || p.isLoading != c.isLoading,
              builder: (context, state) {
                if (state.isLoading && state.messages.isEmpty) {
                  return const Center(
                    child: CircularProgressIndicator.adaptive(),
                  );
                }
                if (state.messages.isEmpty) {
                  return Center(
                    child: Text(
                      l10n.coordinationItemDiscussionComposerHint,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: state.messages.length,
                  itemBuilder: (context, index) {
                    final msg = state.messages[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            msg.senderId,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(msg.body, style: theme.textTheme.bodyMedium),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          // Composer
          _Composer(
            hintText: l10n.coordinationItemDiscussionComposerHint,
            onSend: (body) =>
                context.read<ItemDiscussionCubit>().sendMessage(body),
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatefulWidget {
  const _Composer({required this.hintText, required this.onSend});

  final String hintText;
  final ValueChanged<String> onSend;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 4,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              decoration: InputDecoration(
                hintText: widget.hintText,
                border: InputBorder.none,
                isDense: true,
              ),
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: _send,
            ),
          ),
          IconButton(
            onPressed: () => _send(_controller.text),
            icon: const Icon(Icons.send),
          ),
        ],
      ),
    );
  }

  void _send(String text) {
    if (text.trim().isEmpty) return;
    widget.onSend(text);
    _controller.clear();
  }
}
