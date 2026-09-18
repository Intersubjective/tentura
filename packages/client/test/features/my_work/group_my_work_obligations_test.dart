import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/features/my_work/domain/group_my_work_obligations.dart';

AttentionReceipt _receipt({
  required String id,
  String? presentationKey,
  String? actorUserId,
  String? targetEntityId,
}) => AttentionReceipt(
  id: id,
  category: 'coordination',
  kind: 'helpOfferSubmitted',
  priority: 'normal',
  title: 'Anna',
  body: 'Offered help',
  actionUrl: '/#/',
  createdAt: DateTime.utc(2026, 9, 1),
  collapsedCount: 1,
  presentationKey: presentationKey,
  presentationPayloadJson: '{}',
  surface: AttentionSurface.myWork,
  beaconId: 'b1',
  requiresAction: true,
  actorUserId: actorUserId,
  targetEntityId: targetEntityId,
);

void main() {
  test('groups help_offer_submitted by person and keeps all receipt ids', () {
    final groups = groupMyWorkObligations([
      _receipt(
        id: 'r1',
        presentationKey: 'help_offer_submitted',
        targetEntityId: 'u-a',
      ),
      _receipt(
        id: 'r2',
        presentationKey: 'help_offer_submitted',
        actorUserId: 'u-a',
      ),
      _receipt(
        id: 'r3',
        presentationKey: 'help_offer_submitted',
        targetEntityId: 'u-b',
      ),
    ]);

    expect(groups, hasLength(2));
    expect(groups[0].offererId, 'u-a');
    expect(groups[0].receiptIds, ['r1', 'r2']);
    expect(groups[1].offererId, 'u-b');
    expect(groups[1].receiptIds, ['r3']);
  });

  test('unknown and review stay one group per receipt', () {
    final groups = groupMyWorkObligations([
      _receipt(id: 'rev', presentationKey: 'review_opened'),
      _receipt(id: 'unk', presentationKey: 'something_new'),
    ]);

    expect(groups, hasLength(2));
    expect(groups[0].isReview, isTrue);
    expect(groups[0].receiptIds, ['rev']);
    expect(groups[1].receiptIds, ['unk']);
  });

  test('review-complete and reopen rows are not review obligations', () {
    final groups = groupMyWorkObligations([
      _receipt(id: 'all', presentationKey: 'review_all_packages_in'),
      _receipt(id: 'cxl', presentationKey: 'review_window_cancelled'),
    ]);

    expect(groups, hasLength(2));
    expect(groups.any((g) => g.isReview || g.isHelpOffer), isFalse);
  });
}
