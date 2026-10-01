import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/features/closure/domain/entity/closure_role.dart';
import 'package:tentura/features/closure/domain/entity/closure_state.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';

import 'my_work_test_support.dart';

Beacon _beacon(String id, {BeaconStatus status = BeaconStatus.reviewOpen}) =>
    Beacon.empty.copyWith(
      id: id,
      author: const Profile(id: 'Ua'),
      status: status,
    );

MyWorkCardViewModel _authoredCard(
  String id, {
  BeaconStatus status = BeaconStatus.reviewOpen,
}) =>
    MyWorkCardViewModel(
      beaconId: id,
      role: MyWorkCardRole.authored,
      kind: MyWorkCardKind.authoredActive,
      beacon: _beacon(id, status: status),
    );

ClosureState _closure({required bool canCloseNow}) => ClosureState(
  epoch: 1,
  status: BeaconStatus.reviewOpen.smallintValue,
  role: ClosureRole.author,
  members: const [],
  closesAt: DateTime.utc(2026, 6, 27),
  canCloseNow: canCloseNow,
);

void main() {
  test('loadClosureStates reads only authored wrapping-up cards', () async {
    final closure = FakeMyWorkClosureRepository();
    final case_ = buildTestMyWorkCase(closureRepo: closure);
    final cards = [
      _authoredCard('B1', status: BeaconStatus.open),
      MyWorkCardViewModel(
        beaconId: 'B2',
        role: MyWorkCardRole.helpOffered,
        kind: MyWorkCardKind.helpOfferedActive,
        beacon: _beacon('B2', status: BeaconStatus.reviewOpen),
      ),
    ];

    final out = await case_.loadClosureStates(cards);

    expect(closure.fetchedIds, isEmpty);
    expect(out.every((c) => !c.showCloseNowCta), isTrue);
  });

  test('showCloseNowCta only for authored reviewOpen with canCloseNow', () async {
    final closure = FakeMyWorkClosureRepository()
      ..statesByBeacon['B1'] = _closure(canCloseNow: true)
      ..statesByBeacon['B2'] = _closure(canCloseNow: false);
    final case_ = buildTestMyWorkCase(closureRepo: closure);
    final cards = [
      _authoredCard('B1'),
      _authoredCard('B2'),
    ];

    final out = await case_.loadClosureStates(cards);

    expect(closure.fetchedIds, unorderedEquals(['B1', 'B2']));
    expect(out.firstWhere((c) => c.beaconId == 'B1').showCloseNowCta, isTrue);
    expect(out.firstWhere((c) => c.beaconId == 'B2').showCloseNowCta, isFalse);
  });

  test('a card whose closure state cannot be read stays unchanged', () async {
    final closure = FakeMyWorkClosureRepository()
      ..statesByBeacon['B1'] = _closure(canCloseNow: true);
    final case_ = buildTestMyWorkCase(closureRepo: closure);
    final cards = [_authoredCard('B1'), _authoredCard('B2')];

    final out = await case_.loadClosureStates(cards);

    expect(out.firstWhere((c) => c.beaconId == 'B1').showCloseNowCta, isTrue);
    expect(out.firstWhere((c) => c.beaconId == 'B2').showCloseNowCta, isFalse);
  });
}
