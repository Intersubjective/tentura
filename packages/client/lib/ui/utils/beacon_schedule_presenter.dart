import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/domain/entity/beacon_schedule.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/duration_format.dart';
import 'package:tentura/ui/utils/schedule_date_format.dart';

/// Beyond this lead time the schedule line shows a self-evident absolute date
/// (e.g. "5 May – 8 May") instead of a relative countdown ("starts in …"). A
/// countdown is only intuitive when the anchor is near.
const Duration kScheduleAbsoluteThreshold = Duration(hours: 72);

final class BeaconSchedulePresentation {
  const BeaconSchedulePresentation({
    required this.visibleText,
    required this.semanticsLabel,
    required this.icon,
    required this.urgent,
    required this.phase,
  });

  final String visibleText;
  final String semanticsLabel;
  final IconData icon;
  final bool urgent;
  final BeaconSchedulePhase phase;
}

/// Which schedule template to render, derived purely from timing + lifecycle
/// (no l10n). The presenter turns this into localized text; the card uses
/// [isCountdown] to decide whether a live 1-minute timer is needed.
enum _ScheduleMode {
  eventUpcomingAbsolute,
  eventStartsIn,
  eventUntil,
  eventEndsIn,
  eventNow,
  eventEnded,
  deadlineBy,
  deadlineDueIn,
  deadlineOverdue,
  handoffEnded,
}

extension on _ScheduleMode {
  bool get isCountdown =>
      this == _ScheduleMode.eventStartsIn ||
      this == _ScheduleMode.eventEndsIn ||
      this == _ScheduleMode.deadlineDueIn;
}

class _ScheduleDecision {
  const _ScheduleDecision({
    required this.mode,
    required this.remaining,
    required this.urgent,
  });

  final _ScheduleMode mode;
  final Duration remaining;
  final bool urgent;
}

/// Pure render decision: event vs deadline is derived from the beacon's
/// `scheduleKind` (nullability), and during the review window / terminal
/// lifecycle the line
/// hands off to STATUS (which owns the live clock) and renders a quiet date.
_ScheduleDecision? _decide(Beacon beacon, DateTime now) {
  final kind = beacon.scheduleKind;
  if (kind == BeaconScheduleKind.none) return null;

  // Hand-off: STATUS slot2 (reviewCountdown / lifecycleEndedAt) owns the live
  // urgency in these phases — the schedule line stays quiet historical context.
  final lifecycle = beacon.lifecycle;
  if (lifecycle == BeaconLifecycle.reviewOpen ||
      lifecycle.isFinished ||
      lifecycle == BeaconLifecycle.deleted) {
    return const _ScheduleDecision(
      mode: _ScheduleMode.handoffEnded,
      remaining: Duration.zero,
      urgent: false,
    );
  }

  if (kind == BeaconScheduleKind.deadline) {
    final end = beacon.endAt!;
    if (!now.isBefore(end)) {
      // Passed deadline has a real consequence — legitimately urgent.
      return const _ScheduleDecision(
        mode: _ScheduleMode.deadlineOverdue,
        remaining: Duration.zero,
        urgent: true,
      );
    }
    final remaining = end.difference(now);
    if (remaining > kScheduleAbsoluteThreshold) {
      return _ScheduleDecision(
        mode: _ScheduleMode.deadlineBy,
        remaining: remaining,
        urgent: false,
      );
    }
    return _ScheduleDecision(
      mode: _ScheduleMode.deadlineDueIn,
      remaining: remaining,
      urgent: remaining.inHours < 24,
    );
  }

  // Event (startAt set; window when endAt also set).
  final start = beacon.startAt!;
  final end = beacon.endAt;
  if (now.isBefore(start)) {
    final remaining = start.difference(now);
    if (remaining > kScheduleAbsoluteThreshold) {
      return _ScheduleDecision(
        mode: _ScheduleMode.eventUpcomingAbsolute,
        remaining: remaining,
        urgent: false,
      );
    }
    return _ScheduleDecision(
      mode: _ScheduleMode.eventStartsIn,
      remaining: remaining,
      urgent: remaining.inHours < 24,
    );
  }
  if (end == null) {
    return const _ScheduleDecision(
      mode: _ScheduleMode.eventNow,
      remaining: Duration.zero,
      urgent: false,
    );
  }
  if (!now.isBefore(end)) {
    // A normally-finished event is not urgent — quiet, never "overdue".
    return const _ScheduleDecision(
      mode: _ScheduleMode.eventEnded,
      remaining: Duration.zero,
      urgent: false,
    );
  }
  final remaining = end.difference(now);
  if (remaining > kScheduleAbsoluteThreshold) {
    return _ScheduleDecision(
      mode: _ScheduleMode.eventUntil,
      remaining: remaining,
      urgent: false,
    );
  }
  return _ScheduleDecision(
    mode: _ScheduleMode.eventEndsIn,
    remaining: remaining,
    urgent: remaining.inHours < 24,
  );
}

