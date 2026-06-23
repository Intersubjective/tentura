import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/features/beacon_room/ui/bloc/room_cubit.dart';
import 'package:tentura/features/coordination_item/domain/use_case/coordination_item_case.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/features/beacon_room/ui/widget/beacon_room_body.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/coordination_item_presenter.dart';

import '../bloc/item_actions_cubit.dart';
import '../bloc/item_actions_state.dart';

Widget _itemDiscussionProviders({
  required CoordinationItem item,
  required Widget child,
}) {
  return MultiBlocProvider(
    providers: [
      BlocProvider(
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
    child: BlocListener<ItemActionsCubit, ItemActionsState>(
      listener: commonScreenBlocListener,
      child: child,
    ),
  );
}

@RoutePage()
class ItemDiscussionScreen extends StatelessWidget implements AutoRouteWrapper {
  const ItemDiscussionScreen({
    @PathParam('beaconId') this.beaconId = '',
    @PathParam('itemId') this.itemId = '',
    this.item,
    super.key,
  });

  final String beaconId;

  final String itemId;

  /// Passed on in-app navigation; omitted after a web refresh (hydrate via path).
  final CoordinationItem? item;

  @override
  Widget wrappedRoute(BuildContext context) {
    final resolved = item;
    if (resolved != null && resolved.id.isNotEmpty) {
      if (resolved.kind == CoordinationItemKind.plan) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) {
            unawaited(
              context.router.replace(
                BeaconViewRoute(id: resolved.beaconId, viewTab: 'room'),
              ),
            );
          }
        });
        return const SizedBox.shrink();
      }
      return _itemDiscussionProviders(item: resolved, child: this);
    }
    if (beaconId.isEmpty || itemId.isEmpty) {
      return _ItemDiscussionLoadError(
        onBack: () => unawaited(context.router.maybePop()),
      );
    }
    return _ItemDiscussionHydrateLoader(
      beaconId: beaconId,
      itemId: itemId,
      child: this,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: BlocBuilder<ItemActionsCubit, ItemActionsState>(
          buildWhen: (p, c) => p.item != c.item,
          builder: (context, state) => Text(
            state.item.title.isEmpty
                ? l10n.coordinationItemDiscussionTitle
                : state.item.title,
          ),
        ),
        actions: [
          BlocBuilder<ItemActionsCubit, ItemActionsState>(
            buildWhen: (p, c) =>
                p.item.status != c.item.status ||
                p.pendingResolution != c.pendingResolution ||
                p.isLoading != c.isLoading,
            builder: (context, state) {
              if (!state.item.isActive) return const SizedBox.shrink();
              if (state.isLoading) {
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
              final item = state.item;
              final hasPendingResolution = state.pendingResolution != null;
              final actionsCubit = context.read<ItemActionsCubit>();
              final viewerId = GetIt.I<ProfileCubit>().state.profile.id;
              final canProposeResolution =
                  !hasPendingResolution &&
                  (item.kind == CoordinationItemKind.blocker ||
                      item.kind == CoordinationItemKind.ask ||
                      item.kind == CoordinationItemKind.promise);

              // Resolution items manage accept/reject via the pending banner
              // inside the parent item's discussion — not via this overflow menu.
              if (item.kind == CoordinationItemKind.resolution) {
                return const SizedBox.shrink();
              }

              return PopupMenuButton<String>(
                tooltip: l10n.beaconHudOverflowMore,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 48,
                  minHeight: 48,
                ),
                onSelected: (v) {
                  if (v == 'remind') {
                    unawaited(actionsCubit.remindItem());
                    return;
                  }
                  if (v == 'propose_resolution') {
                    unawaited(
                      _showProposeResolutionSheet(
                        context,
                        actionsCubit,
                        l10n,
                      ),
                    );
                    return;
                  }
                  if (item.kind == CoordinationItemKind.ask) {
                    if (v == 'accept') unawaited(actionsCubit.acceptAsk());
                    if (v == 'resolve') unawaited(actionsCubit.resolveAsk());
                    if (v == 'cancel') unawaited(actionsCubit.cancelAsk());
                  } else if (item.kind == CoordinationItemKind.promise) {
                    if (v == 'accept') unawaited(actionsCubit.acceptPromise());
                    if (v == 'resolve') unawaited(actionsCubit.resolvePromise());
                    if (v == 'cancel') unawaited(actionsCubit.cancelPromise());
                  } else {
                    if (v == 'resolve') unawaited(actionsCubit.resolveBlocker());
                    if (v == 'cancel') unawaited(actionsCubit.cancelBlocker());
                  }
                },
                itemBuilder: (_) {
                  final remindLabel = item.canRemind(viewerId)
                      ? l10n.remindAction(
                          item.responsibleUserId?.substring(
                                0,
                                item.responsibleUserId!.length.clamp(0, 12),
                              ) ??
                              '',
                        )
                      : null;
                  if (item.kind == CoordinationItemKind.ask) {
                    return [
                      if (remindLabel != null)
                        PopupMenuItem(
                          value: 'remind',
                          child: Text(remindLabel),
                        ),
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
                  if (item.kind == CoordinationItemKind.promise) {
                    return [
                      if (remindLabel != null)
                        PopupMenuItem(
                          value: 'remind',
                          child: Text(remindLabel),
                        ),
                      if (item.isOpen && item.targetPersonId == viewerId)
                        PopupMenuItem(
                          value: 'accept',
                          child: Text(l10n.coordinationPromiseAcceptLabel),
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
                    if (remindLabel != null)
                      PopupMenuItem(
                        value: 'remind',
                        child: Text(remindLabel),
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
                },
              );
            },
          ),
        ],
      ),
      body: BlocBuilder<ItemActionsCubit, ItemActionsState>(
        buildWhen: (p, c) =>
            p.item != c.item ||
            p.pendingResolution != c.pendingResolution ||
            p.isLoading != c.isLoading,
        builder: (context, actionsState) {
          final theme = Theme.of(context);
          final actionsCubit = context.read<ItemActionsCubit>();
          final pendingResolution = actionsState.pendingResolution;
          final actionsBusy = actionsState.isLoading;
          return Column(
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
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ItemDiscussionHydrateLoader extends StatefulWidget {
  const _ItemDiscussionHydrateLoader({
    required this.beaconId,
    required this.itemId,
    required this.child,
  });

  final String beaconId;
  final String itemId;
  final ItemDiscussionScreen child;

  @override
  State<_ItemDiscussionHydrateLoader> createState() =>
      _ItemDiscussionHydrateLoaderState();
}

class _ItemDiscussionHydrateLoaderState extends State<_ItemDiscussionHydrateLoader> {
  late final Future<CoordinationItem?> _itemFuture;

  @override
  void initState() {
    super.initState();
    _itemFuture = _loadItem();
  }

  Future<CoordinationItem?> _loadItem() async {
    final items = await GetIt.I<CoordinationItemCase>().listByBeacon(
      widget.beaconId,
    );
    for (final item in items) {
      if (item.id == widget.itemId) return item;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<CoordinationItem?>(
      future: _itemFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator.adaptive()),
          );
        }
        final item = snapshot.data;
        if (item == null) {
          return _ItemDiscussionLoadError(
            onBack: () => unawaited(context.router.maybePop()),
          );
        }
        if (item.kind == CoordinationItemKind.plan) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) {
              unawaited(
                context.router.replace(
                  BeaconViewRoute(id: item.beaconId, viewTab: 'room'),
                ),
              );
            }
          });
          return const SizedBox.shrink();
        }
        return _itemDiscussionProviders(item: item, child: widget.child);
      },
    );
  }
}

class _ItemDiscussionLoadError extends StatelessWidget {
  const _ItemDiscussionLoadError({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    return Scaffold(
      appBar: AppBar(leading: BackButton(onPressed: onBack)),
      body: Center(child: Text(l10n.labelNothingHere)),
    );
  }
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
      CoordinationItemKind.plan => item.isPlanStep
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
          subtitle: Row(
            children: [
              headerIcon,
              SizedBox(width: tt.iconTextGap),
              Text(
                kindLabel,
                style: theme.textTheme.labelSmall?.copyWith(color: statusColor),
              ),
              SizedBox(width: tt.rowGap),
              Text(
                coordinationItemStatusLabel(l10n, item.status),
                style: theme.textTheme.labelSmall?.copyWith(color: statusColor),
              ),
            ],
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
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: colorScheme.primary),
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

Future<void> _showProposeResolutionSheet(
  BuildContext context,
  ItemActionsCubit cubit,
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
