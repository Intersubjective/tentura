// The author's status line says how many of the people they forwarded the
// Request to have declined it, instead of "no offers yet", while no offer has
// come in (#486). Once an offer exists the usual offers line takes over.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_anchor_status.dart';
import 'package:tentura/features/forward/domain/entity/forward_edge.dart';
import 'package:tentura/ui/l10n/l10n.dart';

final _t = DateTime.utc(2026, 6, 20);
const _author = Profile(id: 'auth', displayName: 'Author');
const _helper = Profile(id: 'helper', displayName: 'Helper');

Beacon _beacon({int helpOfferCount = 0}) => Beacon(
  id: 'b1',
  title: 'T',
  author: _author,
  createdAt: _t,
  updatedAt: _t,
  helpOfferCount: helpOfferCount,
);

ForwardEdge _forward(
  String recipientId, {
  bool declined = false,
  bool cancelled = false,
  Profile sender = _author,
}) => ForwardEdge(
  id: 'e-$recipientId',
  beaconId: 'b1',
  createdAt: _t,
  sender: sender,
  recipient: Profile(id: recipientId, displayName: recipientId),
  recipientRejected: declined,
  cancelledAt: cancelled ? _t : null,
);

BeaconViewState _authorState({
  required List<ForwardEdge> forwards,
  int helpOfferCount = 0,
  List<TimelineHelpOffer> helpOffers = const [],
  Profile viewer = _author,
}) => BeaconViewState(
  beacon: _beacon(helpOfferCount: helpOfferCount),
  myProfile: viewer,
  myForwards: forwards,
  forwardsLoaded: true,
  helpOffers: helpOffers,
);

TimelineHelpOffer _offer() => TimelineHelpOffer(
  user: _helper,
  message: 'I can help',
  createdAt: _t,
  updatedAt: _t,
);

// Any of the Russian words for "declined / can't help".
final _ruDeclineWord = RegExp('отказ|отклон|не могут|не может|не смог');

void main() {
  final en = lookupL10n(const Locale('en'));
  final ru = lookupL10n(const Locale('ru'));

  group('author status line with declined forwards and no offers', () {
    test('one forward declined by its only recipient', () {
      final slots = beaconViewStatusSlots(
        en,
        _authorState(forwards: [_forward('r1', declined: true)]),
      );

      expect(
        slots.displayLine,
        contains('1 of 1 declined — forward to someone else'),
      );
      expect(slots.displayLine, isNot(contains(en.beaconPhaseNoOffersYet)));
    });

    test('one of two forwards declined', () {
      final slots = beaconViewStatusSlots(
        en,
        _authorState(
          forwards: [_forward('r1', declined: true), _forward('r2')],
        ),
      );

      expect(slots.displayLine, contains('1 of 2 declined'));
      expect(
        slots.displayLine,
        isNot(contains('forward to someone else')),
        reason: 'the forward-again nudge is only for when everyone declined',
      );
      expect(slots.displayLine, isNot(contains(en.beaconPhaseNoOffersYet)));
    });

    test(
      'Russian partial decline reads «1 из 2» with no forward-again nudge',
      () {
        final slots = beaconViewStatusSlots(
          ru,
          _authorState(
            forwards: [_forward('r1', declined: true), _forward('r2')],
          ),
        );

        expect(slots.displayLine, isNot(contains(ru.beaconPhaseNoOffersYet)));
        expect(slots.displayLine, contains('1 из 2'));
        expect(slots.displayLine, matches(_ruDeclineWord));
        expect(
          slots.displayLine,
          isNot(contains('перешл')),
          reason: 'the forward-again nudge is only for when everyone declined',
        );
        expect(slots.displayLine, isNot(contains('declined')));
      },
    );

    test('Russian all-declined reads «1 из 1» and nudges to forward again', () {
      final slots = beaconViewStatusSlots(
        ru,
        _authorState(forwards: [_forward('r1', declined: true)]),
      );

      expect(slots.displayLine, isNot(contains(ru.beaconPhaseNoOffersYet)));
      expect(slots.displayLine, contains('1 из 1'));
      expect(slots.displayLine, matches(_ruDeclineWord));
      expect(slots.displayLine, contains('перешл'));
      expect(slots.displayLine, isNot(contains('declined')));
    });

    test(
      'a cancelled forward counts in neither the declines nor the total',
      () {
        final slots = beaconViewStatusSlots(
          en,
          _authorState(
            forwards: [
              _forward('r1', declined: true),
              _forward('r2', cancelled: true),
              _forward('r3', declined: true, cancelled: true),
            ],
          ),
        );

        expect(
          slots.displayLine,
          contains('1 of 1 declined — forward to someone else'),
        );
      },
    );

    test('a cancelled declined forward alone leaves the no-offers cue', () {
      final slots = beaconViewStatusSlots(
        en,
        _authorState(
          forwards: [
            _forward('r1', declined: true, cancelled: true),
            _forward('r2'),
          ],
        ),
      );

      expect(slots.displayLine, contains(en.beaconPhaseNoOffersYet));
      expect(slots.displayLine, isNot(contains('declined')));
    });

    test("only the author's own forwards are counted", () {
      final slots = beaconViewStatusSlots(
        en,
        _authorState(
          forwards: [
            _forward('r1', declined: true),
            _forward('r2', sender: _helper),
            _forward('r3', declined: true, sender: _helper),
          ],
        ),
      );

      expect(slots.displayLine, contains('1 of 1 declined'));
    });

    test('a viewer who is not the author never sees the decline count', () {
      final slots = beaconViewStatusSlots(
        en,
        _authorState(
          forwards: [_forward('r1', declined: true, sender: _helper)],
          viewer: _helper,
        ),
      );

      expect(slots.displayLine, isNot(contains('declined')));
    });

    test('forwards nobody declined keep the no-offers cue', () {
      final slots = beaconViewStatusSlots(
        en,
        _authorState(forwards: [_forward('r1'), _forward('r2')]),
      );

      expect(slots.displayLine, contains(en.beaconPhaseNoOffersYet));
      expect(slots.displayLine, isNot(contains('declined')));
    });

    test('an author who forwarded to nobody keeps the no-offers cue', () {
      final slots = beaconViewStatusSlots(en, _authorState(forwards: const []));

      expect(slots.displayLine, contains(en.beaconPhaseNoOffersYet));
    });
  });

  group('author status line once an offer exists', () {
    test('shows the offers line, not the decline count', () {
      final slots = beaconViewStatusSlots(
        en,
        _authorState(
          forwards: [_forward('r1', declined: true), _forward('r2')],
          helpOfferCount: 1,
          helpOffers: [_offer()],
        ),
      );

      expect(slots.displayLine, contains(en.beaconPhaseOffersToReview(1)));
      expect(slots.displayLine, isNot(contains('declined')));
    });

    test('everyone declined but an offer exists: offers line, no nudge', () {
      final slots = beaconViewStatusSlots(
        en,
        _authorState(
          forwards: [_forward('r1', declined: true)],
          helpOfferCount: 1,
          helpOffers: [_offer()],
        ),
      );

      expect(slots.displayLine, contains(en.beaconPhaseOffersToReview(1)));
      expect(slots.displayLine, isNot(contains('declined')));
      expect(slots.displayLine, isNot(contains('forward to someone else')));
      expect(slots.displayLine, isNot(contains(en.beaconPhaseNoOffersYet)));
    });
  });
}
