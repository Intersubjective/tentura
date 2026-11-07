import 'dart:async';
import 'package:flutter/material.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/auto_leading_with_fallback.dart';

import '../bloc/involved_beacon_cubit.dart';
import '../widget/beacon_paged_list.dart';

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
  late final _involvedBeaconCubit = context.read<InvolvedBeaconCubit>();

  late final _l10n = L10n.of(context)!;

  @override
  void initState() {
    super.initState();
    unawaited(_involvedBeaconCubit.fetch());
  }

  Future<void> _onRefresh() => _involvedBeaconCubit.fetch(reset: true);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: TenturaTopBar.of(
        context,
        title: Text(_l10n.beaconsInvolvedInTitle),
        leading: const AutoLeadingWithFallback(fallbackPath: kPathHome),
        progress: BlocSelector<InvolvedBeaconCubit, InvolvedBeaconState, bool>(
          selector: (state) => state.isLoading,
          builder: TenturaTopBar.loadingBar,
          bloc: _involvedBeaconCubit,
        ),
      ),
      body: SafeArea(
        minimum: EdgeInsets.symmetric(horizontal: context.tt.screenHPadding),
        child: TenturaContentColumn(
          child: BlocBuilder<InvolvedBeaconCubit, InvolvedBeaconState>(
            bloc: _involvedBeaconCubit,
            buildWhen: (_, c) => c.isSuccess || c.isLoading || c.hasError,
            builder: (context, state) => BeaconPagedList(
              beacons: state.beacons,
              isLoading: state.isLoading,
              hasError: state.hasError,
              onFetchMore: _involvedBeaconCubit.fetch,
              onReload: _onRefresh,
              empty: Semantics(
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
      ),
    );
  }
}
