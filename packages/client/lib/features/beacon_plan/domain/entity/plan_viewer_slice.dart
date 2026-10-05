import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:tentura_root/domain/plan/plan.dart';

import 'package:tentura/domain/coordination/beacon_you_plan_slots.dart';

/// One step of a [PlanViewerSlice].
@immutable
final class PlanSliceStep {
  const PlanSliceStep({
    required this.stepId,
    required this.title,
    this.description = '',
    this.startAt,
    this.endAt,
  });

  static PlanSliceStep? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['stepId'];
    if (id is! String || id.isEmpty) return null;
    return PlanSliceStep(
      stepId: id,
      title: (raw['title'] as String?) ?? '',
      description: (raw['description'] as String?) ?? '',
      startAt: _instant(raw['startAt']),
      endAt: _instant(raw['endAt']),
    );
  }

  final String stepId;
  final String title;
  final String description;
  final DateTime? startAt;
  final DateTime? endAt;

  /// The step as the shared schedule rules see it (never done: the slice
  /// only lists open steps).
  PlanStepState get state => PlanStepState(
    id: stepId,
    title: title,
    startAt: startAt,
    endAt: endAt,
  );
}

/// Plan changes to the viewer's own steps waiting for «Понятно».
@immutable
final class PlanSlicePending {
  const PlanSlicePending({
    required this.fromSeq,
    required this.headSeq,
    required this.changeCount,
    this.actorIds = const [],
    this.actorNames = const {},
    this.stepIds = const {},
    this.lastAt,
    this.sample,
  });

  static PlanSlicePending? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final sample = raw['sample'];
    final names = raw['actorNames'];
    return PlanSlicePending(
      fromSeq: _int(raw['fromSeq']),
      headSeq: _int(raw['headSeq']),
      changeCount: _int(raw['changeCount']),
      actorIds: _strings(raw['actorIds']),
      actorNames: {
        if (names is Map)
          for (final MapEntry(:key, :value) in names.entries)
            if (key is String && value is String) key: value,
      },
      stepIds: _strings(raw['stepIds']).toSet(),
      lastAt: _instant(raw['lastAt']),
      sample: sample is Map
          ? PlanChange.fromJson(sample.cast<String, Object?>())
          : null,
    );
  }

  final int fromSeq;

  /// The plan head when the slice was read: «Понятно» confirms up to here.
  final int headSeq;
  final int changeCount;
  final List<String> actorIds;
  final Map<String, String> actorNames;

  /// Steps the pending changes touch.
  final Set<String> stepIds;
  final DateTime? lastAt;

  /// The newest change, to word a single one like the Plan tab does.
  final PlanChange? sample;
}

/// The NOW line when the plan sets it (`effectiveNow`, server-side).
@immutable
final class PlanSliceNow {
  const PlanSliceNow({
    required this.stepId,
    required this.title,
    required this.index,
    required this.count,
    this.assigneeId,
    this.startAt,
  });

  static PlanSliceNow? tryFromJson(Object? raw) {
    if (raw is! Map || raw['source'] != 'plan') return null;
    final id = raw['stepId'];
    if (id is! String || id.isEmpty) return null;
    return PlanSliceNow(
      stepId: id,
      title: (raw['title'] as String?) ?? '',
      assigneeId: raw['assigneeId'] as String?,
      startAt: _instant(raw['startAt']),
      index: _int(raw['index']),
      count: _int(raw['count']),
    );
  }

  final String stepId;
  final String title;
  final String? assigneeId;
  final DateTime? startAt;
  final int index;
  final int count;
}

/// The viewer's share of a Request plan for My Work and the inbox
/// (`planSliceJson`, plan §4.9), computed by the server in one batched read.
///
/// On a finished Request only [done] / [total] are filled, so no row offers
/// an action the server would refuse.
@immutable
final class PlanViewerSlice {
  const PlanViewerSlice({
    required this.done,
    required this.total,
    this.overdueMine = 0,
    this.current,
    this.alsoActive = const [],
    this.next,
    this.pendingAck,
    this.now,
  });

