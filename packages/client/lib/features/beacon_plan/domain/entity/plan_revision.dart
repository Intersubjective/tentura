import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:tentura_root/domain/plan/plan.dart';

import 'beacon_plan.dart';

/// `beacon_plan_revision.kind` (server `PlanRevisionKind`).
enum PlanRevisionKind {
  created(0),
  edited(1),
  restored(2),
  copied(3),
  cantMake(4),
  unassignedOnLeave(5),
  unknown(-1);

  const PlanRevisionKind(this.wire);

  final int wire;

  static PlanRevisionKind fromWire(Object? v) {
    for (final k in values) {
      if (k.wire == v) return k;
    }
    return unknown;
  }
}

/// One history row (`beaconPlanRevisions.items[]`).
@immutable
final class PlanRevisionEntry {
  const PlanRevisionEntry({
    required this.seq,
    required this.kind,
    required this.createdAt,
    this.actorId,
    this.comment = '',
    this.restoredFromSeq,
    this.changes = const [],
  });

  factory PlanRevisionEntry.fromJson(Map<String, Object?> json) {
    final raw = json['changes'];
    return PlanRevisionEntry(
      seq: _int(json['seq']),
      kind: PlanRevisionKind.fromWire(json['kind']),
      actorId:
          json['actorId'] is String && (json['actorId']! as String).isNotEmpty
          ? json['actorId']! as String
          : null,
      comment: (json['comment'] as String?) ?? '',
      restoredFromSeq: _intOrNull(json['restoredFromSeq']),
      // Entries with an op the shared domain does not know (e.g. the
      // history-only `cantMake` marker) are dropped from the rendered diff.
      changes: [
        if (raw is List)
          for (final c in raw)
            if (c is Map && PlanChangeOp.fromWire(c['op'] as String?) != null)
              PlanChange.fromJson(c.cast<String, Object?>()),
      ],
      createdAt:
          DateTime.tryParse((json['createdAt'] as String?) ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  final int seq;
  final PlanRevisionKind kind;
  final String? actorId;
  final String comment;
  final int? restoredFromSeq;
  final List<PlanChange> changes;
  final DateTime createdAt;
}

/// One page of the plan history, newest first.
@immutable
final class PlanRevisionPage {
  const PlanRevisionPage({
    this.items = const [],
    this.names = const {},
    this.nextBeforeSeq,
  });

  factory PlanRevisionPage.decode(String raw) {
    final decoded = jsonDecode(raw);
    final map = decoded is Map
        ? decoded.cast<String, Object?>()
        : const <String, Object?>{};
    final items = map['items'];
    return PlanRevisionPage(
      items: [
        if (items is List)
          for (final i in items)
            if (i is Map) PlanRevisionEntry.fromJson(i.cast<String, Object?>()),
      ],
      names: parsePlanNames(map['names']),
      nextBeforeSeq: _intOrNull(map['nextBeforeSeq']),
    );
  }

  final List<PlanRevisionEntry> items;
  final Map<String, String> names;

  /// Cursor for the next (older) page; null on the last page.
  final int? nextBeforeSeq;
}

/// One revision's content (`beaconPlanRevision`).
@immutable
final class PlanRevisionSnapshot {
  const PlanRevisionSnapshot({
    required this.seq,
    required this.kind,
    required this.snapshot,
    this.createdAt,
  });

  factory PlanRevisionSnapshot.decode(String raw) {
    final decoded = jsonDecode(raw);
    final map = decoded is Map
        ? decoded.cast<String, Object?>()
        : const <String, Object?>{};
    final steps = map['steps'];
    return PlanRevisionSnapshot(
      seq: _int(map['seq']),
      kind: PlanRevisionKind.fromWire(map['kind']),
      snapshot: PlanSnapshot.fromJson(steps is List ? steps : const []),
      createdAt: DateTime.tryParse(
        (map['createdAt'] as String?) ?? '',
      )?.toUtc(),
    );
  }

  final int seq;
  final PlanRevisionKind kind;
  final PlanSnapshot snapshot;
  final DateTime? createdAt;
}

int _int(Object? v) => _intOrNull(v) ?? 0;

int? _intOrNull(Object? v) => switch (v) {
  final int i => i,
  final num n => n.toInt(),
  final String s => int.tryParse(s),
  _ => null,
};
