import 'dart:convert';
import 'dart:math';

import 'package:meta/meta.dart';

/// Request plan («либретто», #220): one step as stored in a revision snapshot.
///
/// Snapshots carry content only. Ticks («done») live outside revisions, so a
/// snapshot never mentions them. Times are UTC instants; `null` means the step
/// has no start (or no end).
@immutable
final class PlanStepSnapshot {
  const PlanStepSnapshot({
    required this.id,
    required this.title,
    this.description = '',
    this.assigneeId,
    this.startAt,
    this.endAt,
  });

  factory PlanStepSnapshot.fromJson(Map<String, Object?> json) =>
      PlanStepSnapshot(
        id: json['id']! as String,
        title: (json['title'] as String?) ?? '',
        description: (json['description'] as String?) ?? '',
        assigneeId: _nonEmpty(json['assigneeId'] as String?),
        startAt: _parseInstant(json['startAt']),
        endAt: _parseInstant(json['endAt']),
      );

  final String id;
  final String title;
  final String description;
  final String? assigneeId;
  final DateTime? startAt;
  final DateTime? endAt;

  /// No start and no end: the step runs after the previous one (`—`).
  bool get isUntimed => startAt == null && endAt == null;

  PlanStepSnapshot copyWith({
    String? title,
    String? description,
    String? Function()? assigneeId,
    DateTime? Function()? startAt,
    DateTime? Function()? endAt,
  }) => PlanStepSnapshot(
    id: id,
    title: title ?? this.title,
    description: description ?? this.description,
    assigneeId: assigneeId == null ? this.assigneeId : assigneeId(),
    startAt: startAt == null ? this.startAt : startAt(),
    endAt: endAt == null ? this.endAt : endAt(),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'assigneeId': assigneeId,
    'startAt': formatPlanInstant(startAt),
    'endAt': formatPlanInstant(endAt),
  };

  /// Content equality: the fields a merge compares.
  bool sameContentAs(PlanStepSnapshot other) =>
      title == other.title &&
      description == other.description &&
      assigneeId == other.assigneeId &&
      _sameInstant(startAt, other.startAt) &&
      _sameInstant(endAt, other.endAt);

  @override
  bool operator ==(Object other) =>
      other is PlanStepSnapshot && other.id == id && sameContentAs(other);

  @override
  int get hashCode => Object.hash(
    id,
    title,
    description,
    assigneeId,
    startAt?.millisecondsSinceEpoch,
    endAt?.millisecondsSinceEpoch,
  );

  @override
  String toString() => 'PlanStepSnapshot($id, $title)';
}

/// The whole plan content at one revision, in plan order.
final class PlanSnapshot {
  const PlanSnapshot(this.steps);

  factory PlanSnapshot.fromJson(Object? json) {
    final list = switch (json) {
      final String s when s.isNotEmpty => jsonDecode(s),
      final List<Object?> l => l,
      _ => const <Object?>[],
    };
    if (list is! List) return empty;
    return PlanSnapshot([
      for (final e in list)
        if (e is Map) PlanStepSnapshot.fromJson(e.cast<String, Object?>()),
    ]);
  }

  static const empty = PlanSnapshot([]);

  final List<PlanStepSnapshot> steps;

  bool get isEmpty => steps.isEmpty;

  int get length => steps.length;

  List<String> get ids => [for (final s in steps) s.id];

  Map<String, PlanStepSnapshot> get byId => {for (final s in steps) s.id: s};

  PlanStepSnapshot? operator [](String id) {
    for (final s in steps) {
      if (s.id == id) return s;
    }
    return null;
  }

  List<Map<String, Object?>> toJson() => [for (final s in steps) s.toJson()];

  String encode() => jsonEncode(toJson());

  /// Same steps, same order, same content.
  bool sameAs(PlanSnapshot other) {
    if (other.steps.length != steps.length) return false;
    for (var i = 0; i < steps.length; i++) {
      if (steps[i] != other.steps[i]) return false;
    }
    return true;
  }
}

/// Wire format for plan instants: UTC ISO-8601 with milliseconds.
String? formatPlanInstant(DateTime? v) => v?.toUtc().toIso8601String();

DateTime? _parseInstant(Object? v) => switch (v) {
  final String s when s.isNotEmpty => DateTime.tryParse(s)?.toUtc(),
  _ => null,
};

String? _nonEmpty(String? v) => (v == null || v.isEmpty) ? null : v;

bool _sameInstant(DateTime? a, DateTime? b) =>
    a?.millisecondsSinceEpoch == b?.millisecondsSinceEpoch;

final _stepIdRandom = Random.secure();

/// A fresh plan step id: `PS` + 12 hex digits (plan P6). The client mints it
/// so a draft survives a conflict and a retry; the server checks the shape
/// and collisions.
String newPlanStepId([Random? random]) {
  final r = random ?? _stepIdRandom;
  final b = StringBuffer('PS');
  for (var i = 0; i < 12; i++) {
    b.write(r.nextInt(16).toRadixString(16));
  }
  return b.toString();
}
