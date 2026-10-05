import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:tentura_root/domain/plan/plan.dart';

import 'package:tentura/domain/entity/beacon_room_consts.dart';

import 'plan_revision.dart';

/// A plan system line in the discussion (`system_message_kind = 5`, markers
/// 13..16, plan §4.8). The payload is l10n-neutral; [tryParse] returns null
/// for a broken shape so the tile falls back to «Изменение плана».
@immutable
sealed class PlanRoomLine {
  const PlanRoomLine();

  static PlanRoomLine? tryParse({
    required int? marker,
    required String? payloadJson,
  }) {
    final map = _decode(payloadJson);
    if (map == null) return null;
    try {
      return switch (marker) {
        BeaconRoomSemanticMarker.planRevised => PlanRevisedLine._fromJson(map),
        BeaconRoomSemanticMarker.planStepsDone => PlanStepsDoneLine._fromJson(
          map,
        ),
        BeaconRoomSemanticMarker.planCantMake => PlanCantMakeLine._fromJson(
          map,
        ),
        BeaconRoomSemanticMarker.planCopied => PlanCopiedLine._fromJson(map),
        _ => null,
      };
    } on Object {
      return null;
    }
  }
}

/// Marker 13: a revision (save, restore, an assignee leaving).
final class PlanRevisedLine extends PlanRoomLine {
  const PlanRevisedLine({
    required this.revisionSeq,
    required this.kind,
    this.actorId,
    this.restoredFromSeq,
    this.changeCount = 0,
    this.changes = const [],
    this.comment = '',
    this.subjectUserId,
  });

  factory PlanRevisedLine._fromJson(Map<String, Object?> json) {
    final seq = _intOrNull(json['revisionSeq']);
    if (seq == null || seq <= 0) throw const FormatException('revisionSeq');
    final raw = json['changes'];
    final changes = [
      if (raw is List)
        for (final c in raw)
          if (c is Map && PlanChangeOp.fromWire(c['op'] as String?) != null)
            PlanChange.fromJson(c.cast<String, Object?>()),
    ];
    return PlanRevisedLine(
      revisionSeq: seq,
      kind: PlanRevisionKind.fromWire(json['revisionKind']),
      actorId: _nonEmpty(json['actorId']),
      restoredFromSeq: _intOrNull(json['restoredFromSeq']),
      changeCount: _intOrNull(json['changeCount']) ?? changes.length,
      changes: changes,
      comment: (json['comment'] as String?)?.trim() ?? '',
      subjectUserId: _nonEmpty(json['subjectUserId']),
    );
  }

  final int revisionSeq;
  final PlanRevisionKind kind;
  final String? actorId;
  final int? restoredFromSeq;

  /// All changes of the revision (the payload carries at most 20).
  final int changeCount;
  final List<PlanChange> changes;
  final String comment;

  /// The person a system revision is about (e.g. who left).
  final String? subjectUserId;
}

/// One tick inside a marker-14 line.
@immutable
final class PlanTickEntry {
  const PlanTickEntry({
    required this.stepId,
    required this.title,
    this.assigneeId,
    this.actorId,
    this.at,
    this.undoneAt,
    this.undoneById,
  });

  final String stepId;
  final String title;
  final String? assigneeId;
  final String? actorId;
  final DateTime? at;

  /// Set when the tick was removed later (plan P17): drawn struck through.
  final DateTime? undoneAt;
  final String? undoneById;

  bool get isUndone => undoneAt != null;

  /// Someone other than the assignee ticked it.
  bool get tickedForOther =>
      actorId != null && assigneeId != null && actorId != assigneeId;
}

/// Marker 14: coalesced ticks.
final class PlanStepsDoneLine extends PlanRoomLine {
  const PlanStepsDoneLine(this.ticks);

