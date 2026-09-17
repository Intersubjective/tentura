import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_summary.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/use_case/beacon_hierarchy_case.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/beacon_card_primitives.dart';
import 'package:tentura/ui/widget/beacon_request_preview_identity.dart';

/// Footer / notice card for a promoted child — same projection as Now list.
///
/// Resolves via [BeaconHierarchyCase.fetchChildPreview] (not involvement).
/// Refetches on hierarchy invalidation / catch-up; evicts when access is lost.
class BeaconChildPromotionFooter extends StatefulWidget {
  const BeaconChildPromotionFooter({required this.childBeaconId, super.key});

  final String childBeaconId;

  @override
  State<BeaconChildPromotionFooter> createState() =>
      _BeaconChildPromotionFooterState();
}

class _BeaconChildPromotionFooterState
    extends State<BeaconChildPromotionFooter> {
  static const _reloadDebounce = Duration(milliseconds: 150);

  BeaconHierarchySummary? _summary;
  var _loaded = false;
  var _loadInFlight = false;
  var _reloadQueued = false;
  int _generation = 0;
  Timer? _reloadTimer;
  StreamSubscription<Object?>? _hierarchySub;
  StreamSubscription<void>? _catchUpSub;
  StreamSubscription<void>? _localSub;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant BeaconChildPromotionFooter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.childBeaconId != widget.childBeaconId) {
      _hierarchySub?.cancel();
      _localSub?.cancel();
      _reloadTimer?.cancel();
      _summary = null;
      _loaded = false;
      _subscribe();
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    _reloadTimer?.cancel();
    _hierarchySub?.cancel();
    _catchUpSub?.cancel();
    _localSub?.cancel();
    super.dispose();
  }

  void _subscribe() {
    final hierarchy = GetIt.I<BeaconHierarchyCase>();
    _hierarchySub = hierarchy
        .hierarchyChangesFor(widget.childBeaconId)
        .listen((_) => _scheduleReload());
    _localSub = hierarchy
        .localHierarchyChangesFor(widget.childBeaconId)
        .listen((_) => _scheduleReload());
    _catchUpSub ??= hierarchy.catchUps.listen((_) => _scheduleReload());
  }

  void _scheduleReload() {
    if (!mounted) return;
    _reloadTimer?.cancel();
    _reloadTimer = Timer(_reloadDebounce, () {
      if (mounted) unawaited(_load());
    });
  }

  Future<void> _load() async {
    if (_loadInFlight) {
      _reloadQueued = true;
      return;
    }
    _loadInFlight = true;
    _reloadQueued = false;
    final gen = ++_generation;
    final childId = widget.childBeaconId;
    try {
      final summary = await GetIt.I<BeaconHierarchyCase>().fetchChildPreview(
        beaconId: childId,
      );
      if (!mounted || gen != _generation || childId != widget.childBeaconId) {
        return;
      }
      setState(() {
        _summary = summary;
        _loaded = true;
      });
    } catch (_) {
      if (!mounted || gen != _generation || childId != widget.childBeaconId) {
        return;
      }
      setState(() {
        _summary = null;
        _loaded = true;
      });
    } finally {
      _loadInFlight = false;
      if (_reloadQueued && mounted) {
        _reloadQueued = false;
        _scheduleReload();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final currentUserId = context.read<ProfileCubit>().state.profile.id;

    if (!_loaded) {
      return const SizedBox.shrink();
    }

    final summary = _summary;
    if (summary == null || summary.isTombstone) {
      return Semantics(
        container: true,
        label: l10n.beaconChildFooterUnavailable,
        child: BeaconCardShell(
          muted: true,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: tt.tightGap),
            child: Text(
              l10n.beaconChildFooterUnavailable,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      );
    }

    final data = BeaconRequestPreviewData.fromHierarchySummary(
      l10n,
      summary,
      now: DateTime.now(),
    );
    return BeaconCardShell(
      onTap: () => context.router.push(BeaconViewRoute(id: summary.beaconId)),
      tapSemanticsLabel: data.title,
      child: BeaconRequestPreviewIdentity(
        data: data,
        currentUserId: currentUserId,
        showDescription: true,
        titleMaxLines: 2,
      ),
    );
  }
}
