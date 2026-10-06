import 'package:intl/intl.dart';
import 'package:tentura_root/domain/plan/plan.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/duration_format.dart';

import '../../domain/entity/beacon_plan.dart';
import '../../domain/entity/plan_conflict.dart';
import '../../domain/entity/plan_revision.dart';
import '../../domain/exception/beacon_plan_exceptions.dart';
import '../bloc/plan_state.dart';

/// People the plan can name: admitted members (with avatars) plus the
/// server's `names` map for everyone else it mentions.
final class PlanPeople {
  PlanPeople({required List<Profile> admitted, Map<String, String>? names})
    : admitted = List.unmodifiable(admitted),
      _byId = {for (final p in admitted) p.id: p},
      _names = names ?? const {};

  /// Who a step may be assigned to (author, stewards, admitted helpers).
  final List<Profile> admitted;
  final Map<String, Profile> _byId;
  final Map<String, String> _names;

  PlanPeople withNames(Map<String, String> names) =>
      PlanPeople(admitted: admitted, names: {..._names, ...names});

  bool isAdmitted(String id) => _byId.containsKey(id);

  /// A profile for the avatar: the admitted member, else a name-only one.
  Profile profileOf(String id, L10n l10n) =>
      _byId[id] ?? Profile(id: id, displayName: nameOf(id, l10n));

  String nameOf(String? id, L10n l10n) {
    if (id == null) return l10n.planNoAssignee;
    final p = _byId[id];
    if (p != null && p.shownName.trim().isNotEmpty) return p.shownName.trim();
    final n = _names[id]?.trim();
    if (n != null && n.isNotEmpty) return n;
    return l10n.planDeletedUser;
  }
}

/// `HH:mm` in the viewer's zone.
String planTime(DateTime t, String localeName) =>
    DateFormat.Hm(localeName).format(t.toLocal());

/// Day header of a plan group, e.g. «сб, 12 окт.».
String planDayLabel(DateTime t, String localeName) =>
    DateFormat.MMMEd(localeName).format(t.toLocal());

/// Short day + time used in sheets and history (`сб, 12 окт. 10:00`).
String planDayTime(DateTime t, String localeName) =>
    '${planDayLabel(t, localeName)} ${planTime(t, localeName)}';

/// The time slot of a step row: `10:00`, `10:00–11:30`, `до 11:30` or `—`.
String planStepTimeLabel({
  required DateTime? startAt,
  required DateTime? endAt,
  required L10n l10n,
}) {
  final loc = l10n.localeName;
  if (startAt != null && endAt != null) {
    return '${planTime(startAt, loc)}–${planTime(endAt, loc)}';
  }
  if (startAt != null) return planTime(startAt, loc);
  if (endAt != null) return l10n.planEndOnly(planTime(endAt, loc));
  return l10n.planUntimed;
}

/// Full time of a step for the sheet and history: «сб, 12 окт. 10:00 – 10:30».
String planStepWhenLabel({
  required DateTime? startAt,
  required DateTime? endAt,
  required L10n l10n,
}) {
  final loc = l10n.localeName;
  if (startAt != null && endAt != null) {
    final sameDay = PlanDays.isSameDayLocal(startAt.toLocal(), endAt.toLocal());
    return sameDay
        ? '${planDayTime(startAt, loc)} – ${planTime(endAt, loc)}'
        : '${planDayTime(startAt, loc)} – ${planDayTime(endAt, loc)}';
  }
  if (startAt != null) return planDayTime(startAt, loc);
  if (endAt != null) return l10n.planEndOnly(planDayTime(endAt, loc));
  return l10n.planUntimedSemantics;
}

String planDuration(Duration d, L10n l10n) =>
    formatCompactDurationRemaining(d, l10n);

/// The note after a save conflict: which steps someone else changed (and
/// who), now carrying their version in the draft.
String planConflictNoticeText(
  List<PlanConflictStep> steps,
  PlanPeople people,
  L10n l10n,
) {
  String? nameOf(PlanConflictStep s) {
    final name = s.actorName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final id = s.actorId;
    return id == null ? null : people.nameOf(id, l10n);
  }

  if (steps.length == 1) {
    final name = nameOf(steps.single);
    if (name != null) {
      return l10n.planConflictStepChanged(name, steps.single.title);
    }
  }
  return l10n.planConflictStepsChanged(
    [
      for (final s in steps)
        if (nameOf(s) case final name?)
          '«${s.title}» ($name)'
        else
          '«${s.title}»',
    ].join(', '),
  );
}

