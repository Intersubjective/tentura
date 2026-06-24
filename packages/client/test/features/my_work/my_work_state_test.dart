import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_state.dart';

MyWorkCardViewModel _vm({
  required String id,
  required MyWorkCardRole role,
  required MyWorkCardKind kind,
  BeaconStatus status = BeaconStatus.open,
}) {
  final beacon = Beacon.empty.copyWith(
    id: id,
    updatedAt: DateTime(2025),
    status: status,
  );
  return MyWorkCardViewModel(
    beaconId: id,
    role: role,
    kind: kind,
    beacon: beacon,
  );
}

void main() {
  test('visibleCards All uses nonArchivedCards', () {
    final a = _vm(id: 'a', role: MyWorkCardRole.authored, kind: MyWorkCardKind.authoredActive);
    final c = _vm(id: 'b', role: MyWorkCardRole.helpOffered, kind: MyWorkCardKind.helpOfferedActive);
    final s = MyWorkState(nonArchivedCards: [a, c], filter: MyWorkFilter.all);
    expect(s.visibleCards.length, 2);
  });

  test('default filter is active', () {
    expect(const MyWorkState().filter, MyWorkFilter.active);
  });

  test('visibleCards Authored excludes drafts', () {
    final a = _vm(id: 'a', role: MyWorkCardRole.authored, kind: MyWorkCardKind.authoredActive);
    final d = _vm(
      id: 'd',
      role: MyWorkCardRole.authored,
      kind: MyWorkCardKind.authoredDraft,
      status: BeaconStatus.draft,
    );
    final s = MyWorkState(
      nonArchivedCards: [a, d],
      filter: MyWorkFilter.authored,
    );
    expect(s.visibleCards.map((e) => e.beaconId).toList(), ['a']);
  });

  test('visibleCards Committed excludes authored role', () {
    final a = _vm(id: 'a', role: MyWorkCardRole.authored, kind: MyWorkCardKind.authoredActive);
    final c = _vm(id: 'b', role: MyWorkCardRole.helpOffered, kind: MyWorkCardKind.helpOfferedActive);
    final s = MyWorkState(nonArchivedCards: [a, c], filter: MyWorkFilter.helpOffered);
    expect(s.visibleCards.map((e) => e.beaconId).toList(), ['b']);
  });

  test('visibleCards Archived uses archivedCards only', () {
    final x = _vm(
      id: 'x',
      role: MyWorkCardRole.authored,
      kind: MyWorkCardKind.authoredFinished,
      status: BeaconStatus.closed,
    );
    final s = MyWorkState(
      archivedCards: [x],
      filter: MyWorkFilter.archived,
    );
    expect(s.visibleCards, [x]);
  });

  test('archivedCountHint from init', () {
    const s = MyWorkState(archivedCountHint: 3);
    expect(s.archivedCountHint, 3);
  });
}
