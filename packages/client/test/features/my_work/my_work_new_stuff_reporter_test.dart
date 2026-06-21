import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/features/my_work/domain/derive_my_work_cards.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';

MyWorkCardViewModel _vm(String id, int updatedMs) {
  return MyWorkCardViewModel(
    beaconId: id,
    role: MyWorkCardRole.authored,
    kind: MyWorkCardKind.authoredActive,
    beacon: Beacon.empty.copyWith(
      id: id,
      createdAt: DateTime.fromMillisecondsSinceEpoch(100),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedMs),
    ),
  );
}

void main() {
  test('maxMyWorkDeskActivityEpochMs used by NewStuff reporter path', () {
    final max = maxMyWorkDeskActivityEpochMs(
      nonArchivedCards: [_vm('a', 400)],
      archivedCards: [_vm('b', 900)],
    );
    expect(max, 900);
  });
}
