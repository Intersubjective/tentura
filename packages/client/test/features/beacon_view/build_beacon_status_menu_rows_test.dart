import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/domain/entity/coordination_status.dart';
import 'package:tentura/features/beacon_view/domain/beacon_status_menu.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_closure_readiness.dart';

final _t = DateTime.utc(2026, 6, 20, 12);

Beacon _beacon({
  BeaconLifecycle lifecycle = BeaconLifecycle.open,
  BeaconCoordinationStatus coordinationStatus = BeaconCoordinationStatus.neutral,
  int helpOfferCount = 0,
}) =>
    Beacon.empty.copyWith(
      id: 'b1',
      title: 'Test',
      lifecycle: lifecycle,
      coordinationStatus: coordinationStatus,
      helpOfferCount: helpOfferCount,
      createdAt: _t,
      updatedAt: _t,
    );

BeaconStatusMenuInput _input({
  Beacon? beacon,
  BeaconClosureReadiness readiness = BeaconClosureReadiness.readyToClose,
  bool hasCommitters = false,
  bool canManageLifecycle = true,
  bool canSetCoordination = true,
  ReviewWindowMenuSnapshot? reviewWindow,
}) =>
    BeaconStatusMenuInput(
      beacon: beacon ?? _beacon(),
      closureReadiness: readiness,
      hasCommitters: hasCommitters,
      canManageLifecycle: canManageLifecycle,
      canSetCoordination: canSetCoordination,
      reviewWindow: reviewWindow,
    );

BeaconStatusMenuRow _row(
  List<BeaconStatusMenuRow> rows,
  BeaconStatusMenuRowId id,
) =>
    rows.firstWhere((r) => r.id == id);

void main() {
  test('draft publish row enabled for author', () {
    final rows = buildBeaconStatusMenuRows(
      _input(beacon: _beacon(lifecycle: BeaconLifecycle.draft)),
    );
    final open = _row(rows, BeaconStatusMenuRowId.open);
    expect(open.isEnabled, isTrue);
    expect(open.action, BeaconStatusMenuAction.publish);
  });

  test('open with no committers enables direct close', () {
    final rows = buildBeaconStatusMenuRows(_input(hasCommitters: false));
    final closed = _row(rows, BeaconStatusMenuRowId.closed);
    expect(closed.isEnabled, isTrue);
    expect(closed.action, BeaconStatusMenuAction.closeDirect);
    final wrapping = _row(rows, BeaconStatusMenuRowId.wrappingUp);
    expect(wrapping.isEnabled, isFalse);
    expect(wrapping.disabledReason, BeaconStatusMenuDisabledReason.noCommitters);
  });

  test('open with committers enables wrapping up not direct close', () {
    final rows = buildBeaconStatusMenuRows(
      _input(hasCommitters: true),
    );
    expect(
      _row(rows, BeaconStatusMenuRowId.wrappingUp).isEnabled,
      isTrue,
    );
    expect(
      _row(rows, BeaconStatusMenuRowId.closed).disabledReason,
      BeaconStatusMenuDisabledReason.finishReviewFirst,
    );
  });

  test('open with blockers disables close paths', () {
    final rows = buildBeaconStatusMenuRows(
      _input(
        hasCommitters: true,
        readiness: BeaconClosureReadiness.blocked,
      ),
    );
    expect(_row(rows, BeaconStatusMenuRowId.wrappingUp).isEnabled, isFalse);
    expect(
      _row(rows, BeaconStatusMenuRowId.wrappingUp).disabledReason,
      BeaconStatusMenuDisabledReason.blocked,
    );
  });

  test('review open with incomplete reviewers disables close now', () {
    final rows = buildBeaconStatusMenuRows(
      _input(
        beacon: _beacon(lifecycle: BeaconLifecycle.reviewOpen),
        reviewWindow: const ReviewWindowMenuSnapshot(
          reviewedCount: 1,
          totalCount: 3,
          windowComplete: false,
          extensionsUsed: 0,
        ),
      ),
    );
    expect(_row(rows, BeaconStatusMenuRowId.closed).isEnabled, isFalse);
    expect(
      _row(rows, BeaconStatusMenuRowId.closed).disabledReason,
      BeaconStatusMenuDisabledReason.waitingForReviewers,
    );
  });

  test('review open with all reviewers done enables close now', () {
    final rows = buildBeaconStatusMenuRows(
      _input(
        beacon: _beacon(lifecycle: BeaconLifecycle.reviewOpen),
        reviewWindow: const ReviewWindowMenuSnapshot(
          reviewedCount: 3,
          totalCount: 3,
          windowComplete: false,
          extensionsUsed: 0,
        ),
      ),
    );
    expect(_row(rows, BeaconStatusMenuRowId.closed).isEnabled, isTrue);
    expect(_row(rows, BeaconStatusMenuRowId.closed).action, BeaconStatusMenuAction.closeNow);
  });

  test('closed terminal disables all rows', () {
    final rows = buildBeaconStatusMenuRows(
      _input(beacon: _beacon(lifecycle: BeaconLifecycle.closed)),
    );
    expect(_row(rows, BeaconStatusMenuRowId.closed).isSelected, isTrue);
    expect(rows.every((r) => !r.isEnabled), isTrue);
  });

  test('cancel disabled when help offers exist', () {
    final rows = buildBeaconStatusMenuRows(
      _input(beacon: _beacon(helpOfferCount: 2)),
    );
    expect(_row(rows, BeaconStatusMenuRowId.cancelled).isEnabled, isFalse);
    expect(
      _row(rows, BeaconStatusMenuRowId.cancelled).disabledReason,
      BeaconStatusMenuDisabledReason.cancelHasOffers,
    );
  });
}
