import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_summary.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/domain/entity/room_message_hierarchy_payload.dart';
import 'package:tentura/domain/use_case/beacon_hierarchy_case.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Hierarchy lifecycle/creation notices in parent Chat.
///
/// Standalone `childCreated` (no source bubble in this page, or source-less
/// create) uses centered join-style chrome — not a request card. Lifecycle
/// notices stay person-free one-liners. Callers that already show a
/// source-message footer must skip the notice row (see [BasicChatBody]).
class BeaconHierarchyNotice extends StatelessWidget {
  const BeaconHierarchyNotice({required this.message, super.key});

  final RoomMessage message;

  /// Whether [message] should be rendered by this widget instead of an
  /// ordinary chat bubble.
  static bool isHierarchyNoticeRow(RoomMessage m) =>
      m.systemMessageKind == BeaconRoomSystemMessageKind.hierarchyLifecycle ||
      m.systemMessageKind == BeaconRoomSystemMessageKind.childCreated;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tt = context.tt;

    final payload = message.hierarchyPayload;
    if (payload is RoomMessageHierarchyChildCreated) {
      return _ChildCreatedCenteredNotice(
        childBeaconId: payload.childBeaconId,
      );
    }

    final line = switch (payload) {
      RoomMessageHierarchyLifecycle() => message.body,
      null => l10n.beaconHierarchyNoticeUnknown,
      RoomMessageHierarchyChildCreated() =>
        l10n.beaconHierarchyNoticeChildCreated,
    };

    return Padding(
      padding: EdgeInsets.fromLTRB(
        tt.screenHPadding,
        tt.tightGap / 2,
        tt.screenHPadding,
        tt.tightGap / 2,
      ),
      child: Semantics(
        label: line,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.info_outline,
              size: 14,
              color: scheme.onSurfaceVariant,
            ),
            SizedBox(width: tt.iconTextGap / 2),
            Flexible(
              child: Text(
                line,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                  height: 1.15,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Centered join-style notice for a standalone `childCreated` row.
class _ChildCreatedCenteredNotice extends StatefulWidget {
  const _ChildCreatedCenteredNotice({required this.childBeaconId});

  final String childBeaconId;

  @override
  State<_ChildCreatedCenteredNotice> createState() =>
      _ChildCreatedCenteredNoticeState();
}

class _ChildCreatedCenteredNoticeState
    extends State<_ChildCreatedCenteredNotice> {
  static const _reloadDebounce = Duration(milliseconds: 150);

  String? _title;
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
  void didUpdateWidget(covariant _ChildCreatedCenteredNotice oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.childBeaconId != widget.childBeaconId) {
      _hierarchySub?.cancel();
      _localSub?.cancel();
      _reloadTimer?.cancel();
      _title = null;
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
        _title = _titleFromSummary(summary);
      });
    } catch (_) {
      if (!mounted || gen != _generation || childId != widget.childBeaconId) {
        return;
      }
      setState(() {
        _title = null;
      });
    } finally {
      _loadInFlight = false;
      if (_reloadQueued && mounted) {
        _reloadQueued = false;
        _scheduleReload();
      }
    }
  }

  String? _titleFromSummary(BeaconHierarchySummary? summary) {
    if (summary == null || summary.isTombstone) return null;
    final t = summary.title?.trim();
    if (t == null || t.isEmpty) return null;
    return t;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tt = context.tt;
    final line = l10n.beaconHierarchyNoticeChildCreated;
    final title = _title;
    final label = title == null ? line : '$line. $title';

    return Padding(
      padding: EdgeInsets.fromLTRB(
        tt.screenHPadding,
        tt.tightGap / 2,
        tt.screenHPadding,
        tt.tightGap / 2,
      ),
      child: Semantics(
        button: true,
        label: label,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: () => context.router.push(
              BeaconViewRoute(id: widget.childBeaconId),
            ),
            borderRadius: BorderRadius.circular(tt.cardRadius),
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: tt.tightGap / 2),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.subdirectory_arrow_right_outlined,
                        size: 14,
                        color: scheme.onSurfaceVariant,
                      ),
                      SizedBox(width: tt.iconTextGap / 2),
                      Flexible(
                        child: Text(
                          line,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                            height: 1.15,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (title != null) ...[
                    SizedBox(height: tt.tightGap / 2),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
