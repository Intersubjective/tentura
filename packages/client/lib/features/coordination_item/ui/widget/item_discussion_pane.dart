import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/features/beacon_room/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_room/ui/widget/beacon_room_body.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/coordination_item_presenter.dart';
import 'package:tentura/ui/widget/coordination_item_card_chrome.dart';

import '../bloc/item_actions_cubit.dart';
import '../bloc/item_actions_state.dart';
import '../widget/coordination_item_overflow_menu.dart';

/// Thread-scoped blocs for an item discussion (route or nested room column).
Widget itemDiscussionProviders({
  required CoordinationItem item,
  required Widget child,
}) {
  return MultiBlocProvider(
    providers: [
      BlocProvider(
        key: ValueKey('item-discussion-room-${item.id}'),
        create: (_) => RoomCubit(
          beaconId: item.beaconId,
          threadItemId: item.id,
          initialUnreadAnchorAt: item.lastSeenAt,
        ),
      ),
      BlocProvider(
        create: (_) => ItemActionsCubit(item: item),
      ),
    ],
    child: child,
  );
}

/// Item thread body (header + messages) without a [Scaffold].
class ItemDiscussionPane extends StatelessWidget {
  const ItemDiscussionPane({
    this.onOpenCoordinationItem,
    super.key,
  });

  final ValueChanged<CoordinationItem>? onOpenCoordinationItem;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;

    return BlocBuilder<ItemActionsCubit, ItemActionsState>(
      buildWhen: (p, c) =>
          p.item != c.item ||
          p.pendingResolution != c.pendingResolution ||
          p.isLoading != c.isLoading,
      builder: (context, actionsState) {
        final theme = Theme.of(context);
        final actionsCubit = context.read<ItemActionsCubit>();
        final pendingResolution = actionsState.pendingResolution;
        final actionsBusy = actionsState.isLoading;
        return TenturaChatColumn(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ItemDiscussionHeader(
                item: actionsState.item,
                theme: theme,
                l10n: l10n,
              ),
              if (pendingResolution != null)
                _PendingResolutionBanner(
                  resolution: pendingResolution,
                  theme: theme,
                  l10n: l10n,
                  onAccept: actionsBusy
                      ? null
                      : () => unawaited(actionsCubit.acceptResolution()),
                  onReject: actionsBusy
                      ? null
                      : () => unawaited(actionsCubit.rejectResolution()),
                ),
              Expanded(
                child: BeaconRoomBody(
                  enableComposer: pendingResolution == null,
                  onOpenCoordinationItem: onOpenCoordinationItem,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Compact header for a nested thread inside the ops|room split column.
class ItemDiscussionColumnChrome extends StatelessWidget {
  const ItemDiscussionColumnChrome({
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
                child: ItemDiscussionTitle(fallback: l10n.coordinationItemDiscussionTitle),
              ),
              ItemDiscussionOverflowAction(
                onProposeResolution: () => showItemDiscussionProposeResolutionSheet(
                  context,
                  context.read<ItemActionsCubit>(),
                  l10n,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ItemDiscussionTitle extends StatelessWidget {
  const ItemDiscussionTitle({required this.fallback, super.key});

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

class ItemDiscussionOverflowAction extends StatelessWidget {
  const ItemDiscussionOverflowAction({
    required this.onProposeResolution,
    super.key,
  });

  final Future<void> Function() onProposeResolution;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ItemActionsCubit, ItemActionsState>(
      buildWhen: (p, c) =>
          p.item != c.item ||
          p.pendingResolution != c.pendingResolution ||
          p.isLoading != c.isLoading,
      builder: (context, state) => CoordinationItemDiscussionOverflowMenu(
        item: state.item,
        hasPendingResolution: state.pendingResolution != null,
        isLoading: state.isLoading,
        onProposeResolution: onProposeResolution,
      ),
    );
  }
}

Future<void> showItemDiscussionProposeResolutionSheet(
  BuildContext context,
  ItemActionsCubit cubit,
  L10n l10n,
) async {
  final title = await showTenturaAdaptiveSheet<String>(
    context: context,
    useRootNavigator: true,
    enableDrag: false,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => _ProposeResolutionSheet(l10n: l10n),
  );
  if (title == null || !context.mounted) return;
  final trimmed = title.trim();
  if (trimmed.isEmpty) return;
  await cubit.promoteResolution(title: trimmed);
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
      CoordinationItemKind.resolution => l10n.coordinationResolutionCardLabel,
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
              padding: EdgeInsets.fromLTRB(
                tt.screenHPadding,
                0,
                tt.screenHPadding,
                tt.cardGap,
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
  final VoidCallback? onAccept;
  final VoidCallback? onReject;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
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
          padding: EdgeInsets.symmetric(
            horizontal: tt.screenHPadding,
            vertical: tt.rowGap + tt.tightGap,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.fact_check_outlined,
                    color: colorScheme.primary,
                  ),
                  SizedBox(width: tt.iconTextGap),
                  Text(
                    l10n.coordinationSemanticResolutionOpened,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.primary,
                    ),
                  ),
                ],
              ),
              if (resolution.title.isNotEmpty) ...[
                SizedBox(height: tt.tightGap * 2),
                Text(resolution.title, style: theme.textTheme.bodySmall),
              ],
              SizedBox(height: tt.rowGap),
              Row(
                children: [
                  FilledButton(
                    onPressed: onAccept,
                    child: Text(l10n.coordinationResolutionAcceptLabel),
                  ),
                  SizedBox(width: tt.rowGap),
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

class _ProposeResolutionSheet extends StatefulWidget {
  const _ProposeResolutionSheet({required this.l10n});

  final L10n l10n;

  @override
  State<_ProposeResolutionSheet> createState() => _ProposeResolutionSheetState();
}

class _ProposeResolutionSheetState extends State<_ProposeResolutionSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isDirty => _controller.text.trim().isNotEmpty;

  void _submit() {
    final title = _controller.text.trim();
    if (title.isEmpty) return;
    Navigator.of(context).pop(title);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final tt = context.tt;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return TenturaSheetDismissGuard(
      isDirty: _isDirty,
      useRootNavigator: true,
      child: Padding(
        padding: EdgeInsets.only(
          left: tt.screenHPadding,
          right: tt.screenHPadding,
          top: tt.sectionGap,
          bottom: bottom + tt.sectionGap,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.beaconRoomActionCreateResolution,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            SizedBox(height: tt.rowGap),
            TextField(
              controller: _controller,
              decoration: InputDecoration(
                hintText: l10n.coordinationMarkResolutionHint,
              ),
              maxLines: 3,
              autofocus: true,
              onChanged: (_) => setState(() {}),
            ),
            SizedBox(height: tt.sectionGap),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => TenturaSheetDismissGuard.requestClose(
                    context,
                    isDirty: _isDirty,
                    useRootNavigator: true,
                  ),
                  child: Text(
                    MaterialLocalizations.of(context).cancelButtonLabel,
                  ),
                ),
                FilledButton(
                  onPressed: _submit,
                  child: Text(MaterialLocalizations.of(context).okButtonLabel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
