import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/features/coordination_item/domain/use_case/coordination_item_case.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../bloc/item_actions_cubit.dart';
import '../widget/item_discussion_pane.dart';

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
      return itemDiscussionProviders(item: resolved, child: this);
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
      appBar: TenturaTopBar.of(
        context,
        leading: const AutoLeadingButton(),
        title: ItemDiscussionTitle(
          fallback: l10n.coordinationItemDiscussionTitle,
        ),
        actions: [
          ItemDiscussionOverflowAction(
            onProposeResolution: () => showItemDiscussionProposeResolutionSheet(
              context,
              context.read<ItemActionsCubit>(),
              l10n,
            ),
          ),
        ],
      ),
      body: const ItemDiscussionPane(),
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

class _ItemDiscussionHydrateLoaderState
    extends State<_ItemDiscussionHydrateLoader> {
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
            appBar: TenturaTopBar.of(
              context,
              leading: BackButton(
                onPressed: () => unawaited(context.router.maybePop()),
              ),
              title: const SizedBox.shrink(),
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
        return itemDiscussionProviders(item: item, child: widget.child);
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
      appBar: TenturaTopBar.of(
        context,
        leading: BackButton(onPressed: onBack),
        title: const SizedBox.shrink(),
      ),
      body: Center(child: Text(l10n.labelNothingHere)),
    );
  }
}