/// User-facing text for a plan write error.
String planErrorText(Object error, L10n l10n) => switch (error) {
  PlanEditConflictException() => l10n.planErrorConflict,
  PlanStepNotFoundException() => l10n.planErrorStepNotFound,
  PlanNotEditableException() => l10n.planErrorNotEditable,
  PlanActionStaleException() => l10n.planErrorActionStale,
  PlanRestoreSourceMissingException() => l10n.planErrorRestoreSourceMissing,
  PlanRateLimitedException() => l10n.planErrorRateLimited,
  PlanAssigneeNotAdmittedException() => l10n.planErrorAssigneeNotAdmitted,
  PlanTooLargeException() => l10n.planErrorTooLarge,
  PlanDisabledException() => l10n.planErrorDisabled,
  PlanInvalidException() => l10n.planErrorInvalid,
  _ => error.toString(),
};

/// One rendered row of the Plan list.
sealed class PlanListItem {
  const PlanListItem();
}

final class PlanListDay extends PlanListItem {
  const PlanListDay(this.day);

  /// Any instant of the (local) day.
  final DateTime day;
}

final class PlanListNow extends PlanListItem {
  const PlanListNow(this.now);

  final DateTime now;
}

final class PlanListStep extends PlanListItem {
  const PlanListStep(this.step, {this.dimmed = false});

  final PlanStep step;

  /// A neighbour shown for context under the «Mine» filter.
  final bool dimmed;
}

/// Whether [step] passes [filter] for [viewerId].
bool planStepMatches(PlanStep step, PlanFilter filter, String viewerId) =>
    switch (filter.kind) {
      PlanFilterKind.all => true,
      PlanFilterKind.mine => step.assigneeId == viewerId,
      PlanFilterKind.person => step.assigneeId == filter.personId,
      PlanFilterKind.unassigned => step.assigneeId == null,
    };

/// The Plan list: day headers (viewer's zone), the «now» line between the
/// last started step and the next, and the filter. Under «Mine» the steps
/// right before and after each of mine stay visible, dimmed.
List<PlanListItem> buildPlanListItems({
  required List<PlanStep> steps,
  required PlanFilter filter,
  required String viewerId,
  required DateTime now,
}) {
  final keep = <int, bool>{}; // index → dimmed
  for (var i = 0; i < steps.length; i++) {
    if (planStepMatches(steps[i], filter, viewerId)) keep[i] = false;
  }
  if (filter.kind == PlanFilterKind.mine) {
    for (final i in keep.keys.toList()) {
      for (final j in [i - 1, i + 1]) {
        if (j >= 0 && j < steps.length) keep.putIfAbsent(j, () => true);
      }
    }
  }
  if (keep.isEmpty) return const [];

  // The «now» line goes after the last step whose start has come.
  var lastStarted = -1;
  var anyTimed = false;
  for (var i = 0; i < steps.length; i++) {
    final anchor = steps[i].anchorAt;
    if (anchor == null) continue;
    anyTimed = true;
    if (steps[i].startAt != null && !steps[i].startAt!.isAfter(now)) {
      lastStarted = i;
    }
  }

  final items = <PlanListItem>[];
  DateTime? lastDay;
  var nowPlaced = !anyTimed;
  if (!nowPlaced && lastStarted < 0) {
    items.add(PlanListNow(now));
    nowPlaced = true;
  }
  final indexes = keep.keys.toList()..sort();
  for (final i in indexes) {
    final step = steps[i];
    final anchor = step.anchorAt;
    if (!nowPlaced && i > lastStarted) {
      items.add(PlanListNow(now));
      nowPlaced = true;
    }
    if (anchor != null &&
        (lastDay == null || !PlanDays.isSameDayLocal(lastDay, anchor))) {
      items.add(PlanListDay(anchor));
      lastDay = anchor;
    }
    items.add(PlanListStep(step, dimmed: keep[i]!));
  }
  if (!nowPlaced) items.add(PlanListNow(now));
  return items;
}

