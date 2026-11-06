import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/widget/help_path_chain_row.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/help_path_node.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/beacon_hud_row_lead.dart';

/// «Help came through A → B → C» rows on a closed Request (#774), above the
/// closure results card. One tappable row per admitted helper whose path has a
/// forwarder between author and helper; hidden when the server returns no path
/// for the viewer.
class ClosureHelpPathBlock extends StatefulWidget {
  const ClosureHelpPathBlock({
    required this.beaconId,
    required this.admittedHelpers,
    super.key,
  });

  final String beaconId;
  final List<Profile> admittedHelpers;

  @override
  State<ClosureHelpPathBlock> createState() => _ClosureHelpPathBlockState();
}

class _LoadedHelpPathRow {
  const _LoadedHelpPathRow({
    required this.helpOffererId,
    required this.helpOffererName,
    required this.path,
  });

  final String helpOffererId;
  final String helpOffererName;
  final List<HelpPathNode> path;
}

class _ClosureHelpPathBlockState extends State<ClosureHelpPathBlock> {
  late Future<List<_LoadedHelpPathRow>> _rowsFuture;
  int _loadEpoch = 0;

  ForwardRepository? get _forwardRepository =>
      GetIt.I.isRegistered<ForwardRepository>()
      ? GetIt.I<ForwardRepository>()
      : null;

  @override
  void initState() {
    super.initState();
    _rowsFuture = _loadForEpoch(++_loadEpoch);
  }

  @override
  void didUpdateWidget(covariant ClosureHelpPathBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.beaconId != widget.beaconId ||
        !_sameHelpers(oldWidget.admittedHelpers, widget.admittedHelpers)) {
      _rowsFuture = _loadForEpoch(++_loadEpoch);
    }
  }

  bool _sameHelpers(List<Profile> a, List<Profile> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }

  Future<List<_LoadedHelpPathRow>> _loadForEpoch(int epoch) async {
    final rows = await _load();
    if (!mounted || epoch != _loadEpoch) return const [];
    return rows;
  }

  Future<List<_LoadedHelpPathRow>> _load() async {
    final repo = _forwardRepository;
    if (repo == null) return const [];

    final helpers = widget.admittedHelpers;
    if (helpers.isEmpty) return const [];

    final loaded = <_LoadedHelpPathRow>[];
    for (final helper in helpers) {
      try {
        final graph = await repo.fetchHelpOffererForwardPath(
          beaconId: widget.beaconId,
          helpOffererId: helper.id,
        );
        final path = graph.path;
        if (!helpPathShowsClosureRow(path)) continue;
        loaded.add(
          _LoadedHelpPathRow(
            helpOffererId: helper.id,
            helpOffererName: helper.shownName,
            path: path,
          ),
        );
      } on Object {
        // Optional block: stay hidden for this helper on failure.
      }
    }
    return loaded;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_LoadedHelpPathRow>>(
      future: _rowsFuture,
      builder: (context, snapshot) {
        final rows = snapshot.data;
        if (rows == null || rows.isEmpty) return const SizedBox.shrink();

        final l10n = L10n.of(context)!;
        final tt = context.tt;
        final screenCubit = context.read<ScreenCubit>();

        return Padding(
          padding: EdgeInsets.only(bottom: tt.cardGap),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BeaconHudIconRow(
                leadIcon: Icons.route_outlined,
                semanticsLabel: l10n.closureHelpPathTitle,
                body: Text(
                  l10n.closureHelpPathTitle,
                  style: TenturaText.bodySmall(tt.text),
                ),
              ),
              for (final row in rows) ...[
                SizedBox(height: tt.tightGap),
                HelpPathChainRow(
                  path: row.path,
                  onTap: () => screenCubit.showConstellationForwardTreeFor(
                    beaconId: widget.beaconId,
                    helpOffererId: row.helpOffererId,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
