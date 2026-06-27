import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/my_work/domain/derive_my_work_cards.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';

Beacon _b({
  required String id,
  required BeaconStatus status,
  int helpOfferCount = 0,
  int unansweredHelpOfferCount = 0,
}) => Beacon.empty.copyWith(
  id: id,
  updatedAt: DateTime(2025, 1, 2),
  status: status,
  helpOfferCount: helpOfferCount,
  unansweredHelpOfferCount: unansweredHelpOfferCount,
  author: const Profile(id: 'auth', displayName: 'Author Co'),
);

void main() {
  test('buildNonArchivedViewModels maps draft as authoredDraft', () {
    final authored = [_b(id: 'd', status: BeaconStatus.draft)];
    final vms = buildNonArchivedViewModels(
      authoredNonArchived: authored,
      helpOfferedNonArchived: const [],
    );
    expect(vms.single.kind, MyWorkCardKind.authoredDraft);
  });

  test(
    'authored active shows Review commitments CTA when unanswered exist',
    () {
      final authored = [
        _b(
          id: 'a',
          status: BeaconStatus.enoughHelp,
          helpOfferCount: 2,
          unansweredHelpOfferCount: 2,
        ),
      ];
      final vms = buildNonArchivedViewModels(
        authoredNonArchived: authored,
        helpOfferedNonArchived: const [],
      );
      expect(vms.single.showReviewHelpOffersCta, isTrue);
    },
  );

  test(
    'authored active hides Review commitments CTA when all offers reviewed',
    () {
      final authored = [
        _b(
          id: 'a-reviewed',
          status: BeaconStatus.enoughHelp,
          helpOfferCount: 2,
          unansweredHelpOfferCount: 0,
        ),
      ];
      final vms = buildNonArchivedViewModels(
        authoredNonArchived: authored,
        helpOfferedNonArchived: const [],
      );
      expect(vms.single.showReviewHelpOffersCta, isFalse);
    },
  );

  test('committed active shows review CTA in reviewOpen', () {
    final row = (
      beacon: _b(id: 'c', status: BeaconStatus.reviewOpen),
      offerHelpMessage: 'note',
      helpType: null,
      authorResponseType: null,
      forwarderSenders: const <Profile>[],
      helpOfferRowUpdatedAt: DateTime(2025, 1, 2),
      authorCoordinationUpdatedAt: null,
    );
    final vms = buildNonArchivedViewModels(
      authoredNonArchived: const [],
      helpOfferedNonArchived: [row],
    );
    expect(vms.single.showReviewCta, isTrue);
  });

  test('authored beacon drops duplicate committed row for same id', () {
    final beacon = _b(
      id: 'both',
      status: BeaconStatus.enoughHelp,
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
      authoredNonArchived: [beacon],
      helpOfferedNonArchived: [row],
    );
    expect(vms.length, 1);
    expect(vms.single.role, MyWorkCardRole.authored);
    expect(vms.single.kind, MyWorkCardKind.authoredActive);
  });

  test('buildNonArchivedViewModels maps finished lifecycle', () {
    final authored = [_b(id: 'f', status: BeaconStatus.closed)];
    final vms = buildNonArchivedViewModels(
      authoredNonArchived: authored,
      helpOfferedNonArchived: const [],
    );
    expect(vms.single.kind, MyWorkCardKind.authoredFinished);
  });

  test('buildArchivedViewModels yields archived kinds', () {
    final closed = [_b(id: 'z', status: BeaconStatus.closed)];
    final row = (
      beacon: _b(id: 'y', status: BeaconStatus.closed),
      offerHelpMessage: '',
      helpType: null,
      authorResponseType: null,
      forwarderSenders: const <Profile>[],
      helpOfferRowUpdatedAt: DateTime(2025, 1, 2),
      authorCoordinationUpdatedAt: null,
    );
    final vms = buildArchivedViewModels(
      authoredArchived: closed,
      helpOfferedArchived: [row],
    );
    expect(
      vms.map((e) => e.kind).toSet(),
      {MyWorkCardKind.authoredArchived, MyWorkCardKind.helpOfferedArchived},
    );
  });

  test('myWorkCardViewModelForBeaconView mirrors authored list derivation', () {
    final b = _b(
      id: 'bv1',
      status: BeaconStatus.needsMoreHelp,
      helpOfferCount: 1,
    );
    final fromList = buildNonArchivedViewModels(
      authoredNonArchived: [b],
      helpOfferedNonArchived: const [],
    ).single;
    final fromBeaconView = myWorkCardViewModelForBeaconView(
      beacon: b,
      isBeaconMine: true,
      isHelpOffered: false,
      myOfferHelpMessage: '',
    );
    expect(fromBeaconView, fromList);
  });

  test(
    'myWorkCardViewModelForBeaconView mirrors committed list derivation',
    () {
      final b = _b(id: 'bv2', status: BeaconStatus.open);
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
        authoredNonArchived: const [],
        helpOfferedNonArchived: [row],
      ).single;
      final fromBeaconView = myWorkCardViewModelForBeaconView(
        beacon: b,
        isBeaconMine: false,
        isHelpOffered: true,
        myOfferHelpMessage: 'hi',
        myHelpOfferUpdatedAt: DateTime(2025, 3),
      );
      expect(fromBeaconView, fromList);
    },
  );
}
