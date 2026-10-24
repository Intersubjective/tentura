import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/commitment_stake_state.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/help_offer_admission_action.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_anchor_status.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'beacon_view_screen_harness.dart';

/// #636: while an offer waits for the author, the request status line shows
/// it — the author sees "N offers to review", the helper who offered sees
/// "Offer sent". The cue goes once the offer is accepted, declined or
/// withdrawn, and the status verb itself does not change (#504).
final _t = DateTime.utc(2026, 10, 20);
const _author = Profile(id: 'auth', displayName: 'Author');
const _helper = Profile(id: 'h1', displayName: 'Helper');

TimelineHelpOffer _offer(String userId) => TimelineHelpOffer(
  user: Profile(id: userId, displayName: userId),
  message: 'I can help',
  createdAt: _t,
  updatedAt: _t,
);

BeaconViewState _state({
  required Profile viewer,
  List<TimelineHelpOffer> offers = const [],
  List<BeaconParticipant> participants = const [],
  BeaconStatus status = BeaconStatus.open,
}) => BeaconViewState(
  beacon: Beacon(
    id: 'b636',
    title: 'T',
    author: _author,
    createdAt: _t,
    updatedAt: _t,
    status: status,
    helpOfferCount: offers.where((o) => !o.isWithdrawn).length,
  ),
  myProfile: viewer,
  helpOffers: offers,
  roomParticipants: participants,
  isHelpOffered: offers.any((o) => !o.isWithdrawn && o.user.id == viewer.id),
);

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
  });

  final l10n = lookupL10n(const Locale('en'));
  String line(BeaconViewState s) =>
      beaconViewStatusSlots(l10n, s, now: _t).displayLine;

  group('#636 pending-offer cue on the status line', () {
    test('author with no offers sees no review cue', () {
      final s = line(_state(viewer: _author));
      expect(s, contains(l10n.beaconPhaseLookingForHelpers));
      expect(s, isNot(contains('to review')));
    });

    test('author with one pending offer sees "1 offer to review"', () {
      final slots = beaconViewStatusSlots(
        l10n,
        _state(viewer: _author, offers: [_offer('h1')]),
        now: _t,
      );
      expect(slots.slot2, l10n.beaconPhaseOffersToReview(1));
      expect(slots.slot2, '1 offer to review');
      // #504: the first offer does not flip the shared status verb.
      expect(slots.slot1, l10n.beaconPhaseLookingForHelpers);
    });

    test('author with three pending offers sees the plural count', () {
      final slots = beaconViewStatusSlots(
        l10n,
        _state(
          viewer: _author,
          offers: [_offer('h1'), _offer('h2'), _offer('h3')],
        ),
        now: _t,
      );
      expect(slots.slot2, '3 offers to review');
      expect(slots.slot1, l10n.beaconPhaseLookingForHelpers);
    });

    test('helper whose offer waits sees "Offer sent"', () {
      final slots = beaconViewStatusSlots(
        l10n,
        _state(viewer: _helper, offers: [_offer('h1'), _offer('h2')]),
        now: _t,
      );
      expect(slots.slot2, l10n.beaconPhaseOfferSent);
      expect(slots.slot2, 'Offer sent');
      expect(slots.slot1, l10n.beaconPhaseLookingForHelpers);
    });

    test('an offer whose stake reads offered still counts as pending', () {
      final offered = _offer('h1').copyWith(
        stakeState: CommitmentStakeState.offered,
      );
      expect(
        beaconViewStatusSlots(
          l10n,
          _state(viewer: _author, offers: [offered]),
          now: _t,
        ).slot2,
        '1 offer to review',
      );
      expect(
        beaconViewStatusSlots(
          l10n,
          _state(viewer: _helper, offers: [offered]),
          now: _t,
        ).slot2,
        'Offer sent',
      );
    });

    test('a standby backup offer does not count for review', () {
      final backup = _offer('h2').copyWith(
        offerKind: TimelineHelpOffer.offerKindBackup,
      );
      final slots = beaconViewStatusSlots(
        l10n,
        _state(viewer: _author, offers: [_offer('h1'), backup]),
        now: _t,
      );
      expect(slots.slot2, '1 offer to review');
      expect(
        line(_state(viewer: _author, offers: [backup])),
        isNot(contains('to review')),
      );
    });

    test('a helper whose own offer is a standby backup does not see '
        '"Offer sent"', () {
      // #710: a backup never gets a coordination row, so it would read
      // "Offer sent" for as long as the request stays open.
      final backup = _offer('h1').copyWith(
        offerKind: TimelineHelpOffer.offerKindBackup,
      );
      expect(
        line(_state(viewer: _helper, offers: [backup])),
        isNot(contains(l10n.beaconPhaseOfferSent)),
      );
    });

    test('the author count is the same number as unansweredHelpOffersCount '
        '(helper already admitted to the room)', () {
      // h1 is in the room (participant row admitted) though the offer row
      // carries no room access yet: the HUD "Review N offers" skips it.
      final state = _state(
        viewer: _author,
        offers: [_offer('h1'), _offer('h2')],
        participants: [
          BeaconParticipant(
            id: 'p1',
            beaconId: 'b636',
            userId: 'h1',
            role: 0,
            status: 0,
            roomAccess: RoomAccessBits.admitted,
            createdAt: _t,
            updatedAt: _t,
          ),
        ],
      );
      expect(state.unansweredHelpOffersCount, 1);
      expect(
        beaconViewStatusSlots(l10n, state, now: _t).slot2,
        l10n.beaconPhaseOffersToReview(state.unansweredHelpOffersCount),
      );
      expect(
        beaconViewStatusSlots(l10n, state, now: _t).slot2,
        '1 offer to review',
      );
    });

    test('the helper already admitted to the room does not see '
        '"Offer sent"', () {
      final state = _state(
        viewer: _helper,
        offers: [_offer('h1')],
        participants: [
          BeaconParticipant(
            id: 'p1',
            beaconId: 'b636',
            userId: 'h1',
            role: 0,
            status: 0,
            roomAccess: RoomAccessBits.admitted,
            createdAt: _t,
            updatedAt: _t,
          ),
        ],
      );
      expect(line(state), isNot(contains(l10n.beaconPhaseOfferSent)));
    });

    test('a viewer who has not offered sees neither cue', () {
      final s = line(
        _state(
          viewer: const Profile(id: 'other', displayName: 'Other'),
          offers: [_offer('h1')],
        ),
      );
      expect(s, isNot(contains(l10n.beaconPhaseOfferSent)));
      expect(s, isNot(contains('to review')));
    });

    test('after accept the cue is gone for author and helper', () {
      final accepted = _offer('h1').copyWith(
        coordinationResponse: CoordinationResponseType.useful,
        roomAccess: RoomAccessBits.admitted,
        admissionAction: HelpOfferAdmissionAction.accept,
      );
      expect(
        line(_state(viewer: _author, offers: [accepted])),
        isNot(contains('to review')),
      );
      expect(
        line(_state(viewer: _helper, offers: [accepted])),
        isNot(contains(l10n.beaconPhaseOfferSent)),
      );
    });

    test('after accepting one of three the author sees two', () {
      final accepted = _offer('h1').copyWith(
        coordinationResponse: CoordinationResponseType.useful,
        admissionAction: HelpOfferAdmissionAction.accept,
      );
      final slots = beaconViewStatusSlots(
        l10n,
        _state(
          viewer: _author,
          offers: [accepted, _offer('h2'), _offer('h3')],
        ),
        now: _t,
      );
      expect(slots.slot2, '2 offers to review');
    });

    test('after decline the cue is gone for author and helper', () {
      final declined = _offer('h1').copyWith(
        coordinationResponse: CoordinationResponseType.notSuitable,
        admissionAction: HelpOfferAdmissionAction.decline,
      );
      expect(
        line(_state(viewer: _author, offers: [declined])),
        isNot(contains('to review')),
      );
      expect(
        line(_state(viewer: _helper, offers: [declined])),
        isNot(contains(l10n.beaconPhaseOfferSent)),
      );
    });

    test('after withdraw the cue is gone for author and helper', () {
      final withdrawn = _offer('h1').copyWith(isWithdrawn: true);
      expect(
        line(_state(viewer: _author, offers: [withdrawn])),
        isNot(contains('to review')),
      );
      expect(
        line(_state(viewer: _helper, offers: [withdrawn])),
        isNot(contains(l10n.beaconPhaseOfferSent)),
      );
    });

    test('closed request shows no pending-offer cue', () {
      final s = line(
        _state(
          viewer: _author,
          offers: [_offer('h1')],
          status: BeaconStatus.closed,
        ),
      );
      expect(s, contains(l10n.beaconPhaseClosed));
      expect(s, isNot(contains('to review')));
    });
  });

  group('#636 status line on the Request screen', () {
    setUp(() async {
      await registerBeaconViewHarnessGetIt();
    });

    tearDown(() async {
      await unregisterBeaconViewHarnessGetIt();
    });

    testWidgets('author top bar shows "3 offers to review"', (tester) async {
      final base = beaconViewHarnessAuthorState();
      final offers = [_offer('h1'), _offer('h2'), _offer('h3')];
      await pumpBeaconViewHarness(
        tester,
        size: kBeaconViewHarnessCompact,
        beaconState: base.copyWith(
          beacon: base.beacon.copyWith(helpOfferCount: offers.length),
          helpOffers: offers,
        ),
        threadsState: beaconViewHarnessThreadsState(),
      );

      expect(
        find.descendant(
          of: find.byType(TenturaTopBar),
          matching: find.textContaining(
            '3 offers to review',
            findRichText: true,
          ),
        ),
        findsOneWidget,
      );
    });
  });
}
