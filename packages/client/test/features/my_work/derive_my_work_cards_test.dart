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
  BeaconCoordinationStatus coordination = BeaconCoordinationStatus.noHelpOffersYet,
  int helpOfferCount = 0,
}) =>
    Beacon.empty.copyWith(
      id: id,
      updatedAt: DateTime(2025, 1, 2),
      lifecycle: lifecycle,
      coordinationStatus: coordination,
      helpOfferCount: helpOfferCount,
      author: const Profile(id: 'auth', displayName: 'Author Co'),
    );

void main() {
  test('buildNonArchivedViewModels maps draft as authoredDraft', () {
    final authored = [_b(id: 'd', lifecycle: BeaconLifecycle.draft)];
    final vms = buildNonArchivedViewModels(
      authoredNonClosed: authored,
      helpOfferedNonClosed: const [],
    );
    expect(vms.single.kind, MyWorkCardKind.authoredDraft);
  });

  test('authored active shows Review commitments CTA when waiting review', () {
    final authored = [
      _b(
        id: 'a',
        lifecycle: BeaconLifecycle.open,
        coordination: BeaconCoordinationStatus.helpOffersWaitingForReview,
        helpOfferCount: 2,
      ),
    ];
    final vms = buildNonArchivedViewModels(
      authoredNonClosed: authored,
      helpOfferedNonClosed: const [],
    );
    expect(vms.single.showReviewHelpOffersCta, isTrue);
  });

  test('committed active shows ready for review chip in closedReviewOpen', () {
    final row = (
      beacon: _b(id: 'c', lifecycle: BeaconLifecycle.closedReviewOpen),
      offerHelpMessage: 'note',
      helpType: null,
      authorResponseType: null,
      forwarderSenders: const <Profile>[],
      helpOfferRowUpdatedAt: DateTime(2025, 1, 2),
      authorCoordinationUpdatedAt: null,
    );
    final vms = buildNonArchivedViewModels(
      authoredNonClosed: const [],
      helpOfferedNonClosed: [row],
    );
    expect(vms.single.showReadyForReviewChip, isTrue);
    expect(vms.single.showReviewCta, isTrue);
  });

  test('authored beacon drops duplicate committed row for same id', () {
    final beacon = _b(
      id: 'both',
      lifecycle: BeaconLifecycle.open,
      coordination: BeaconCoordinationStatus.enoughHelpOffered,
      helpOfferCount: 2,
    );
    final row = (
      beacon: beacon,
      offerHelpMessage: 'mine',
      helpType: null,
      authorResponseType: null,
      forwarderSenders: const <Profile>[],
      helpOfferRowUpdatedAt: DateTime(2025, 1, 3),
      authorCoordinationUpdatedAt: null,
    );
    final vms = buildNonArchivedViewModels(
      authoredNonClosed: [beacon],
      helpOfferedNonClosed: [row],
    );
    expect(vms.length, 1);
    expect(vms.single.role, MyWorkCardRole.authored);
    expect(vms.single.kind, MyWorkCardKind.authoredActive);
  });

  test('buildArchivedViewModels yields closed kinds', () {
    final closed = [_b(id: 'z', lifecycle: BeaconLifecycle.closed)];
    final row = (
      beacon: _b(id: 'y', lifecycle: BeaconLifecycle.closed),
      offerHelpMessage: '',
      helpType: null,
      authorResponseType: null,
      forwarderSenders: const <Profile>[],
      helpOfferRowUpdatedAt: DateTime(2025, 1, 2),
      authorCoordinationUpdatedAt: null,
    );
    final vms = buildArchivedViewModels(
      authoredClosed: closed,
      helpOfferedClosed: [row],
    );
    expect(
      vms.map((e) => e.kind).toSet(),
      {MyWorkCardKind.authoredClosed, MyWorkCardKind.helpOfferedClosed},
    );
  });

  test('myWorkCardViewModelForBeaconView mirrors authored list derivation', () {
    final b = _b(
      id: 'bv1',
      lifecycle: BeaconLifecycle.open,
      coordination: BeaconCoordinationStatus.moreOrDifferentHelpNeeded,
      helpOfferCount: 1,
    );
    final fromList = buildNonArchivedViewModels(
      authoredNonClosed: [b],
      helpOfferedNonClosed: const [],
    ).single;
    final fromBeaconView = myWorkCardViewModelForBeaconView(
      beacon: b,
      isBeaconMine: true,
      isHelpOffered: false,
      myOfferHelpMessage: '',
    );
    expect(fromBeaconView, fromList);
  });

  test('myWorkCardViewModelForBeaconView mirrors committed list derivation', () {
    final b = _b(id: 'bv2', lifecycle: BeaconLifecycle.open);
    final row = (
      beacon: b,
      offerHelpMessage: 'hi',
      helpType: null,
      authorResponseType: null,
      forwarderSenders: const <Profile>[],
      helpOfferRowUpdatedAt: DateTime(2025, 3),
      authorCoordinationUpdatedAt: null,
    );
    final fromList = buildNonArchivedViewModels(
      authoredNonClosed: const [],
      helpOfferedNonClosed: [row],
    ).single;
    final fromBeaconView = myWorkCardViewModelForBeaconView(
      beacon: b,
      isBeaconMine: false,
      isHelpOffered: true,
      myOfferHelpMessage: 'hi',
      myHelpOfferUpdatedAt: DateTime(2025, 3),
    );
    expect(fromBeaconView, fromList);
  });
}
