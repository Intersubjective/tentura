import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura/domain/coordination/derive_beacon_coordination_phase.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/presenter/beacon_phase_input_builders.dart';
import 'package:tentura/ui/presenter/beacon_phase_presenter.dart';

/// Phase STATUS + optional room subtitle for My Work card headers.
final class MyWorkStatusLineData {
  const MyWorkStatusLineData({
    required this.phaseStatus,
    required this.timeSlotOverdue,
    this.slot1ResponseType,
    this.slot1CoordinationStatus,
  });

  final BeaconPhaseStatusPresentation phaseStatus;
  final CoordinationResponseType? slot1ResponseType;
  final BeaconStatus? slot1CoordinationStatus;
  final bool timeSlotOverdue;

  bool get isEmpty => phaseStatus.statusLine.trim().isEmpty;

  String get slot1 => phaseStatus.slot1;
  String get slot2 => phaseStatus.slot2 ?? '';
  TenturaTone get tone => phaseStatus.slot1Tone;
}

/// Header STATUS with optional room subtitle merged into slot2.
BeaconPhaseStatusPresentation myWorkHeaderPhaseStatus(
  MyWorkStatusLineData data, {
  String? roomSubtitle,
}) {
  var s2 = data.phaseStatus.slot2?.trim() ?? '';
  final room = roomSubtitle?.trim() ?? '';
  if (room.isNotEmpty) {
    s2 = s2.isEmpty ? room : '$s2 · $room';
  }
  if (s2.isEmpty) return data.phaseStatus;
  return BeaconPhaseStatusPresentation(
    slot1: data.phaseStatus.slot1,
    slot2: s2,
    slot1Tone: data.phaseStatus.slot1Tone,
    slot2Tone: data.phaseStatus.slot2Tone,
  );
}

/// Assembles `slot1 [· slot2]` for compact header / app bar subtitles.
String myWorkStatusDisplayLine(
  MyWorkStatusLineData data, {
  String? roomSubtitle,
}) => myWorkHeaderPhaseStatus(data, roomSubtitle: roomSubtitle).statusLine;

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
    phaseStatus: pres,
    timeSlotOverdue: false,
  );
}
