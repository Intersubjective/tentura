import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/evaluation/domain/review_package_state.dart';

typedef _Case = ({
  String name,
  bool beaconIsInReview,
  bool beaconIsClosed,
  bool hasWindow,
  bool windowComplete,
  int? userReviewStatus,
  DateTime? sentAt,
  int requiredTotal,
  int requiredAnswered,
  int totalTargets,
  ReviewPackageState expected,
});

/// Baseline is a live checklist window: enrolled, nothing answered yet,
/// nothing sent. Rows override only the fields under test.
_Case _row({
  required String name,
  required ReviewPackageState expected,
  bool beaconIsInReview = true,
  bool beaconIsClosed = false,
  bool hasWindow = true,
  bool windowComplete = false,
  int? userReviewStatus = 0,
  DateTime? sentAt,
  int requiredTotal = 1,
  int requiredAnswered = 0,
  int totalTargets = 1,
}) => (
  name: name,
  beaconIsInReview: beaconIsInReview,
  beaconIsClosed: beaconIsClosed,
  hasWindow: hasWindow,
  windowComplete: windowComplete,
  userReviewStatus: userReviewStatus,
  sentAt: sentAt,
  requiredTotal: requiredTotal,
  requiredAnswered: requiredAnswered,
  totalTargets: totalTargets,
  expected: expected,
);

ReviewPackageState _derive(_Case c) => deriveReviewPackageState(
  beaconIsInReview: c.beaconIsInReview,
  beaconIsClosed: c.beaconIsClosed,
  hasWindow: c.hasWindow,
  windowComplete: c.windowComplete,
  userReviewStatus: c.userReviewStatus,
  sentAt: c.sentAt,
  requiredTotal: c.requiredTotal,
  requiredAnswered: c.requiredAnswered,
  totalTargets: c.totalTargets,
);

void _runAll(List<_Case> cases) {
  for (final c in cases) {
    test(c.name, () => expect(_derive(c), c.expected));
  }
}

final _sentAt = DateTime.utc(2026, 3, 14);

