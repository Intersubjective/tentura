// A person's row in a Request's People tab offers "Add to tag…" through a
// visible overflow button, a touch long press and a mouse secondary tap, on
// both the offer cards the participants see and the read-only helper rows an
// observer sees; the entry opens the add-to-tag sheet of that row's person.
// The viewer's own row and every row while the people-tags feature is off
// offer nothing.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_access.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_people_tab_body.dart';
import 'package:tentura/features/beacon_view/ui/widget/help_offer_tile.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/add_to_tag_sheet_probe.dart';
import '../../support/fake_people_tags_repository.dart';
import '../../support/optional_gate_call.dart';
import '../../support/person_menu_open_way.dart';

const _author = Profile(id: 'U-author', displayName: 'Olga Author');
const _helper = Profile(id: 'U-helper', displayName: 'Helen Helper');
const _observer = Profile(id: 'U-observer', displayName: 'Observer');

class _MockProfileCubit extends Mock implements ProfileCubit {
  _MockProfileCubit(this._viewer);

  final Profile _viewer;

  @override
  ProfileState get state => ProfileState(profile: _viewer);

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
}

final _t = DateTime.utc(2025);

BeaconViewState _state({
  required Profile viewer,
  List<TimelineHelpOffer> helpOffers = const [],
  List<Profile> admittedHelperRoster = const [],
  BeaconAccessLevel? accessLevel,
}) => BeaconViewState(
  beacon: Beacon(
    id: 'B1',
    title: 'T',
    author: _author,
    createdAt: _t,
    updatedAt: _t,
    accessLevel: accessLevel,
  ),
  myProfile: viewer,
  helpOffers: helpOffers,
  admittedHelperRoster: admittedHelperRoster,
);

TimelineHelpOffer _offerBy(Profile user) => TimelineHelpOffer(
  user: user,
  message: 'I can help',
  createdAt: _t,
  updatedAt: _t,
);

