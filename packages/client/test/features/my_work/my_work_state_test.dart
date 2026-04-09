import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_state.dart';

MyWorkCardViewModel _vm({
  required String id,
  required MyWorkCardRole role,
  required MyWorkCardKind kind,
  BeaconLifecycle lifecycle = BeaconLifecycle.open,
}) {
  final beacon = Beacon.empty.copyWith(
    id: id,
    updatedAt: DateTime(2025, 1, 1),
    lifecycle: lifecycle,
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
    final c = _vm(id: 'b', role: MyWorkCardRole.committed, kind: MyWorkCardKind.committedActive);
    final s = MyWorkState(nonArchivedCards: [a, c], filter: MyWorkFilter.all);
    expect(s.visibleCards.length, 2);
  });

  test('visibleCards Authored excludes committed role', () {
    final a = _vm(id: 'a', role: MyWorkCardRole.authored, kind: MyWorkCardKind.authoredActive);
    final c = _vm(id: 'b', role: MyWorkCardRole.committed, kind: MyWorkCardKind.committedActive);
    final s = MyWorkState(nonArchivedCards: [a, c], filter: MyWorkFilter.authored);
    expect(s.visibleCards.map((e) => e.beaconId).toList(), ['a']);
  });

  test('visibleCards Committed excludes authored role', () {
    final a = _vm(id: 'a', role: MyWorkCardRole.authored, kind: MyWorkCardKind.authoredActive);
    final c = _vm(id: 'b', role: MyWorkCardRole.committed, kind: MyWorkCardKind.committedActive);
    final s = MyWorkState(nonArchivedCards: [a, c], filter: MyWorkFilter.committed);
    expect(s.visibleCards.map((e) => e.beaconId).toList(), ['b']);
  });

  test('visibleCards Archived uses archivedCards only', () {
    final x = _vm(
      id: 'x',
      role: MyWorkCardRole.authored,
      kind: MyWorkCardKind.authoredClosed,
      lifecycle: BeaconLifecycle.closed,
    );
    final s = MyWorkState(
      nonArchivedCards: const [],
      archivedCards: [x],
      filter: MyWorkFilter.archived,
    );
    expect(s.visibleCards, [x]);
  });

  test('archivedCountHint dedupes shared ids', () {
    const s = MyWorkState(
      authoredClosedIdHints: ['a', 'b'],
      committedClosedIdHints: ['b', 'c'],
    );
    expect(s.archivedCountHint, 3);
  });
}
