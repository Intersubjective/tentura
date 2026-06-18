import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_schedule.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/duration_format.dart';
import 'package:tentura/ui/utils/relative_time.dart';

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

/// Formats [beacon] schedule phase for My Work card metadata (no phase derivation).
BeaconSchedulePresentation? beaconSchedulePresentation({
  required Beacon beacon,
  required L10n l10n,
  DateTime? now,
}) {
  final phase = beacon.schedulePhase(now: now);
  if (phase == BeaconSchedulePhase.none) {
    return null;
  }

  final clock = now ?? DateTime.now();
  final reference = beacon.scheduleReferenceAt(now: clock);

  return switch (phase) {
    BeaconSchedulePhase.notStarted => _countdownPresentation(
      l10n: l10n,
      phase: phase,
      reference: reference!,
      now: clock,
      icon: Icons.schedule_outlined,
      semanticsBuilder: l10n.beaconCardScheduleStartsIn,
    ),
    BeaconSchedulePhase.inProgress => _inProgressPresentation(
      l10n: l10n,
      reference: reference,
      now: clock,
    ),
    BeaconSchedulePhase.finished => _finishedPresentation(
      l10n: l10n,
      reference: reference!,
      now: clock,
    ),
    BeaconSchedulePhase.none => null,
  };
}

BeaconSchedulePresentation _countdownPresentation({
  required L10n l10n,
  required BeaconSchedulePhase phase,
  required DateTime reference,
  required DateTime now,
  required IconData icon,
  required String Function(String remaining) semanticsBuilder,
}) {
  final remaining = reference.difference(now);
  final visible = formatCompactDurationRemaining(remaining, l10n);
  return BeaconSchedulePresentation(
    visibleText: visible,
    semanticsLabel: semanticsBuilder(visible),
    icon: icon,
    urgent: remaining.inHours < 24,
    phase: phase,
  );
}

BeaconSchedulePresentation _inProgressPresentation({
  required L10n l10n,
  required DateTime? reference,
  required DateTime now,
}) {
  if (reference == null) {
    return BeaconSchedulePresentation(
      visibleText: '',
      semanticsLabel: l10n.beaconCardScheduleInProgress,
      icon: Icons.timelapse,
      urgent: false,
      phase: BeaconSchedulePhase.inProgress,
    );
  }
  return _countdownPresentation(
    l10n: l10n,
    phase: BeaconSchedulePhase.inProgress,
    reference: reference,
    now: now,
    icon: Icons.timelapse,
    semanticsBuilder: l10n.beaconCardScheduleEndsIn,
  );
}

BeaconSchedulePresentation _finishedPresentation({
  required L10n l10n,
  required DateTime reference,
  required DateTime now,
}) {
  final ago = compactRelativeTimeAgo(when: reference, now: now, l10n: l10n);
  return BeaconSchedulePresentation(
    visibleText: ago,
    semanticsLabel: l10n.beaconCardScheduleEndedAgo(ago),
    icon: Icons.event_available_outlined,
    urgent: false,
    phase: BeaconSchedulePhase.finished,
  );
}

bool beaconScheduleNeedsLiveTimer(BeaconSchedulePhase phase) =>
    phase == BeaconSchedulePhase.notStarted ||
    phase == BeaconSchedulePhase.inProgress;
