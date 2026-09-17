import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_summary.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/use_case/beacon_hierarchy_case.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Compact Chat link to a promoted child under its source bubble.
///
/// Resolves via [BeaconHierarchyCase.fetchChildPreview] (not involvement).
/// Refetches on hierarchy invalidation / catch-up; evicts when access is lost.
/// Full request cards stay on NOW ([BeaconChildRequestCard]).
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

  void _openChild(String beaconId) {
    context.router.push(BeaconViewRoute(id: beaconId));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (!_loaded) {
      // Stable compact height while loading — avoid shrink → expand jump.
      return TenturaTextAction(
        label: l10n.beaconHierarchyNoticeChildCreated,
        tone: TenturaTone.neutral,
        icon: const Icon(Icons.subdirectory_arrow_right_outlined),
        flushStart: true,
        onPressed: null,
      );
    }

    final summary = _summary;
    if (summary == null || summary.isTombstone) {
      return Semantics(
        container: true,
        label: l10n.beaconChildFooterUnavailable,
        child: Text(
          l10n.beaconChildFooterUnavailable,
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }

    final title = summary.title?.trim().isNotEmpty == true
        ? summary.title!.trim()
        : l10n.beaconUntitled;

    return TenturaTextAction(
      label: title,
      tone: TenturaTone.info,
      icon: const Icon(Icons.subdirectory_arrow_right_outlined),
      flushStart: true,
      onPressed: () => _openChild(summary.beaconId),
    );
  }
}
