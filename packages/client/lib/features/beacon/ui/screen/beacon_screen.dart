import 'dart:async';
import 'package:flutter/material.dart';
import 'package:auto_route/auto_route.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/auto_leading_with_fallback.dart';
import 'package:tentura/ui/widget/linear_pi_active.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_item.dart';
import 'package:tentura/features/inbox/domain/enum.dart';
import 'package:tentura/features/inbox/ui/widget/inbox_item_tile.dart';

import '../../domain/enum.dart';
import '../bloc/beacon_cubit.dart';

@RoutePage()
class BeaconScreen extends StatefulWidget implements AutoRouteWrapper {
  const BeaconScreen({
    @PathParam('id') this.id = '',
    super.key,
  });

  /// Profile Id of user which beacons to show
  final String id;

  @override
  Widget wrappedRoute(_) => MultiBlocProvider(
    providers: [
      BlocProvider(
        create: (_) => ScreenCubit(),
      ),
      BlocProvider(
        create: (_) => BeaconCubit(profileId: id),
      ),
    ],
    child: MultiBlocListener(
      listeners: const [
        BlocListener<BeaconCubit, BeaconState>(
          listener: commonScreenBlocListener,
        ),
        BlocListener<ScreenCubit, ScreenState>(
          listener: commonScreenBlocListener,
        ),
      ],
      child: this,
    ),
  );

  @override
  State<BeaconScreen> createState() => _BeaconScreenState();
}

class _BeaconScreenState extends State<BeaconScreen> {
  final _scrollController = ScrollController();

  late final _beaconCubit = context.read<BeaconCubit>();

  late final _l10n = L10n.of(context)!;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      if (_scrollController.hasClients &&
          _scrollController.offset >
              _scrollController.position.maxScrollExtent * kFetchListOffset) {
        unawaited(_beaconCubit.fetch());
      }
    });
    unawaited(_beaconCubit.fetch());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tt = context.tt;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: Text(_l10n.beaconsTitle),
        leading: const AutoLeadingWithFallback(fallbackPath: kPathHome),
        actions: [
          BlocSelector<BeaconCubit, BeaconState, BeaconFilter>(
            selector: (state) => state.filter,
            builder: (context, filter) => Padding(
              padding: EdgeInsets.only(right: tt.tightGap),
              child: Tooltip(
                message: _l10n.myWorkFilterMenuTooltip,
                child: DropdownButton<BeaconFilter>(
                  icon: const Icon(Icons.filter_alt),
                  items: [
                    DropdownMenuItem(
                      value: BeaconFilter.active,
                      child: Text(_l10n.beaconsFilterActive),
                    ),
                    DropdownMenuItem(
                      value: BeaconFilter.closed,
                      child: Text(_l10n.beaconsFilterClosed),
                    ),
                  ],
                  onChanged: _beaconCubit.setFilter,
                  value: filter,
                  dropdownColor: scheme.surfaceContainer,
                ),
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: LinearPiActive.size,
          child: BlocSelector<BeaconCubit, BeaconState, bool>(
            selector: (state) => state.isLoading,
            builder: LinearPiActive.builder,
            bloc: _beaconCubit,
          ),
        ),
      ),
      body: SafeArea(
        minimum: kPaddingSmallH,
        child: BlocBuilder<BeaconCubit, BeaconState>(
          bloc: _beaconCubit,
          buildWhen: (_, c) => c.isSuccess || c.isLoading,
          builder: (context, state) {
            if (state.isLoading && state.beacons.isEmpty) {
              return const Center(
                child: CircularProgressIndicator.adaptive(),
              );
            }
            if (state.beacons.isEmpty) {
              return Center(
                child: Padding(
                  padding: tt.cardPadding,
                  child: Semantics(
                    label: _l10n.noBeaconsMessage,
                    child: Text(
                      _l10n.noBeaconsMessage,
                      style: TenturaText.bodyMedium(scheme.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              );
            }
            return ListView.builder(
              key: ValueKey(state.beacons),
              controller: _scrollController,
              padding: kPaddingSmallV,
              itemCount: state.beacons.length,
              itemBuilder: (_, i) {
                final beacon = state.beacons[i];
                return Padding(
                  padding: kPaddingSmallV,
                  child: InboxItemTile(
                    key: ValueKey(beacon.id),
                    item: _inboxItemFromBeacon(beacon),
                    onOpenBeacon: () => context.router.pushPath(
                      '$kPathBeaconView/${beacon.id}',
                    ),
                    onTap: () => context.router.pushPath(
                      '$kPathForwardBeacon/${beacon.id}',
                    ),
                    showCtaRow: false,
                    showProvenance: false,
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

InboxItem _inboxItemFromBeacon(Beacon beacon) => InboxItem(
      beaconId: beacon.id,
      latestForwardAt: beacon.updatedAt,
      beacon: beacon,
      context: beacon.context,
      status: InboxItemStatus.watching,
    );
