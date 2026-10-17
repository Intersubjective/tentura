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
  bool closureBlockedOnlyByNeedsMoreHelp = false,
}) =>
    BeaconStatusMenuInput(
      beacon: beacon ?? _beacon(),
      closureReadiness: readiness,
      hasCommitters: hasCommitters,
      canManageLifecycle: canManageLifecycle,
      canSetCoordination: canSetCoordination,
      closure: closure,
      serverCanCancel: serverCanCancel,
      closureBlockedOnlyByNeedsMoreHelp: closureBlockedOnlyByNeedsMoreHelp,
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

  // #384: "Enough help" could be set on a request nobody had committed to;
  // the HUD already offers it only once someone has.
  test('open with no committers disables enough help with a reason', () {
    final rows = buildBeaconStatusMenuRows(_input());
    final enough = _row(rows, BeaconStatusMenuRowId.enoughHelp);
    expect(enough.isEnabled, isFalse);
    expect(
      enough.disabledReason,
      BeaconStatusMenuDisabledReason.noHelpersYet,
    );
  });

  test('open with committers enables enough help', () {
    final rows = buildBeaconStatusMenuRows(_input(hasCommitters: true));
    expect(_row(rows, BeaconStatusMenuRowId.enoughHelp).isEnabled, isTrue);
  });

  test('enough help already set stays selected without committers', () {
    final rows = buildBeaconStatusMenuRows(
      _input(beacon: _beacon(status: BeaconStatus.enoughHelp)),
    );
    final enough = _row(rows, BeaconStatusMenuRowId.enoughHelp);
    expect(enough.isSelected, isTrue);
    expect(enough.isEnabled, isTrue);
  });

  test('a non-author still sees the author-only reason', () {
    final rows = buildBeaconStatusMenuRows(
      _input(canSetCoordination: false),
    );
    expect(
      _row(rows, BeaconStatusMenuRowId.enoughHelp).disabledReason,
      BeaconStatusMenuDisabledReason.lifecycleAuthorOnly,
    );
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

  group('after a reopen the request is "Needs more help" (B081)', () {
    // A reopen lands the request in needsMoreHelp, which closure readiness
    // counts as blocking. The sheet then said "Resolve open blockers first"
    // for Wrapping up and Closed although nothing named a blocker.
    List<BeaconStatusMenuRow> rowsAfterReopen() => buildBeaconStatusMenuRows(
      _input(
        beacon: _beacon(status: BeaconStatus.needsMoreHelp),
        hasCommitters: true,
        readiness: BeaconClosureReadiness.blocked,
        closureBlockedOnlyByNeedsMoreHelp: true,
      ),
    );

    test('wrapping up and closed point at Enough help, not at blockers', () {
      final rows = rowsAfterReopen();
      for (final id in [
        BeaconStatusMenuRowId.wrappingUp,
        BeaconStatusMenuRowId.closed,
      ]) {
        final row = _row(rows, id);
        expect(row.isEnabled, isFalse, reason: '$id');
        expect(
          row.disabledReason,
          BeaconStatusMenuDisabledReason.markEnoughHelpFirst,
          reason: '$id',
        );
      }
    });

    test('the Enough help row that unblocks them is enabled', () {
      final enough = _row(rowsAfterReopen(), BeaconStatusMenuRowId.enoughHelp);
      expect(enough.isEnabled, isTrue);
      expect(enough.isSelected, isFalse);
    });

    test('needs more help plus a real blocker keeps the blocker hint', () {
      // Marking Enough help would not unblock closing here, so the sheet must
      // not point at it.
      final rows = buildBeaconStatusMenuRows(
        _input(
          beacon: _beacon(status: BeaconStatus.needsMoreHelp),
          hasCommitters: true,
          readiness: BeaconClosureReadiness.blocked,
        ),
      );
      for (final id in [
        BeaconStatusMenuRowId.wrappingUp,
        BeaconStatusMenuRowId.closed,
      ]) {
        expect(
          _row(rows, id).disabledReason,
          BeaconStatusMenuDisabledReason.blocked,
          reason: '$id',
        );
      }
    });

    test('a real blocker on an open request keeps the blocker hint', () {
      final rows = buildBeaconStatusMenuRows(
        _input(
          beacon: _beacon(status: BeaconStatus.enoughHelp),
          hasCommitters: true,
          readiness: BeaconClosureReadiness.blocked,
        ),
      );
      expect(
        _row(rows, BeaconStatusMenuRowId.wrappingUp).disabledReason,
        BeaconStatusMenuDisabledReason.blocked,
      );
    });
  });
}
