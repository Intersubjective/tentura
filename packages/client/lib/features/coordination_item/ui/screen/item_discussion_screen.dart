import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/features/beacon_room/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_room/ui/widget/beacon_room_body.dart';
import 'package:tentura/features/coordination_item/domain/use_case/coordination_item_case.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/coordination_item_presenter.dart';

import '../bloc/item_actions_cubit.dart';
import '../bloc/item_actions_state.dart';
import '../widget/coordination_item_overflow_menu.dart';

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
                p.item != c.item ||
                p.pendingResolution != c.pendingResolution ||
                p.isLoading != c.isLoading,
            builder: (context, state) => CoordinationItemDiscussionOverflowMenu(
              item: state.item,
              hasPendingResolution: state.pendingResolution != null,
              isLoading: state.isLoading,
              onProposeResolution: () => _showProposeResolutionSheet(
                context,
                context.read<ItemActionsCubit>(),
                l10n,
              ),
            ),
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
          return Scaffold(
            appBar: AppBar(
              leading: BackButton(
                onPressed: () => unawaited(context.router.maybePop()),
              ),
            ),
            body: const Center(child: CircularProgressIndicator.adaptive()),
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
  final title = await showTenturaAdaptiveSheet<String>(
    context: context,
    useRootNavigator: true,
    enableDrag: false,
    isDismissible: false,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => _ProposeResolutionSheet(l10n: l10n),
  );
  if (title == null || !context.mounted) return;
  final trimmed = title.trim();
  if (trimmed.isEmpty) return;
  await cubit.promoteResolution(title: trimmed);
}

class _ProposeResolutionSheet extends StatefulWidget {
  const _ProposeResolutionSheet({required this.l10n});

  final L10n l10n;

  @override
  State<_ProposeResolutionSheet> createState() =>
      _ProposeResolutionSheetState();
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

    return Padding(
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
          ),
          SizedBox(height: tt.sectionGap),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
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
    );
  }
}
