import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_summary.dart';

import 'package:tentura/domain/use_case/beacon_hierarchy_case.dart';

/// Loads [BeaconHierarchyCase.fetchChildPreview] for [childBeaconId] and keeps
/// it fresh on hierarchy invalidation / catch-up (debounced, single-flight).
///
/// A failed fetch yields a loaded `null` preview so callers can render the
/// "unavailable" state; stale responses for a previous id are dropped.
mixin ChildBeaconPreviewLoader<T extends StatefulWidget> on State<T> {
  static const _reloadDebounce = Duration(milliseconds: 150);

  String get childBeaconId;

  BeaconHierarchySummary? get childPreview => _preview;

  bool get childPreviewLoaded => _loaded;

  BeaconHierarchySummary? _preview;
  var _loaded = false;
  var _loadInFlight = false;
  var _reloadQueued = false;
  int _generation = 0;
  late String _subscribedId;
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
  void didUpdateWidget(covariant T oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_subscribedId != childBeaconId) {
      unawaited(_hierarchySub?.cancel());
      unawaited(_localSub?.cancel());
      _reloadTimer?.cancel();
      _preview = null;
      _loaded = false;
      _subscribe();
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    _reloadTimer?.cancel();
    unawaited(_hierarchySub?.cancel());
    unawaited(_catchUpSub?.cancel());
    unawaited(_localSub?.cancel());
    super.dispose();
  }

  void _subscribe() {
    final hierarchy = GetIt.I<BeaconHierarchyCase>();
    _subscribedId = childBeaconId;
    _hierarchySub = hierarchy
        .hierarchyChangesFor(childBeaconId)
        .listen((_) => _scheduleReload());
    _localSub = hierarchy
        .localHierarchyChangesFor(childBeaconId)
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
    final childId = childBeaconId;
    BeaconHierarchySummary? summary;
    try {
      summary = await GetIt.I<BeaconHierarchyCase>().fetchChildPreview(
        beaconId: childId,
      );
    } catch (_) {
      summary = null;
    } finally {
      _loadInFlight = false;
    }
    if (mounted && gen == _generation && childId == childBeaconId) {
      setState(() {
        _preview = summary;
        _loaded = true;
      });
    }
    if (_reloadQueued && mounted) {
      _reloadQueued = false;
      _scheduleReload();
    }
  }
}