/// One line per change of a revision, l10n-rendered.
List<String> planChangeLines({
  required List<PlanChange> changes,
  required String Function(String? userId) nameOf,
  required L10n l10n,
}) => [
  for (final c in changes)
    switch (c.op) {
      PlanChangeOp.added => l10n.planOpAdded(
        _withMeta(
          c.title,
          c.toStartAt ?? c.toEndAt,
          c.toAssigneeId,
          nameOf,
          l10n,
        ),
      ),
      PlanChangeOp.removed => l10n.planOpRemoved(c.title),
      PlanChangeOp.retitled => l10n.planOpRetitled(c.fromTitle ?? '', c.title),
      PlanChangeOp.redescribed => l10n.planOpRedescribed(c.title),
      PlanChangeOp.retimed => l10n.planOpRetimed(
        c.title,
        planStepTimeLabelLong(c.fromStartAt, c.fromEndAt, l10n),
        planStepTimeLabelLong(c.toStartAt, c.toEndAt, l10n),
      ),
      PlanChangeOp.reassigned => l10n.planOpReassigned(
        c.title,
        nameOf(c.fromAssigneeId),
        nameOf(c.toAssigneeId),
      ),
      PlanChangeOp.moved => l10n.planOpMoved(c.title),
    },
];

String planStepTimeLabelLong(DateTime? start, DateTime? end, L10n l10n) =>
    start == null && end == null
    ? l10n.planUntimedSemantics
    : planStepWhenLabel(startAt: start, endAt: end, l10n: l10n);

String _withMeta(
  String title,
  DateTime? at,
  String? assigneeId,
  String Function(String?) nameOf,
  L10n l10n,
) {
  final meta = [
    if (at != null) planDayTime(at, l10n.localeName),
    if (assigneeId != null) nameOf(assigneeId),
  ];
  return meta.isEmpty ? title : '$title (${meta.join(', ')})';
}

/// The headline of one history row.
String planRevisionHeadline({
  required PlanRevisionEntry entry,
  required String actorName,
  required BeaconPlan? plan,
  required L10n l10n,
}) => switch (entry.kind) {
  PlanRevisionKind.created => l10n.planHistoryCreated(actorName),
  PlanRevisionKind.restored => l10n.planHistoryRestored(
    actorName,
    entry.restoredFromSeq ?? 0,
  ),
  PlanRevisionKind.copied =>
    plan?.copiedFromTitle != null
        ? l10n.planHistoryCopied(plan!.copiedFromTitle!)
        : l10n.planHistoryCopiedUnknown,
  PlanRevisionKind.cantMake => l10n.planHistoryCantMake(actorName),
  PlanRevisionKind.unassignedOnLeave => l10n.planHistoryUnassignedOnLeave(
    actorName,
  ),
  PlanRevisionKind.edited ||
  PlanRevisionKind.unknown => l10n.planHistoryEdited(actorName),
};

/// «{actor} · {when}: «{step}» {change}» lines for the viewer's pending card.
List<String> planPendingLines({
  required PlanViewerPending pending,
  required String viewerId,
  required String Function(String? userId) nameOf,
  required String actorName,
  required String when,
  required L10n l10n,
}) => [
  for (final p in pending.changes)
    l10n.planChangeOne(
      actorName,
      when,
      p.change.title,
      planPendingChangeText(p.change, viewerId, nameOf, l10n),
    ),
];

String planPendingChangeText(
  PlanChange c,
  String viewerId,
  String Function(String?) nameOf,
  L10n l10n,
) => switch (c.op) {
  PlanChangeOp.added => l10n.planChangeAssignedToYou,
  PlanChangeOp.removed => l10n.planChangeRemoved,
  PlanChangeOp.retitled => l10n.planChangeRenamed,
  PlanChangeOp.retimed => l10n.planChangeMoved(
    planStepTimeLabelLong(c.fromStartAt, c.fromEndAt, l10n),
    planStepTimeLabelLong(c.toStartAt, c.toEndAt, l10n),
  ),
  PlanChangeOp.reassigned =>
    c.toAssigneeId == viewerId
        ? l10n.planChangeAssignedToYou
        : c.toAssigneeId == null
        ? l10n.planChangeUnassigned
        : l10n.planChangeHandedTo(nameOf(c.toAssigneeId)),
  PlanChangeOp.redescribed || PlanChangeOp.moved => l10n.planChangeRenamed,
};

/// Helper that compares local calendar days.
abstract final class PlanDays {
  static bool isSameDayLocal(DateTime a, DateTime b) {
    final x = a.toLocal();
    final y = b.toLocal();
    return x.year == y.year && x.month == y.month && x.day == y.day;
  }
}
