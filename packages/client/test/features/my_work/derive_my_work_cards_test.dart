import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/domain/entity/coordination_status.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/my_work/domain/derive_my_work_cards.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';

Beacon _b({
  required String id,
  required BeaconLifecycle lifecycle,
  BeaconCoordinationStatus coordination = BeaconCoordinationStatus.noCommitmentsYet,
  int commitmentCount = 0,
}) =>
    Beacon.empty.copyWith(
      id: id,
      updatedAt: DateTime(2025, 1, 2),
      lifecycle: lifecycle,
      coordinationStatus: coordination,
      commitmentCount: commitmentCount,
      author: const Profile(id: 'auth', title: 'Author Co'),
    );

void main() {
  test('buildNonArchivedViewModels maps draft as authoredDraft', () {
    final authored = [_b(id: 'd', lifecycle: BeaconLifecycle.draft)];
    final vms = buildNonArchivedViewModels(
      authoredNonClosed: authored,
      committedNonClosed: const [],
    );
    expect(vms.single.kind, MyWorkCardKind.authoredDraft);
  });

  test('authored active shows Review commitments CTA when waiting review', () {
    final authored = [
      _b(
        id: 'a',
        lifecycle: BeaconLifecycle.open,
        coordination: BeaconCoordinationStatus.commitmentsWaitingForReview,
        commitmentCount: 2,
      ),
    ];
    final vms = buildNonArchivedViewModels(
      authoredNonClosed: authored,
      committedNonClosed: const [],
    );
    expect(vms.single.showReviewCommitmentsCta, isTrue);
  });

  test('committed active shows ready for review chip in closedReviewOpen', () {
    final row = (
      beacon: _b(id: 'c', lifecycle: BeaconLifecycle.closedReviewOpen),
      commitMessage: 'note',
      helpType: null,
      authorResponseType: null,
      forwarderSenders: const <Profile>[],
    );
    final vms = buildNonArchivedViewModels(
      authoredNonClosed: const [],
      committedNonClosed: [row],
    );
    expect(vms.single.showReadyForReviewChip, isTrue);
    expect(vms.single.showReviewCta, isTrue);
  });

  test('buildArchivedViewModels yields closed kinds', () {
    final closed = [_b(id: 'z', lifecycle: BeaconLifecycle.closed)];
    final row = (
      beacon: _b(id: 'y', lifecycle: BeaconLifecycle.closed),
      commitMessage: '',
      helpType: null,
      authorResponseType: null,
      forwarderSenders: const <Profile>[],
    );
    final vms = buildArchivedViewModels(
      authoredClosed: closed,
      committedClosed: [row],
    );
    expect(
      vms.map((e) => e.kind).toSet(),
      {MyWorkCardKind.authoredClosed, MyWorkCardKind.committedClosed},
    );
  });
}
