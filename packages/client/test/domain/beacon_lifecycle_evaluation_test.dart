import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon_lifecycle.dart';

void main() {
  test('reviewOpen is active section', () {
    expect(BeaconLifecycle.reviewOpen.isActiveSection, isTrue);
    expect(BeaconLifecycle.reviewOpen.isClosedSection, isFalse);
    expect(BeaconLifecycle.reviewOpen.isReviewWindowOpen, isTrue);
    expect(BeaconLifecycle.reviewOpen.isWrappingUp, isTrue);
  });

  test('closed and cancelled are finished', () {
    expect(BeaconLifecycle.closed.isFinished, isTrue);
    expect(BeaconLifecycle.cancelled.isFinished, isTrue);
    expect(BeaconLifecycle.closed.isActiveSection, isFalse);
    expect(BeaconLifecycle.cancelled.isActiveSection, isFalse);
  });

  test('fromSmallint maps lifecycle redesign states', () {
    expect(BeaconLifecycle.fromSmallint(0), BeaconLifecycle.open);
    expect(BeaconLifecycle.fromSmallint(1), BeaconLifecycle.cancelled);
    expect(BeaconLifecycle.fromSmallint(2), BeaconLifecycle.deleted);
    expect(BeaconLifecycle.fromSmallint(3), BeaconLifecycle.draft);
    expect(BeaconLifecycle.fromSmallint(4), BeaconLifecycle.closed);
    expect(BeaconLifecycle.fromSmallint(5), BeaconLifecycle.reviewOpen);
    expect(BeaconLifecycle.fromSmallint(6), BeaconLifecycle.closed);
  });

  test('My Work tab helpers', () {
    expect(BeaconLifecycle.reviewOpen.isMyWorkReviewTab, isTrue);
    expect(BeaconLifecycle.open.isMyWorkActiveTab, isTrue);
    expect(BeaconLifecycle.draft.isMyWorkDraftsTab, isTrue);
    expect(BeaconLifecycle.closed.isMyWorkDraftsTab, isFalse);
    expect(BeaconLifecycle.closed.isMyWorkActiveTab, isFalse);
    expect(BeaconLifecycle.closed.isMyWorkReviewTab, isFalse);
  });

  test('forward only while open', () {
    expect(BeaconLifecycle.open.allowsForward, isTrue);
    expect(BeaconLifecycle.reviewOpen.allowsForward, isFalse);
    expect(BeaconLifecycle.closed.allowsForward, isFalse);
  });
}
