import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/features/beacon_view/domain/beacon_status_menu.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_closure_readiness.dart';

final _t = DateTime.utc(2026, 6, 20, 12);

Beacon _beacon({
  BeaconStatus status = BeaconStatus.open,
  int helpOfferCount = 0,
}) =>
    Beacon.empty.copyWith(
      id: 'b1',
      title: 'Test',
      status: status,
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
  ClosureMenuSnapshot? closure,
  bool? serverCanCancel,
}) =>
    BeaconStatusMenuInput(
      beacon: beacon ?? _beacon(),
      closureReadiness: readiness,
      hasCommitters: hasCommitters,
      canManageLifecycle: canManageLifecycle,
      canSetCoordination: canSetCoordination,
      closure: closure,
      serverCanCancel: serverCanCancel,
    );

BeaconStatusMenuRow _row(
  List<BeaconStatusMenuRow> rows,
  BeaconStatusMenuRowId id,
) =>
    rows.firstWhere((r) => r.id == id);

void main() {
  test('draft publish row enabled for author', () {
    final rows = buildBeaconStatusMenuRows(
      _input(beacon: _beacon(status: BeaconStatus.draft)),
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

  test('review open before the closure allows it disables close now', () {
    final rows = buildBeaconStatusMenuRows(
      _input(
        beacon: _beacon(status: BeaconStatus.reviewOpen),
        closure: const ClosureMenuSnapshot(
          extensionsUsed: 0,
          canCloseNow: false,
        ),
      ),
    );
    expect(_row(rows, BeaconStatusMenuRowId.closed).isEnabled, isFalse);
    expect(
      _row(rows, BeaconStatusMenuRowId.closed).disabledReason,
      BeaconStatusMenuDisabledReason.waitingForReviewers,
    );
  });

  test('review open once the closure allows it enables close now', () {
    final rows = buildBeaconStatusMenuRows(
      _input(
        beacon: _beacon(status: BeaconStatus.reviewOpen),
        closure: const ClosureMenuSnapshot(
          extensionsUsed: 0,
          canCloseNow: true,
        ),
      ),
    );
    expect(_row(rows, BeaconStatusMenuRowId.closed).isEnabled, isTrue);
    expect(_row(rows, BeaconStatusMenuRowId.closed).action, BeaconStatusMenuAction.closeNow);
  });

  test('review open more help row enabled for author or steward', () {
    final rows = buildBeaconStatusMenuRows(
      _input(
        beacon: _beacon(status: BeaconStatus.reviewOpen),
        canSetCoordination: true,
      ),
    );
    final moreHelp = _row(rows, BeaconStatusMenuRowId.moreHelp);
    expect(moreHelp.isEnabled, isTrue);
    expect(moreHelp.action, BeaconStatusMenuAction.setCoordinationMoreHelp);
  });

  test('review open disables enough help row', () {
    final rows = buildBeaconStatusMenuRows(
      _input(
        beacon: _beacon(status: BeaconStatus.reviewOpen),
        canSetCoordination: true,
      ),
    );
    final enough = _row(rows, BeaconStatusMenuRowId.enoughHelp);
    expect(enough.isEnabled, isFalse);
    expect(enough.disabledReason, BeaconStatusMenuDisabledReason.finishReviewFirst);
  });

  test('review open disables reopen when cap exhausted', () {
    final rows = buildBeaconStatusMenuRows(
      _input(
        beacon: _beacon(status: BeaconStatus.reviewOpen),
        canManageLifecycle: true,
        closure: const ClosureMenuSnapshot(
          extensionsUsed: 0,
          canReopen: false,
        ),
      ),
    );
    final open = _row(rows, BeaconStatusMenuRowId.open);
    expect(open.action, BeaconStatusMenuAction.reopen);
    expect(open.isEnabled, isFalse);
    expect(open.disabledReason, BeaconStatusMenuDisabledReason.reopenLimitReached);
  });

  test('closed terminal disables all rows', () {
    final rows = buildBeaconStatusMenuRows(
      _input(beacon: _beacon(status: BeaconStatus.closed)),
    );
    expect(_row(rows, BeaconStatusMenuRowId.closed).isSelected, isTrue);
    expect(rows.every((r) => !r.isEnabled), isTrue);
  });

  test('cancel disabled when acknowledged committers exist', () {
    final rows = buildBeaconStatusMenuRows(
      _input(beacon: _beacon(helpOfferCount: 2), hasCommitters: true),
    );
    expect(_row(rows, BeaconStatusMenuRowId.cancelled).isEnabled, isFalse);
    expect(
      _row(rows, BeaconStatusMenuRowId.cancelled).disabledReason,
      BeaconStatusMenuDisabledReason.cancelHasOffers,
    );
  });

  test('cancel disabled with server canCancel false uses committer reason', () {
    final rows = buildBeaconStatusMenuRows(
      _input(
        beacon: _beacon(helpOfferCount: 2),
        serverCanCancel: false,
      ),
    );
    expect(_row(rows, BeaconStatusMenuRowId.cancelled).isEnabled, isFalse);
    expect(
      _row(rows, BeaconStatusMenuRowId.cancelled).disabledReason,
      BeaconStatusMenuDisabledReason.cancelHasCommitters,
    );
  });

  test('cancel enabled when server canCancel true despite heuristic block', () {
    final rows = buildBeaconStatusMenuRows(
      _input(
        beacon: _beacon(helpOfferCount: 2),
        hasCommitters: true,
        serverCanCancel: true,
      ),
    );
    expect(_row(rows, BeaconStatusMenuRowId.cancelled).isEnabled, isTrue);
  });

  group('B041: wrapping up again after a Reopen is never a dead end', () {
    // Second round: the one Reopen is spent, nobody has reviewed yet.
    final afterReopen = _input(
      beacon: _beacon(status: BeaconStatus.reviewOpen),
      hasCommitters: true,
      closure: const ClosureMenuSnapshot(
        extensionsUsed: 0,
        canCloseNow: false,
        canReopen: false,
      ),
    );

    test('the current "Wrapping up" step opens the review for the author', () {
      final wrapping = _row(
        buildBeaconStatusMenuRows(afterReopen),
        BeaconStatusMenuRowId.wrappingUp,
      );
      expect(wrapping.isSelected, isTrue);
      expect(wrapping.isEnabled, isTrue);
      expect(wrapping.action, BeaconStatusMenuAction.openReview);
    });

    test('not for someone who cannot manage the lifecycle', () {
      final wrapping = _row(
        buildBeaconStatusMenuRows(
          _input(
            beacon: _beacon(status: BeaconStatus.reviewOpen),
            canManageLifecycle: false,
            closure: const ClosureMenuSnapshot(extensionsUsed: 0),
          ),
        ),
        BeaconStatusMenuRowId.wrappingUp,
      );
      expect(wrapping.isEnabled, isFalse);
    });

    test('nor before the closure snapshot has loaded', () {
      final wrapping = _row(
        buildBeaconStatusMenuRows(
          _input(beacon: _beacon(status: BeaconStatus.reviewOpen)),
        ),
        BeaconStatusMenuRowId.wrappingUp,
      );
      expect(wrapping.isEnabled, isFalse);
    });

    test('"More help" no longer offers a reopen the server will refuse', () {
      final moreHelp = _row(
        buildBeaconStatusMenuRows(afterReopen),
        BeaconStatusMenuRowId.moreHelp,
      );
      expect(moreHelp.isEnabled, isFalse);
      expect(
        moreHelp.disabledReason,
        BeaconStatusMenuDisabledReason.reopenLimitReached,
      );
    });

    test('first round: "More help" still reopens', () {
      final moreHelp = _row(
        buildBeaconStatusMenuRows(
          _input(
            beacon: _beacon(status: BeaconStatus.reviewOpen),
            closure: const ClosureMenuSnapshot(
              extensionsUsed: 0,
              canReopen: true,
            ),
          ),
        ),
        BeaconStatusMenuRowId.moreHelp,
      );
      expect(moreHelp.isEnabled, isTrue);
    });

    test('once the review allows it, Close now is enabled again', () {
      final rows = buildBeaconStatusMenuRows(
        _input(
          beacon: _beacon(status: BeaconStatus.reviewOpen),
          hasCommitters: true,
          closure: const ClosureMenuSnapshot(
            extensionsUsed: 0,
            canCloseNow: true,
            canReopen: false,
          ),
        ),
      );
      final closed = _row(rows, BeaconStatusMenuRowId.closed);
      expect(closed.isEnabled, isTrue);
      expect(closed.action, BeaconStatusMenuAction.closeNow);
    });
  });
}