  factory PlanViewerSlice.fromJson(Map<String, Object?> json) {
    final also = json['alsoActive'];
    return PlanViewerSlice(
      done: _int(json['done']),
      total: _int(json['total']),
      overdueMine: _int(json['overdueMine']),
      current: PlanSliceStep.tryFromJson(json['current']),
      alsoActive: [
        if (also is List)
          for (final a in also) ?PlanSliceStep.tryFromJson(a),
      ],
      next: PlanSliceStep.tryFromJson(json['next']),
      pendingAck: PlanSlicePending.tryFromJson(json['pendingAck']),
      now: PlanSliceNow.tryFromJson(json['now']),
    );
  }

  /// Decodes the wire string; null when absent or malformed.
  static PlanViewerSlice? tryDecode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return PlanViewerSlice.fromJson(decoded.cast<String, Object?>());
    } on FormatException {
      return null;
    }
  }

  final int done;
  final int total;

  /// The viewer's own overdue steps.
  final int overdueMine;

  /// The step expected from the viewer now.
  final PlanSliceStep? current;

  /// Other active steps of the viewer («тоже идёт»).
  final List<PlanSliceStep> alsoActive;

  /// The viewer's next step.
  final PlanSliceStep? next;
  final PlanSlicePending? pendingAck;
  final PlanSliceNow? now;

  /// Something of the viewer's own to show (a step or a change).
  bool get hasViewerRows =>
      current != null || next != null || pendingAck != null;

  /// The viewer's schedule rebuilt from the slice, for the shared ladder.
  PlanViewerSchedule schedule(DateTime at) {
    final current = this.current;
    final next = this.next;
    final start = next?.startAt;
    return PlanViewerSchedule(
      current: current?.state,
      alsoActive: [for (final a in alsoActive) a.state],
      next: next?.state,
      freeUntil: current == null && start != null && start.isAfter(at)
          ? start
          : null,
    );
  }

  /// Input of the YOU / BY PLAN / NEXT ladder ([deriveBeaconYouPlanSlots]).
  PlanYouInput youInput(DateTime at) => PlanYouInput(
    schedule: schedule(at),
    pendingAck: pendingAck != null,
    pendingStepIds: pendingAck?.stepIds ?? const {},
  );

  PlanSliceStep? stepById(String id) {
    for (final s in [?current, ...alsoActive, ?next]) {
      if (s.stepId == id) return s;
    }
    return null;
  }

  /// After a local «Готово» on [stepId]: the step leaves the viewer's rows
  /// until the next refresh.
  PlanViewerSlice withoutStep(String stepId) => PlanViewerSlice(
    done: done + 1,
    total: total,
    overdueMine: overdueMine,
    current: current?.stepId == stepId
        ? (alsoActive.isEmpty ? null : alsoActive.first)
        : current,
    alsoActive: current?.stepId == stepId
        ? alsoActive.skip(1).toList(growable: false)
        : [
            for (final a in alsoActive)
              if (a.stepId != stepId) a,
          ],
    next: next?.stepId == stepId ? null : next,
    pendingAck: pendingAck,
    now: now,
  );

  /// After a local «Понятно».
  PlanViewerSlice withoutPending() => PlanViewerSlice(
    done: done,
    total: total,
    overdueMine: overdueMine,
    current: current,
    alsoActive: alsoActive,
    next: next,
    now: now,
  );
}

int _int(Object? v) => v is num ? v.toInt() : 0;

List<String> _strings(Object? v) => [
  if (v is List)
    for (final s in v)
      if (s is String && s.isNotEmpty) s,
];

DateTime? _instant(Object? v) =>
    v is String && v.isNotEmpty ? DateTime.tryParse(v)?.toUtc() : null;
