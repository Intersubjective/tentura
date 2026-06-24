import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

void main() {
  test('reviewOpen is active section', () {
    expect(BeaconStatus.reviewOpen.isActiveSection, isTrue);
    expect(BeaconStatus.reviewOpen.isClosedSection, isFalse);
    expect(BeaconStatus.reviewOpen.isReviewWindowOpen, isTrue);
    expect(BeaconStatus.reviewOpen.isWrappingUp, isTrue);
  });

  test('closed and cancelled are finished', () {
    expect(BeaconStatus.closed.isFinished, isTrue);
    expect(BeaconStatus.cancelled.isFinished, isTrue);
    expect(BeaconStatus.closed.isActiveSection, isFalse);
    expect(BeaconStatus.cancelled.isActiveSection, isFalse);
  });

  test('fromSmallint maps persisted status values', () {
    expect(BeaconStatus.fromSmallint(0), BeaconStatus.open);
    expect(BeaconStatus.fromSmallint(1), BeaconStatus.cancelled);
    expect(BeaconStatus.fromSmallint(2), BeaconStatus.deleted);
    expect(BeaconStatus.fromSmallint(3), BeaconStatus.draft);
    expect(BeaconStatus.fromSmallint(4), BeaconStatus.closed);
    expect(BeaconStatus.fromSmallint(5), BeaconStatus.reviewOpen);
    expect(BeaconStatus.fromSmallint(6), BeaconStatus.closed);
    expect(BeaconStatus.fromSmallint(7), BeaconStatus.needsMoreHelp);
    expect(BeaconStatus.fromSmallint(8), BeaconStatus.enoughHelp);
  });

  test('My Work tab helpers', () {
    expect(BeaconStatus.reviewOpen.isMyWorkReviewTab, isTrue);
    expect(BeaconStatus.open.isMyWorkActiveTab, isTrue);
    expect(BeaconStatus.draft.isMyWorkDraftsTab, isTrue);
    expect(BeaconStatus.closed.isMyWorkDraftsTab, isFalse);
    expect(BeaconStatus.closed.isMyWorkActiveTab, isFalse);
    expect(BeaconStatus.closed.isMyWorkReviewTab, isFalse);
  });

  test('forward only while open-family', () {
    expect(BeaconStatus.open.allowsForward, isTrue);
    expect(BeaconStatus.needsMoreHelp.allowsForward, isTrue);
    expect(BeaconStatus.reviewOpen.allowsForward, isFalse);
    expect(BeaconStatus.closed.allowsForward, isFalse);
  });
}