  factory PlanStepsDoneLine._fromJson(Map<String, Object?> json) {
    final raw = json['ticks'];
    if (raw is! List) throw const FormatException('ticks');
    final ticks = [
      for (final t in raw)
        if (t is Map && t['stepId'] is String)
          PlanTickEntry(
            stepId: t['stepId']! as String,
            title: (t['title'] as String?) ?? '',
            assigneeId: _nonEmpty(t['assigneeId']),
            actorId: _nonEmpty(t['actorId']),
            at: _instant(t['at']),
            undoneAt: _instant(t['undoneAt']),
            undoneById: _nonEmpty(t['undoneById']),
          ),
    ];
    if (ticks.isEmpty) throw const FormatException('ticks');
    return PlanStepsDoneLine(ticks);
  }

  final List<PlanTickEntry> ticks;
}

enum PlanCantMakeLineOption { reschedule, handover, unknown }

/// Marker 15: «Не успеваю» with a move or a handover.
final class PlanCantMakeLine extends PlanRoomLine {
  const PlanCantMakeLine({
    required this.option,
    required this.title,
    this.actorId,
    this.stepId,
    this.fromStartAt,
    this.toStartAt,
    this.fromEndAt,
    this.toEndAt,
    this.shiftMinutes,
    this.toUserId,
    this.revisionSeq,
  });

  factory PlanCantMakeLine._fromJson(Map<String, Object?> json) =>
      PlanCantMakeLine(
        option: switch (json['option']) {
          'reschedule' => PlanCantMakeLineOption.reschedule,
          'handover' => PlanCantMakeLineOption.handover,
          _ => PlanCantMakeLineOption.unknown,
        },
        title: (json['title'] as String?) ?? '',
        actorId: _nonEmpty(json['actorId']),
        stepId: _nonEmpty(json['stepId']),
        fromStartAt: _instant(json['fromStartAt']),
        toStartAt: _instant(json['toStartAt']),
        fromEndAt: _instant(json['fromEndAt']),
        toEndAt: _instant(json['toEndAt']),
        shiftMinutes: _intOrNull(json['shiftMinutes']),
        toUserId: _nonEmpty(json['toUserId']),
        revisionSeq: _intOrNull(json['revisionSeq']),
      );

  final PlanCantMakeLineOption option;
  final String title;
  final String? actorId;
  final String? stepId;
  final DateTime? fromStartAt;
  final DateTime? toStartAt;
  final DateTime? fromEndAt;
  final DateTime? toEndAt;
  final int? shiftMinutes;
  final String? toUserId;
  final int? revisionSeq;

  /// How far the step moved: the payload's `shiftMinutes`, else start → start,
  /// else end → end. Null when it cannot be told.
  Duration? get shift {
    final minutes = shiftMinutes;
    if (minutes != null) return Duration(minutes: minutes);
    final fs = fromStartAt;
    final ts = toStartAt;
    if (fs != null && ts != null) return ts.difference(fs);
    final fe = fromEndAt;
    final te = toEndAt;
    if (fe != null && te != null) return te.difference(fe);
    return null;
  }

  /// The new time when [shift] is unknown.
  DateTime? get movedTo => toStartAt ?? toEndAt;
}

/// Marker 16: the plan came with a copy of another Request.
final class PlanCopiedLine extends PlanRoomLine {
  const PlanCopiedLine({required this.sourceBeaconId, this.stepCount = 0});

  factory PlanCopiedLine._fromJson(Map<String, Object?> json) => PlanCopiedLine(
    sourceBeaconId: _nonEmpty(json['sourceBeaconId']) ?? '',
    stepCount: _intOrNull(json['stepCount']) ?? 0,
  );

  /// A reference by id only (ADR 0004 Decision 8): the title is shown only
  /// when the viewer can read the source.
  final String sourceBeaconId;
  final int stepCount;
}

Map<String, Object?>? _decode(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  try {
    final decoded = jsonDecode(raw);
    return decoded is Map ? decoded.cast<String, Object?>() : null;
  } on Object {
    return null;
  }
}

int? _intOrNull(Object? v) => switch (v) {
  final int i => i,
  final num n => n.toInt(),
  final String s => int.tryParse(s),
  _ => null,
};

String? _nonEmpty(Object? v) => v is String && v.isNotEmpty ? v : null;

DateTime? _instant(Object? v) =>
    v is String && v.isNotEmpty ? DateTime.tryParse(v)?.toUtc() : null;
