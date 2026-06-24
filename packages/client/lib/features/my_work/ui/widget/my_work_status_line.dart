import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura/domain/coordination/derive_beacon_coordination_phase.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/presenter/beacon_phase_input_builders.dart';
import 'package:tentura/ui/presenter/beacon_phase_presenter.dart';

/// Two semantic slots for the My Work status row (`slot1 [· slot2]`).
final class MyWorkStatusLineData {
  const MyWorkStatusLineData({
    required this.slot1,
    required this.slot2,
    required this.timeSlotOverdue,
    this.slot1ResponseType,
    this.slot1CoordinationStatus,
    this.tone = TenturaTone.neutral,
  });

  final String slot1;
  final String slot2;

  final CoordinationResponseType? slot1ResponseType;
  final BeaconStatus? slot1CoordinationStatus;
  final bool timeSlotOverdue;
  final TenturaTone tone;

  bool get isEmpty => slot1.trim().isEmpty && slot2.trim().isEmpty;
}

/// Assembles `slot1 [· slot2]` for compact header / app bar subtitles.
String myWorkStatusDisplayLine(
  MyWorkStatusLineData data, {
  String? roomSubtitle,
}) {
  var slot2 = data.slot2.trim();
  if (slot2.isEmpty) {
    slot2 = roomSubtitle?.trim() ?? '';
  }
  final slot1 = data.slot1.trim();
  if (slot1.isEmpty && slot2.isEmpty) return '';
  if (slot1.isEmpty) return slot2;
  if (slot2.isEmpty) return slot1;
  return '$slot1 · $slot2';
}

TenturaTone myWorkStatusTone(MyWorkStatusLineData data) => data.tone;

/// Derives shared phase status for My Work card headers.
MyWorkStatusLineData myWorkStatusLine({
  required L10n l10n,
  required MyWorkCardViewModel vm,
  DateTime? now,
}) {
  final clock = now ?? DateTime.now();
  final input = beaconPhaseInputFromMyWorkCard(vm, now: clock);
  final result = deriveBeaconCoordinationPhase(input);
  final pres = formatBeaconPhaseStatus(l10n, result, now: clock);

  return MyWorkStatusLineData(
    slot1: pres.statusLine,
    slot2: '',
    timeSlotOverdue: false,
    tone: pres.tone,
  );
}
