import 'dart:async';
import 'package:flutter/material.dart';
import 'package:auto_route/auto_route.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/linear_pi_active.dart';

import '../../domain/enum.dart';
import '../bloc/beacon_cubit.dart';
import '../widget/beacon_tile.dart';

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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_l10n.beaconsTitle),
      leading: const AutoLeadingButton(),
      actions: [
        BlocSelector<BeaconCubit, BeaconState, BeaconFilter>(
          selector: (state) => state.filter,
          builder: (_, filter) => Padding(
            padding: const EdgeInsets.only(right: kSpacingMedium),
            child: DropdownButton<BeaconFilter>(
              icon: const Icon(Icons.filter_alt),
              items: [
                DropdownMenuItem(
                  value: BeaconFilter.enabled,
                  child: Text(_l10n.beaconsFilterEnabled),
                ),
                DropdownMenuItem(
                  value: BeaconFilter.disabled,
                  child: Text(_l10n.beaconsFilterDisabled),
                ),
              ],
              onChanged: _beaconCubit.setFilter,
              value: filter,
              dropdownColor: Theme.of(context).colorScheme.surfaceContainer,
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
    body: BlocBuilder<BeaconCubit, BeaconState>(
      bloc: _beaconCubit,
      buildWhen: (_, c) => c.isSuccess,
      builder: (context, state) => state.beacons.isEmpty
          ? Center(
              child: Text(
                _l10n.noBeaconsMessage,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            )
          : Padding(
              padding: kPaddingSmallH,
              child: ListView.builder(
                key: ValueKey(state.beacons),
                controller: _scrollController,
                itemCount: state.beacons.length,
                itemBuilder: (_, i) {
                  final beacon = state.beacons[i];
                  return Padding(
                    padding: kPaddingSmallV,
                    child: BeaconTile(
                      key: ValueKey(beacon),
                      isMine: state.isMine,
                      beacon: beacon,
                    ),
                  );
                },
              ),
            ),
    ),
  );
}
