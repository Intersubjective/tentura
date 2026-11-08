import 'dart:async';
import 'package:flutter/material.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/util/ui_utils.dart';
import 'package:tentura/ui/widget/auto_leading_with_fallback.dart';
import 'package:tentura/ui/widget/show_anchored_popup_menu.dart';

import '../../domain/enum.dart';
import '../bloc/beacon_cubit.dart';
import '../widget/beacon_paged_list.dart';
import 'package:tentura/features/home/ui/widget/home_rail_frame.dart';

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
  late final _beaconCubit = context.read<BeaconCubit>();

  late final _l10n = L10n.of(context)!;

  @override
  void initState() {
    super.initState();
    unawaited(_beaconCubit.fetch());
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

    return HomeRailFrame(
      selectedTab: HomeTab.me,
      child: Scaffold(
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
                      padding: EdgeInsets.symmetric(
                        horizontal: tt.tightGap * 2,
                      ),
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
          minimum: EdgeInsets.symmetric(horizontal: context.tt.screenHPadding),
          child: TenturaContentColumn(
            child: BlocBuilder<BeaconCubit, BeaconState>(
              bloc: _beaconCubit,
              buildWhen: (_, c) => c.isSuccess || c.isLoading || c.hasError,
              builder: (context, state) => BeaconPagedList(
                beacons: state.beacons,
                isLoading: state.isLoading,
                hasError: state.hasError,
                onFetchMore: _beaconCubit.fetch,
                onReload: _onRefresh,
                showAuthor: false,
                empty: TenturaEmptyState(
                  icon: Icons.campaign_outlined,
                  title: _l10n.noBeaconsMessage,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
