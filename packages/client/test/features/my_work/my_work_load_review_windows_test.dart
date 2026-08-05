import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/features/evaluation/domain/entity/review_window_info.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';

import '../evaluation/evaluation_case_test.dart' show FakeEvaluationRepository;
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

void main() {
  test('loadReviewWindows skips query when no reviewOpen authored cards', () async {
    final eval = FakeEvaluationRepository();
    final case_ = buildTestMyWorkCase(evaluationRepo: eval);
    final cards = [
      _authoredCard('B1', status: BeaconStatus.open),
      MyWorkCardViewModel(
        beaconId: 'B2',
        role: MyWorkCardRole.helpOffered,
        kind: MyWorkCardKind.helpOfferedActive,
        beacon: _beacon('B2', status: BeaconStatus.reviewOpen),
      ),
    ];

    final out = await case_.loadReviewWindows(cards, userId: 'Ua');

    expect(eval.lastReviewWindowStatusesIds, isNull);
    expect(out.every((c) => !c.showCloseNowCta), isTrue);
  });

  test('showCloseNowCta only for authored reviewOpen with canCloseNow', () async {
    final eval = FakeEvaluationRepository()
      ..reviewWindowStatusesResult = [
        const ReviewWindowInfo(
          beaconId: 'B1',
          hasWindow: true,
          canCloseNow: true,
        ),
        const ReviewWindowInfo(
          beaconId: 'B2',
          hasWindow: true,
          canCloseNow: false,
        ),
      ];
    final case_ = buildTestMyWorkCase(evaluationRepo: eval);
    final cards = [
      _authoredCard('B1'),
      _authoredCard('B2'),
    ];

    final out = await case_.loadReviewWindows(cards, userId: 'Ua');

    expect(eval.lastReviewWindowStatusesIds, ['B1', 'B2']);
    expect(out.firstWhere((c) => c.beaconId == 'B1').showCloseNowCta, isTrue);
    expect(out.firstWhere((c) => c.beaconId == 'B2').showCloseNowCta, isFalse);
  });
}
