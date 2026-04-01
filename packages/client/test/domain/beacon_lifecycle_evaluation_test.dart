import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon_lifecycle.dart';

void main() {
  test('closedReviewOpen is active section', () {
    expect(BeaconLifecycle.closedReviewOpen.isActiveSection, isTrue);
    expect(BeaconLifecycle.closedReviewOpen.isClosedSection, isFalse);
    expect(BeaconLifecycle.closedReviewOpen.isReviewWindowOpen, isTrue);
  });

  test('closedReviewComplete is closed section', () {
    expect(BeaconLifecycle.closedReviewComplete.isClosedSection, isTrue);
    expect(BeaconLifecycle.closedReviewComplete.isActiveSection, isFalse);
  });

  test('fromSmallint', () {
    expect(BeaconLifecycle.fromSmallint(5), BeaconLifecycle.closedReviewOpen);
    expect(BeaconLifecycle.fromSmallint(6), BeaconLifecycle.closedReviewComplete);
  });
}