/// Formats [beacon] schedule for the card "when" line, harmonized with the
/// STATUS→YOU funnel: orientation (a factual date) at the top, urgency scoped so
/// it never competes with STATUS or fakes an "overdue" on a finished event.
BeaconSchedulePresentation? beaconSchedulePresentation({
  required Beacon beacon,
  required L10n l10n,
  DateTime? now,
}) {
  final clock = now ?? DateTime.now();
  final decision = _decide(beacon, clock);
  if (decision == null) return null;

  final localeName = l10n.localeName;
  final remainingText = formatCompactDurationRemaining(decision.remaining, l10n);

  String whenAbsolute() {
    final start = beacon.startAt;
    final end = beacon.endAt;
    if (start != null && end != null) {
      return formatScheduleRange(start, end, localeName: localeName, now: clock);
    }
    return formatScheduleDate(start ?? end!, localeName: localeName, now: clock);
  }

  String endDate() =>
      formatScheduleDate(beacon.endAt!, localeName: localeName, now: clock);

  switch (decision.mode) {
    case _ScheduleMode.eventUpcomingAbsolute:
      final when = whenAbsolute();
      return BeaconSchedulePresentation(
        visibleText: when,
        semanticsLabel: l10n.beaconCardScheduleScheduledFor(when),
        icon: Icons.event_outlined,
        urgent: false,
        phase: BeaconSchedulePhase.notStarted,
      );
    case _ScheduleMode.eventStartsIn:
      final text = l10n.beaconCardScheduleStartsIn(remainingText);
      return BeaconSchedulePresentation(
        visibleText: text,
        semanticsLabel: text,
        icon: Icons.event_outlined,
        urgent: decision.urgent,
        phase: BeaconSchedulePhase.notStarted,
      );
    case _ScheduleMode.eventUntil:
      final text = l10n.beaconCardScheduleUntil(endDate());
      return BeaconSchedulePresentation(
        visibleText: text,
        semanticsLabel: text,
        icon: Icons.timelapse,
        urgent: false,
        phase: BeaconSchedulePhase.inProgress,
      );
    case _ScheduleMode.eventEndsIn:
      final text = l10n.beaconCardScheduleEndsIn(remainingText);
      return BeaconSchedulePresentation(
        visibleText: text,
        semanticsLabel: text,
        icon: Icons.timelapse,
        urgent: decision.urgent,
        phase: BeaconSchedulePhase.inProgress,
      );
    case _ScheduleMode.eventNow:
      final text = l10n.beaconCardScheduleHappeningNow;
      return BeaconSchedulePresentation(
        visibleText: text,
        semanticsLabel: text,
        icon: Icons.timelapse,
        urgent: false,
        phase: BeaconSchedulePhase.inProgress,
      );
    case _ScheduleMode.eventEnded:
    case _ScheduleMode.handoffEnded:
      final when = whenAbsolute();
      return BeaconSchedulePresentation(
        visibleText: when,
        semanticsLabel: l10n.beaconCardScheduleEndedOn(when),
        icon: Icons.event_available_outlined,
        urgent: false,
        phase: BeaconSchedulePhase.finished,
      );
    case _ScheduleMode.deadlineBy:
      final text = l10n.beaconCardScheduleDeadlineBy(endDate());
      return BeaconSchedulePresentation(
        visibleText: text,
        semanticsLabel: text,
        icon: Icons.timer_outlined,
        urgent: false,
        phase: BeaconSchedulePhase.inProgress,
      );
    case _ScheduleMode.deadlineDueIn:
      final text = l10n.beaconCardScheduleDueIn(remainingText);
      return BeaconSchedulePresentation(
        visibleText: text,
        semanticsLabel: text,
        icon: Icons.timer_outlined,
        urgent: decision.urgent,
        phase: BeaconSchedulePhase.inProgress,
      );
    case _ScheduleMode.deadlineOverdue:
      final text = l10n.beaconCardScheduleOverdue;
      return BeaconSchedulePresentation(
        visibleText: text,
        semanticsLabel: text,
        icon: Icons.timer_outlined,
        urgent: true,
        phase: BeaconSchedulePhase.finished,
      );
  }
}

/// True only when the schedule line shows a live countdown (within the absolute
/// threshold, not handed off), so the card should run a 1-minute refresh timer.
bool beaconScheduleNeedsLiveTimer(Beacon beacon, {DateTime? now}) {
  final decision = _decide(beacon, now ?? DateTime.now());
  return decision?.mode.isCountdown ?? false;
}