void main() {
  group('all nine states are reachable', () {
    _runAll([
      _row(
        name: 'notEnrolled — status -1 in a live window',
        userReviewStatus: -1,
        expected: ReviewPackageState.notEnrolled,
      ),
      _row(
        name: 'empty — enrolled but no targets',
        userReviewStatus: 1,
        totalTargets: 0,
        expected: ReviewPackageState.empty,
      ),
      _row(
        name: 'inProgress — a required target is unanswered',
        userReviewStatus: 1,
        requiredTotal: 2,
        requiredAnswered: 1,
        totalTargets: 2,
        expected: ReviewPackageState.inProgress,
      ),
      _row(
        name: 'readyToSend — every required target answered, nothing sent',
        userReviewStatus: 1,
        requiredAnswered: 1,
        expected: ReviewPackageState.readyToSend,
      ),
      _row(
        name: 'sent — server status 2',
        userReviewStatus: 2,
        sentAt: _sentAt,
        requiredAnswered: 1,
        expected: ReviewPackageState.sent,
      ),
      _row(
        name: 'changedNotSent — sent once, then edited back to complete',
        userReviewStatus: 1,
        sentAt: _sentAt,
        requiredAnswered: 1,
        expected: ReviewPackageState.changedNotSent,
      ),
      _row(
        name: 'paused — window lost while the request is not in review',
        beaconIsInReview: false,
        hasWindow: false,
        userReviewStatus: 1,
        expected: ReviewPackageState.paused,
      ),
      _row(
        name: 'closed — window complete and the viewer had sent',
        userReviewStatus: 1,
        windowComplete: true,
        sentAt: _sentAt,
        expected: ReviewPackageState.closed,
      ),
      _row(
        name: 'closedUnsent — window complete and the viewer had not sent',
        userReviewStatus: 1,
        windowComplete: true,
        expected: ReviewPackageState.closedUnsent,
      ),
    ]);
  });

  group('status 1 without sentAt never yields changedNotSent', () {
    _runAll([
      _row(
        name: 'status 1, no sentAt, incomplete → inProgress',
        userReviewStatus: 1,
        requiredTotal: 3,
        requiredAnswered: 2,
        totalTargets: 3,
        expected: ReviewPackageState.inProgress,
      ),
      _row(
        name: 'status 1, no sentAt, complete → readyToSend',
        userReviewStatus: 1,
        requiredTotal: 3,
        requiredAnswered: 3,
        totalTargets: 3,
        expected: ReviewPackageState.readyToSend,
      ),
    ]);
  });

  group('status 3 behaves like status 0', () {
    _runAll([
      _row(
        name: 'status 0, incomplete → inProgress',
        userReviewStatus: 0,
        requiredTotal: 2,
        requiredAnswered: 1,
        totalTargets: 2,
        expected: ReviewPackageState.inProgress,
      ),
      _row(
        name: 'status 3, incomplete → inProgress',
        userReviewStatus: 3,
        requiredTotal: 2,
        requiredAnswered: 1,
        totalTargets: 2,
        expected: ReviewPackageState.inProgress,
      ),
      _row(
        name: 'status 0, complete → readyToSend',
        userReviewStatus: 0,
        requiredTotal: 2,
        requiredAnswered: 2,
        totalTargets: 2,
        expected: ReviewPackageState.readyToSend,
      ),
      _row(
        name: 'status 3, complete → readyToSend',
        userReviewStatus: 3,
        requiredTotal: 2,
        requiredAnswered: 2,
        totalTargets: 2,
        expected: ReviewPackageState.readyToSend,
      ),
    ]);
  });

  group('completeness edges', () {
    _runAll([
      _row(
        name: 'requiredTotal 0 with targets present → readyToSend',
        requiredTotal: 0,
        requiredAnswered: 0,
        totalTargets: 2,
        expected: ReviewPackageState.readyToSend,
      ),
      _row(
        name: 'totalTargets 0 → empty, never readyToSend',
        userReviewStatus: 1,
        requiredTotal: 0,
        requiredAnswered: 0,
        totalTargets: 0,
        expected: ReviewPackageState.empty,
      ),
      _row(
        name: 'sentAt set and a required answer removed → inProgress',
        userReviewStatus: 1,
        sentAt: _sentAt,
        requiredTotal: 2,
        requiredAnswered: 1,
        totalTargets: 2,
        expected: ReviewPackageState.inProgress,
      ),
    ]);
  });

  group('missing window', () {
    _runAll([
      _row(
        name: 'no window while the request is in review → notEnrolled',
        beaconIsInReview: true,
        hasWindow: false,
        expected: ReviewPackageState.notEnrolled,
      ),
      _row(
        name: 'no window and the request is not in review → paused',
        beaconIsInReview: false,
        hasWindow: false,
        userReviewStatus: 1,
        expected: ReviewPackageState.paused,
      ),
    ]);
  });

  group('closed windows', () {
    _runAll([
      _row(
        name: 'windowComplete with sentAt → closed',
        userReviewStatus: 1,
        windowComplete: true,
        sentAt: _sentAt,
        expected: ReviewPackageState.closed,
      ),
      _row(
        name: 'windowComplete without sentAt → closedUnsent',
        userReviewStatus: 1,
        windowComplete: true,
        expected: ReviewPackageState.closedUnsent,
      ),
      _row(
        name: 'beaconIsClosed with sentAt → closed',
        userReviewStatus: 1,
        beaconIsClosed: true,
        sentAt: _sentAt,
        expected: ReviewPackageState.closed,
      ),
      _row(
        name: 'beaconIsClosed without sentAt → closedUnsent',
        userReviewStatus: 1,
        beaconIsClosed: true,
        expected: ReviewPackageState.closedUnsent,
      ),
      _row(
        name: 'status 4 in a live window → closedUnsent',
        userReviewStatus: 4,
        expected: ReviewPackageState.closedUnsent,
      ),
    ]);
  });
}
