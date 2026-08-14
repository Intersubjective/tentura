import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_cards.dart';

MyWorkCardViewModel _vm({
  required BeaconStatus status,
  bool authorHasForwardedOnce = false,
}) {
  return MyWorkCardViewModel(
    beaconId: 'b1',
    role: MyWorkCardRole.authored,
    kind: MyWorkCardKind.authoredActive,
    beacon: Beacon.empty.copyWith(
      id: 'b1',
      status: status,
      author: const Profile(id: 'auth', displayName: 'Author'),
    ),
    authorHasForwardedOnce: authorHasForwardedOnce,
  );
}

void main() {
  group('myWorkNeedsForwardCta', () {
    test('true when author has not forwarded and beacon allows forward', () {
      expect(
        myWorkNeedsForwardCta(_vm(status: BeaconStatus.open)),
        isTrue,
      );
    });

    test('false when author already forwarded once', () {
      expect(
        myWorkNeedsForwardCta(
          _vm(status: BeaconStatus.open, authorHasForwardedOnce: true),
        ),
        isFalse,
      );
    });

    test('false when beacon does not allow forward', () {
      expect(
        myWorkNeedsForwardCta(_vm(status: BeaconStatus.reviewOpen)),
        isFalse,
      );
    });
  });
}
