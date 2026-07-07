import 'dart:async';
import 'package:flutter/material.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/auto_leading_with_fallback.dart';
import 'package:tentura/ui/widget/show_anchored_popup_menu.dart';

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
  Widget wrappedRoute(_) => localScreenCubitScope(
    child: BlocProvider(
      create: (_) => BeaconCubit(profileId: id),
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

  String _labelForFilter(BeaconFilter filter) => switch (filter) {
    BeaconFilter.active => _l10n.beaconsFilterActive,
    BeaconFilter.closed => _l10n.beaconsFilterClosed,
  };

  Future<void> _showFilterMenu(BuildContext buttonContext) async {
    final selected = await showAnchoredPopupMenu<BeaconFilter>(
      anchorContext: buttonContext,
      items: [
        for (final f in BeaconFilter.values)
          PopupMenuItem<BeaconFilter>(
            value: f,
            child: Text(_labelForFilter(f)),
          ),
      ],
    );
    if (selected != null && buttonContext.mounted) {
      _beaconCubit.setFilter(selected);
    }
  }

  Future<void> _onRefresh() => _beaconCubit.fetch(reset: true);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tt = context.tt;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: TenturaTopBar.of(
        context,
        title: Text(_l10n.beaconsTitle),
        leading: const AutoLeadingWithFallback(fallbackPath: kPathHome),
        actions: [
          BlocSelector<BeaconCubit, BeaconState, BeaconFilter>(
            selector: (state) => state.filter,
            builder: (context, filter) => Padding(
              padding: EdgeInsets.only(right: tt.tightGap),
              child: Tooltip(
                message: _l10n.myWorkFilterMenuTooltip,
                child: TextButton(
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.symmetric(horizontal: tt.tightGap * 2),
                    minimumSize: Size(tt.buttonHeight, tt.buttonHeight),
                    foregroundColor: scheme.onSurface,
                  ),
                  onPressed: () => unawaited(_showFilterMenu(context)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.filter_alt, color: scheme.onSurface),
                      SizedBox(width: tt.iconTextGap),
                      Flexible(
                        child: Text(
                          _labelForFilter(filter),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TenturaText.labelLarge(
                            scheme.onSurface,
                          ).copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Icon(
                        Icons.arrow_drop_down,
                        color: scheme.onSurface,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
        progress: BlocSelector<BeaconCubit, BeaconState, bool>(
          selector: (state) => state.isLoading,
          builder: TenturaTopBar.loadingBar,
          bloc: _beaconCubit,
        ),
      ),
      body: SafeArea(
        minimum: kPaddingSmallH,
        child: TenturaContentColumn(
          child: BlocBuilder<BeaconCubit, BeaconState>(
            bloc: _beaconCubit,
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
                            unawaited(_beaconCubit.fetch(reset: true)),
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
                              label: _l10n.noBeaconsMessage,
                              child: Text(
                                _l10n.noBeaconsMessage,
                                style: TenturaText.bodyMedium(
                                  scheme.onSurfaceVariant,
                                ),
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
