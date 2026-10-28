// The author's status line says how many of the people they forwarded the
// Request to have declined it, instead of "no offers yet", while no offer has
// come in (#486). Once an offer exists the usual offers line takes over. The
// People tab opens its Forwards fold on its own when one of those forwards was
// declined, so the red «Dismissed» line is not hidden behind a tap.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_anchor_status.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_people_tab_body.dart';
import 'package:tentura/features/forward/domain/entity/forward_edge.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import '../../support/people_tags_widget_harness.dart';

class _MockProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(profile: _author);

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

class _MockBeaconViewCubit extends Mock implements BeaconViewCubit {
  _MockBeaconViewCubit(this._state);

  final BeaconViewState _state;

  @override
  BeaconViewState get state => _state;

  @override
  Stream<BeaconViewState> get stream => Stream<BeaconViewState>.value(_state);

  @override
  Future<void> loadForwards() async {}
}

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

  group('People tab Forwards fold', () {
    // The author's forwards as the cubit loads them: the same edges feed the
    // status line (myForwards) and the Forwards fold (viewerForwardEdges).
    BeaconViewState peopleState(List<ForwardEdge> forwards) => _authorState(
      forwards: forwards,
    ).copyWith(viewerForwardEdges: forwards);

    Future<void> pumpPeopleTab(
      WidgetTester tester,
      BeaconViewState state,
    ) async {
      final cubit = _MockBeaconViewCubit(state);
      await tester.pumpPeopleTagsWidget(
        MaterialApp(
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('en'),
          home: MultiBlocProvider(
            providers: [
              BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
              BlocProvider<ScreenCubit>(create: (_) => ScreenCubit.local()),
              BlocProvider<BeaconViewCubit>.value(value: cubit),
            ],
            child: Scaffold(
              body: SingleChildScrollView(
                child: BeaconPeopleTabBody(
                  state: state,
                  beaconViewCubit: cubit,
                  l10n: lookupL10n(const Locale('en')),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('opens on first build when a forward was declined', (
      tester,
    ) async {
      await pumpPeopleTab(
        tester,
        peopleState([
          _forward('r1', declined: true),
          _forward('r2'),
        ]),
      );

      expect(find.text('Forwards (2)'), findsOneWidget);
      expect(find.text(en.myForwardDeclined), findsOneWidget);
    });

    testWidgets('stays closed when nobody declined', (tester) async {
      await pumpPeopleTab(
        tester,
        peopleState([_forward('r1'), _forward('r2')]),
      );

      expect(find.text('Forwards (2)'), findsOneWidget);
      expect(find.text(en.myForwardDeclined), findsNothing);

      await tester.tap(find.text('Forwards (2)'));
      await tester.pumpAndSettle();

      expect(
        find.text('r1'),
        findsOneWidget,
        reason: 'the rows are there, the fold was just closed',
      );
    });

    testWidgets('stays closed when the only decline was cancelled', (
      tester,
    ) async {
      await pumpPeopleTab(
        tester,
        peopleState([
          _forward('r1'),
          _forward('r2', declined: true, cancelled: true),
        ]),
      );

      expect(find.textContaining('Forwards ('), findsOneWidget);
      expect(find.text('r1'), findsNothing);
      expect(find.text(en.myForwardDeclined), findsNothing);
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