void main() {
  late PeopleTagsTestRig rig;

  setUp(() async {
    rig = await PeopleTagsTestRig.create(addToTagProbeRepository(_helper.id));
    GetIt.I.registerSingleton<PeopleTagsCase>(rig.peopleTags);
  });

  tearDown(() async {
    await GetIt.I.reset();
    await rig.dispose();
  });

  Future<void> pumpWith(
    WidgetTester tester, {
    required Profile viewer,
    required Widget Function(BeaconViewCubit cubit) body,
    BeaconViewState? state,
  }) async {
    await tester.binding.setSurfaceSize(const Size(500, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final screenCubit = ScreenCubit.local();
    addTearDown(screenCubit.close);
    final cubit = _MockBeaconViewCubit(state ?? _state(viewer: viewer));
    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: MultiBlocProvider(
          providers: [
            BlocProvider<ProfileCubit>.value(value: _MockProfileCubit(viewer)),
            BlocProvider<ScreenCubit>.value(value: screenCubit),
            BlocProvider<BeaconViewCubit>.value(value: cubit),
          ],
          child: Scaffold(body: SingleChildScrollView(child: body(cubit))),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// A Request member's People tab: the author with one offer waiting.
  /// [peopleTagsEnabled] null leaves the tab's own default (the gate).
  Future<void> pumpPeopleTab(
    WidgetTester tester, {
    bool? peopleTagsEnabled,
  }) {
    final state = _state(
      viewer: _author,
      helpOffers: [_offerBy(_helper)],
    );
    return pumpWith(
      tester,
      viewer: _author,
      state: state,
      body: (cubit) =>
          callWithPeopleTagsGate(
                BeaconPeopleTabBody.new,
                gate: peopleTagsEnabled,
                named: {
                  #state: state,
                  #beaconViewCubit: cubit,
                  #l10n: lookupL10n(const Locale('en')),
                },
              )!
              as Widget,
    );
  }

  /// The read-only People tab of somebody watching the Request.
  Future<void> pumpObserverTab(
    WidgetTester tester, {
    bool? peopleTagsEnabled,
    List<Profile> roster = const [_helper],
  }) {
    final state = _state(
      viewer: _observer,
      accessLevel: BeaconAccessLevel.observer,
      admittedHelperRoster: roster,
    );
    return pumpWith(
      tester,
      viewer: _observer,
      state: state,
      body: (cubit) =>
          callWithPeopleTagsGate(
                BeaconPeopleTabBody.new,
                gate: peopleTagsEnabled,
                named: {
                  #state: state,
                  #beaconViewCubit: cubit,
                  #l10n: lookupL10n(const Locale('en')),
                },
              )!
              as Widget,
    );
  }

  /// The card holding the person [name]: an offer card, or an observer's
  /// read-only helper row (both are tech cards).
  Finder cardOf(String name) => find
      .ancestor(
        of: find.text(name),
        matching: find.byType(TenturaTechCardStatic),
      )
      .first;

  Finder overflowOf(String name) =>
      find.descendant(of: cardOf(name), matching: find.byIcon(Icons.more_vert));

  group('Request People tab, offer card: add to tag', () {
    testWidgets('an offer card shows the person it is about', (tester) async {
      await pumpPeopleTab(tester, peopleTagsEnabled: true);

      expect(find.byType(HelpOfferTile), findsWidgets);
      expect(find.text('Helen Helper'), findsOneWidget);
    });

    for (final way in PersonMenuOpenWay.values) {
      testWidgets('"Add to tag…" opened by ${way.name} shows in the menu', (
        tester,
      ) async {
        await pumpPeopleTab(tester, peopleTagsEnabled: true);
        expect(find.text('Add to tag…'), findsNothing);

        await way.open(
          tester,
          overflow: overflowOf('Helen Helper'),
          target: find.text('Helen Helper'),
        );

        expect(find.text('Add to tag…'), findsOneWidget);
      });

      testWidgets(
        '"Add to tag…" opened by ${way.name} opens the sheet for that '
        "card's person",
        (tester) async {
          await pumpPeopleTab(tester, peopleTagsEnabled: true);

          await way.open(
            tester,
            overflow: overflowOf('Helen Helper'),
            target: find.text('Helen Helper'),
          );
          await tester.tap(find.text('Add to tag…'));

          await expectAddToTagSheetIsForPerson(
            tester,
            rig.repository,
            _helper.id,
          );
        },
      );
    }

    testWidgets('is absent when the feature is switched off', (tester) async {
      await pumpPeopleTab(tester, peopleTagsEnabled: false);

      expect(find.byIcon(Icons.more_vert), findsNothing);
      await expectNoPersonMenuFromGestures(
        tester,
        target: find.text('Helen Helper'),
      );
    });

    testWidgets('is absent when phase 1 is explicitly disabled', (
      tester,
    ) async {
      await pumpPeopleTab(tester, peopleTagsEnabled: false);

      expect(find.byIcon(Icons.more_vert), findsNothing);
      await expectNoPersonMenuFromGestures(
        tester,
        target: find.text('Helen Helper'),
      );
    });
  });

  group('Request People tab, offer card of the viewer: add to tag', () {
    testWidgets(
      'the viewer own offer card has no overflow button and no menu',
      (
        tester,
      ) async {
        final own = _offerBy(_helper);
        await pumpWith(
          tester,
          viewer: _helper,
          body: (cubit) =>
              callWithPeopleTagsGate(
                    HelpOfferTile.new,
                    gate: true,
                    named: {
                      #helpOffer: own,
                      #beaconId: 'B1',
                      #beaconAuthor: _author,
                      #beaconAuthorId: _author.id,
                      #isMine: true,
                    },
                  )!
                  as Widget,
        );

        expect(find.byType(HelpOfferTile), findsOneWidget);
        expect(find.byIcon(Icons.more_vert), findsNothing);
        await expectNoPersonMenuFromGestures(
          tester,
          target: find.byType(HelpOfferTile),
        );
      },
    );
  });

  group('Request People tab, own offer card in the full tab: add to tag', () {
    /// The full People tab as the person who made [_helper]'s offer, next to
    /// another helper's offer, with the tab gate on.
    Future<void> pumpOwnOfferTab(
      WidgetTester tester, {
      BeaconAccessLevel? accessLevel,
    }) {
      const other = Profile(id: 'U-other', displayName: 'Otto Other');
      // An observer sees helpers from the roster, a member from the offers.
      final state = _state(
        viewer: _helper,
        accessLevel: accessLevel,
        helpOffers: [
          _offerBy(_helper),
          if (accessLevel == null) _offerBy(other),
        ],
        admittedHelperRoster: [if (accessLevel != null) other],
      );
      return pumpWith(
        tester,
        viewer: _helper,
        state: state,
        body: (cubit) => BeaconPeopleTabBody(
          state: state,
          beaconViewCubit: cubit,
          l10n: lookupL10n(const Locale('en')),
        ),
      );
    }

    for (final level in <BeaconAccessLevel?>[
      null,
      BeaconAccessLevel.observer,
    ]) {
      final viewAs = level == null ? 'a member' : 'an observer';

      testWidgets(
        'the own card has no overflow button and no menu, seen as $viewAs, '
        'while another person card has the button',
        (tester) async {
          await pumpOwnOfferTab(tester, accessLevel: level);
          expect(find.text('You'), findsWidgets);
          expect(find.text('Otto Other'), findsOneWidget);

          expect(overflowOf('Otto Other'), findsOneWidget);
          expect(overflowOf('You'), findsNothing);
          await expectNoPersonMenuFromGestures(
            tester,
            target: find.text('You').first,
          );
        },
      );
    }
  });

  group('Request People tab, observer helper row: add to tag', () {
    for (final way in PersonMenuOpenWay.values) {
      testWidgets('"Add to tag…" opened by ${way.name} shows in the menu', (
        tester,
      ) async {
        await pumpObserverTab(tester, peopleTagsEnabled: true);
        expect(find.text('Helen Helper'), findsOneWidget);
        expect(find.text('Add to tag…'), findsNothing);

        await way.open(
          tester,
          overflow: overflowOf('Helen Helper'),
          target: find.text('Helen Helper'),
        );

        expect(find.text('Add to tag…'), findsOneWidget);
      });

      testWidgets(
        '"Add to tag…" opened by ${way.name} opens the sheet for that '
        "row's person",
        (tester) async {
          await pumpObserverTab(tester, peopleTagsEnabled: true);

          await way.open(
            tester,
            overflow: overflowOf('Helen Helper'),
            target: find.text('Helen Helper'),
          );
          await tester.tap(find.text('Add to tag…'));

          await expectAddToTagSheetIsForPerson(
            tester,
            rig.repository,
            _helper.id,
          );
        },
      );
    }

    testWidgets('a plain tap on the row opens no menu', (tester) async {
      await pumpObserverTab(tester, peopleTagsEnabled: true);

      await tester.tap(find.text('Helen Helper'));
      await tester.pumpAndSettle();

      expect(find.text('Add to tag…'), findsNothing);
    });

    testWidgets('the viewer own row has no overflow button and no menu', (
      tester,
    ) async {
      await pumpObserverTab(
        tester,

        roster: const [_helper, _observer],
      );
      expect(find.text('You'), findsOneWidget);

      expect(overflowOf('You'), findsNothing);
      await expectNoPersonMenuFromGestures(
        tester,
        target: find.text('You'),
      );
    });

    testWidgets('is absent when the feature is switched off', (tester) async {
      await pumpObserverTab(tester, peopleTagsEnabled: false);

      expect(find.byIcon(Icons.more_vert), findsNothing);
      await expectNoPersonMenuFromGestures(
        tester,
        target: find.text('Helen Helper'),
      );
    });

    testWidgets('is absent when phase 1 is explicitly disabled', (
      tester,
    ) async {
      await pumpObserverTab(tester, peopleTagsEnabled: false);

      expect(find.byIcon(Icons.more_vert), findsNothing);
      await expectNoPersonMenuFromGestures(
        tester,
        target: find.text('Helen Helper'),
      );
    });
  });
}
