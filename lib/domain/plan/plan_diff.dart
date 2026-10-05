import 'plan_snapshot.dart';

/// One change between two plan snapshots.
enum PlanChangeOp {
  added('added'),
  removed('removed'),
  retitled('retitled'),
  redescribed('redescribed'),
  retimed('retimed'),
  reassigned('reassigned'),
  moved('moved');

  const PlanChangeOp(this.wire);

  final String wire;

  static PlanChangeOp? fromWire(String? v) {
    for (final op in values) {
      if (op.wire == v) return op;
    }
    return null;
  }

  /// Whether the assignee has to confirm («Понятно») this change.
  ///
  /// Details and order changes do not need confirmation (plan P7).
  bool get needsAck => switch (this) {
    added || removed || retitled || retimed || reassigned => true,
    redescribed || moved => false,
  };
}

/// A single plan change, l10n-neutral (stored in `changes_json`).
final class PlanChange {
  const PlanChange({
    required this.op,
    required this.stepId,
    required this.title,
    this.fromTitle,
    this.fromStartAt,
    this.toStartAt,
    this.fromEndAt,
    this.toEndAt,
    this.fromAssigneeId,
    this.toAssigneeId,
  });

  factory PlanChange.fromJson(Map<String, Object?> json) => PlanChange(
    op: PlanChangeOp.fromWire(json['op'] as String?) ?? PlanChangeOp.moved,
    stepId: (json['stepId'] as String?) ?? '',
    title: (json['title'] as String?) ?? '',
    fromTitle: json['fromTitle'] as String?,
    fromStartAt: _instant(json['fromStartAt']),
    toStartAt: _instant(json['toStartAt']),
    fromEndAt: _instant(json['fromEndAt']),
    toEndAt: _instant(json['toEndAt']),
    fromAssigneeId: json['fromAssigneeId'] as String?,
    toAssigneeId: json['toAssigneeId'] as String?,
  );

  final PlanChangeOp op;
  final String stepId;

  /// Title after the change (before it, for `removed`).
  final String title;
  final String? fromTitle;
  final DateTime? fromStartAt;
  final DateTime? toStartAt;
  final DateTime? fromEndAt;
  final DateTime? toEndAt;
  final String? fromAssigneeId;
  final String? toAssigneeId;

  /// People whose own steps this change touches.
  Set<String> get affectedUserIds {
    if (!op.needsAck) return const {};
    return {?fromAssigneeId, ?toAssigneeId};
  }

  Map<String, Object?> toJson() => {
    'op': op.wire,
    'stepId': stepId,
    'title': title,
    if (fromTitle != null) 'fromTitle': fromTitle,
    if (op == PlanChangeOp.retimed) ...{
      'fromStartAt': formatPlanInstant(fromStartAt),
      'toStartAt': formatPlanInstant(toStartAt),
      'fromEndAt': formatPlanInstant(fromEndAt),
      'toEndAt': formatPlanInstant(toEndAt),
    },
    if (fromAssigneeId != null) 'fromAssigneeId': fromAssigneeId,
    if (toAssigneeId != null) 'toAssigneeId': toAssigneeId,
  };

  @override
  String toString() => 'PlanChange(${op.wire}, $stepId)';
}

abstract final class PlanDiff {
  /// Changes that turn [from] into [to], in the order of [to] (removals last).
  ///
  /// Each step yields at most one change per kind; a step that is both
  /// retitled and retimed yields two entries.
  static List<PlanChange> between(PlanSnapshot from, PlanSnapshot to) {
    final before = from.byId;
    final after = to.byId;
    final changes = <PlanChange>[];
    final movedIds = planMovedStepIds(from, to);
    for (final step in to.steps) {
      final old = before[step.id];
      if (old == null) {
        changes.add(
          PlanChange(
            op: PlanChangeOp.added,
            stepId: step.id,
            title: step.title,
            toAssigneeId: step.assigneeId,
            toStartAt: step.startAt,
            toEndAt: step.endAt,
          ),
        );
        continue;
      }
      if (old.title != step.title) {
        changes.add(
          PlanChange(
            op: PlanChangeOp.retitled,
            stepId: step.id,
            title: step.title,
            fromTitle: old.title,
            fromAssigneeId: step.assigneeId,
          ),
        );
      }
      if (old.description != step.description) {
        changes.add(
          PlanChange(
            op: PlanChangeOp.redescribed,
            stepId: step.id,
            title: step.title,
          ),
        );
      }
      if (!_same(old.startAt, step.startAt) || !_same(old.endAt, step.endAt)) {
        changes.add(
          PlanChange(
            op: PlanChangeOp.retimed,
            stepId: step.id,
            title: step.title,
            fromStartAt: old.startAt,
            toStartAt: step.startAt,
            fromEndAt: old.endAt,
            toEndAt: step.endAt,
            fromAssigneeId: old.assigneeId == step.assigneeId
                ? step.assigneeId
                : null,
          ),
        );
      }
      if (old.assigneeId != step.assigneeId) {
        changes.add(
          PlanChange(
            op: PlanChangeOp.reassigned,
            stepId: step.id,
            title: step.title,
            fromAssigneeId: old.assigneeId,
            toAssigneeId: step.assigneeId,
          ),
        );
      }
      if (movedIds.contains(step.id)) {
        changes.add(
          PlanChange(
            op: PlanChangeOp.moved,
            stepId: step.id,
            title: step.title,
          ),
        );
      }
    }
    for (final old in from.steps) {
      if (!after.containsKey(old.id)) {
        changes.add(
          PlanChange(
            op: PlanChangeOp.removed,
            stepId: old.id,
            title: old.title,
            fromAssigneeId: old.assigneeId,
          ),
        );
      }
    }
    return changes;
  }

  /// Everyone whose own steps [changes] touch.
  static Set<String> affectedUserIds(Iterable<PlanChange> changes) => {
    for (final c in changes) ...c.affectedUserIds,
  };
}

/// Steps whose relative order changed between [from] and [to]: the ids outside
/// a longest common subsequence of the two orders (steps present in both).
Set<String> planMovedStepIds(PlanSnapshot from, PlanSnapshot to) {
  final toIds = to.ids.toSet();
  final fromIds = from.ids.toSet();
  final a = [
    for (final id in from.ids)
      if (toIds.contains(id)) id,
  ];
  final b = [
    for (final id in to.ids)
      if (fromIds.contains(id)) id,
  ];
  if (a.length < 2) return const {};
  final kept = _lcs(a, b).toSet();
  return {
    for (final id in b)
      if (!kept.contains(id)) id,
  };
}

List<String> _lcs(List<String> a, List<String> b) {
  final n = a.length;
  final m = b.length;
  final dp = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      dp[i][j] = a[i] == b[j]
          ? dp[i + 1][j + 1] + 1
          : (dp[i + 1][j] >= dp[i][j + 1] ? dp[i + 1][j] : dp[i][j + 1]);
    }
  }
  final out = <String>[];
  var i = 0;
  var j = 0;
  while (i < n && j < m) {
    if (a[i] == b[j]) {
      out.add(a[i]);
      i++;
      j++;
    } else if (dp[i + 1][j] >= dp[i][j + 1]) {
      i++;
    } else {
      j++;
    }
  }
  return out;
}

bool _same(DateTime? a, DateTime? b) =>
    a?.millisecondsSinceEpoch == b?.millisecondsSinceEpoch;

DateTime? _instant(Object? v) =>
    v is String && v.isNotEmpty ? DateTime.tryParse(v)?.toUtc() : null;
