import 'dart:async';
import 'package:flutter/material.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/auto_leading_with_fallback.dart';
import 'package:tentura/ui/widget/linear_pi_active.dart';

import '../bloc/involved_beacon_cubit.dart';
import '../widget/beacon_tile.dart';

@RoutePage()
class InvolvedBeaconScreen extends StatefulWidget implements AutoRouteWrapper {
  const InvolvedBeaconScreen({
    @PathParam('id') this.id = '',
    super.key,
  });

  /// Id of the beacon author whose involved beacons to show.
  final String id;

  @override
  Widget wrappedRoute(_) => localScreenCubitScope(
    child: BlocProvider(
      create: (_) => InvolvedBeaconCubit(authorId: id),
      child: this,
    ),
  );

  @override
  State<InvolvedBeaconScreen> createState() => _InvolvedBeaconScreenState();
}

class _InvolvedBeaconScreenState extends State<InvolvedBeaconScreen> {
  final _scrollController = ScrollController();

  late final _involvedBeaconCubit = context.read<InvolvedBeaconCubit>();

  late final _l10n = L10n.of(context)!;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      if (_scrollController.hasClients &&
          _scrollController.offset >
              _scrollController.position.maxScrollExtent * kFetchListOffset) {
        unawaited(_involvedBeaconCubit.fetch());
      }
    });
    unawaited(_involvedBeaconCubit.fetch());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _onRefresh() => _involvedBeaconCubit.fetch(reset: true);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tt = context.tt;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: Text(_l10n.beaconsInvolvedInTitle),
        leading: const AutoLeadingWithFallback(fallbackPath: kPathHome),
        bottom: PreferredSize(
          preferredSize: LinearPiActive.size,
          child: BlocSelector<InvolvedBeaconCubit, InvolvedBeaconState, bool>(
            selector: (state) => state.isLoading,
            builder: LinearPiActive.builder,
            bloc: _involvedBeaconCubit,
          ),
        ),
      ),
      body: SafeArea(
        minimum: kPaddingSmallH,
        child: TenturaContentColumn(
          child:
              BlocBuilder<InvolvedBeaconCubit, InvolvedBeaconState>(
            bloc: _involvedBeaconCubit,
            buildWhen: (_, c) => c.isSuccess || c.isLoading || c.hasError,
            builder: (context, state) {
            if (state.isLoading && state.beacons.isEmpty) {
              return const Center(
                child: CircularProgressIndicator.adaptive(),
              );
            }
            if (state.hasError && state.beacons.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 48,
                      color: scheme.error,
                    ),
                    const SizedBox(height: kSpacingMedium),
                    FilledButton(
                      onPressed: () =>
                          unawaited(_involvedBeaconCubit.fetch(reset: true)),
                      child: Text(_l10n.myWorkRetry),
                    ),
                  ],
                ),
              );
            }
            if (state.beacons.isEmpty) {
              return RefreshIndicator.adaptive(
                onRefresh: _onRefresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    SizedBox(
                      height: MediaQuery.sizeOf(context).height * 0.4,
                      child: Center(
                        child: Padding(
                          padding: tt.cardPadding,
                          child: Semantics(
                            label: _l10n.noInvolvedBeaconsMessage,
                            child: Text(
                              _l10n.noInvolvedBeaconsMessage,
                              style: TenturaText.bodyMedium(scheme.onSurfaceVariant),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }
            return RefreshIndicator.adaptive(
              onRefresh: _onRefresh,
              child: ListView.builder(
                key: ValueKey(state.beacons),
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: kPaddingSmallV,
                itemCount: state.beacons.length,
                itemBuilder: (_, i) {
                  final beacon = state.beacons[i];
                  return Padding(
                    padding: kPaddingSmallV,
                    child: BeaconTile(
                      key: ValueKey(beacon.id),
                      beacon: beacon,
                      onOpenBeacon: () => context.router.push(
                        BeaconViewRoute(id: beacon.id),
                      ),
                      onForward: () => context.router.push(
                        ForwardBeaconRoute(beaconId: beacon.id),
                      ),
                    ),
                  );
                },
              ),
            );
            },
          ),
        ),
      ),
    );
  }
}
