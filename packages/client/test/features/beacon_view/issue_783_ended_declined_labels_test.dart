// #783: another helper, and the author's Forwards row, must not call an
// ended or declined person withdrawn.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/commitment_stake_state.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/help_offer_admission_action.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_people_tab_body.dart';
import 'package:tentura/features/beacon_view/ui/widget/unified_forward_row.dart';
import 'package:tentura/features/forward/domain/entity/forward_edge.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/people_tags_widget_harness.dart';
import '../../support/phone_surface.dart';

class _MockProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(
    profile: Profile(id: 'auth', displayName: 'Author'),
  );

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

final _t = DateTime.utc(2026, 10, 26);

TimelineHelpOffer _offer({
  required String id,
  required String name,
  required bool isWithdrawn,
  CommitmentStakeState stake = CommitmentStakeState.none,
  CoordinationResponseType? response,
  HelpOfferAdmissionAction? admission,
  String? withdrawReason,
}) => TimelineHelpOffer(
  user: Profile(id: id, displayName: name),
  message: 'help',
  createdAt: _t,
  updatedAt: _t,
  isWithdrawn: isWithdrawn,
  stakeState: stake,
  coordinationResponse: response,
  admissionAction: admission,
  withdrawReason: withdrawReason,
);

ForwardEdge _edge(String id, String name) => ForwardEdge(
  id: 'e-$id',
  beaconId: 'B1',
  createdAt: _t,
  sender: const Profile(id: 'auth', displayName: 'Author'),
  recipient: Profile(id: id, displayName: name),
  note: 'please',
);

BeaconViewState _state({
  required List<TimelineHelpOffer> offers,
  required Profile viewer,
  List<ForwardEdge> edges = const [],
}) => BeaconViewState(
  beacon: Beacon(
    id: 'B1',
    title: 'T',
    author: const Profile(id: 'auth', displayName: 'Author'),
    createdAt: _t,
    updatedAt: _t,
  ),
  myProfile: viewer,
  helpOffers: offers,
  viewerForwardEdges: edges,
  forwardsLoaded: edges.isNotEmpty,
);

Future<void> _pump(
  WidgetTester tester, {
  required BeaconViewState state,
  required Locale locale,
}) {
  final l10n = lookupL10n(locale);
  return tester.pumpPeopleTagsWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      locale: locale,
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: MultiBlocProvider(
        providers: [
          BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
          BlocProvider<ScreenCubit>(create: (_) => ScreenCubit.local()),
          BlocProvider<BeaconViewCubit>.value(
            value: _MockBeaconViewCubit(state),
          ),
        ],
        child: Scaffold(
          body: SingleChildScrollView(
            child: BeaconPeopleTabBody(
              state: state,
              beaconViewCubit: _MockBeaconViewCubit(state),
              l10n: l10n,
              peopleTagsEnabled: false,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  final overflows = <String>[];

  setUp(() {
    overflows.clear();
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      final text = details.exceptionAsString();
      if (text.contains('overflowed')) overflows.add(text);
      previous?.call(details);
    };
    addTearDown(() => FlutterError.onError = previous);
  });

  testWidgets('another helper does not see ended or declined as Withdrawn', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final en = lookupL10n(const Locale('en'));
    // Admission is null: that is what helpOffersWithCoordination sends a
    // helper who is not the author and not the offerer.
    final state = _state(
      viewer: const Profile(id: 'carol', displayName: 'Carol'),
      offers: [
        _offer(
          id: 'dave',
          name: 'Dave',
          isWithdrawn: true,
          stake: CommitmentStakeState.released,
          response: CoordinationResponseType.useful,
        ),
        _offer(
          id: 'bob',
          name: 'Bob',
          isWithdrawn: true,
          stake: CommitmentStakeState.offered,
          response: CoordinationResponseType.notSuitable,
        ),
      ],
    );

    await _pump(tester, state: state, locale: const Locale('en'));
    await tester.pumpAndSettle();

    expect(find.textContaining('closed offer'), findsNothing);
    expect(find.text(en.labelWithdrawn), findsNothing);
    expect(find.text('Participation ended (1)'), findsOneWidget);
    expect(find.text('Declined offers (1)'), findsOneWidget);

    await tester.tap(find.text('Participation ended (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Declined offers (1)'));
    await tester.pumpAndSettle();

    expect(find.text('Dave'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text(en.helpOfferParticipationEndedLabel), findsWidgets);
    expect(find.text(en.helpOfferStatusDeclined), findsOneWidget);
    expect(overflows, isEmpty);
  });

  testWidgets('author Forwards row says declined, not withdrew commitment', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final en = lookupL10n(const Locale('en'));
    final state = _state(
      viewer: const Profile(id: 'auth', displayName: 'Author'),
      offers: [
        _offer(
          id: 'dave',
          name: 'Dave',
          isWithdrawn: true,
          stake: CommitmentStakeState.offered,
          response: CoordinationResponseType.notSuitable,
          admission: HelpOfferAdmissionAction.decline,
        ),
        _offer(
          id: 'bob',
          name: 'Bob',
          isWithdrawn: true,
          stake: CommitmentStakeState.exited,
          withdrawReason: 'other',
        ),
      ],
      edges: [_edge('dave', 'Dave'), _edge('bob', 'Bob')],
    );

    await _pump(tester, state: state, locale: const Locale('en'));
    await tester.pumpAndSettle();

    expect(find.text('Declined offers (1)'), findsOneWidget);
    await tester.tap(find.text('Forwards (2)'));
    await tester.pumpAndSettle();

    final dave = find.ancestor(
      of: find.text('Dave'),
      matching: find.byType(UnifiedForwardRow),
    );
    final bob = find.ancestor(
      of: find.text('Bob'),
      matching: find.byType(UnifiedForwardRow),
    );
    expect(
      find.descendant(
        of: dave,
        matching: find.text(en.helpOfferStatusDeclined),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dave, matching: find.text(en.forwardWithdrawn)),
      findsNothing,
    );
    expect(
      find.descendant(of: bob, matching: find.text(en.forwardWithdrawn)),
      findsOneWidget,
    );
    expect(overflows, isEmpty);
  });

  testWidgets('375 ru: ended and declined labels fit', (tester) async {
    await usePhoneSurface(tester);
    final ru = lookupL10n(const Locale('ru'));
    final state = _state(
      viewer: const Profile(id: 'auth', displayName: 'Author'),
      offers: [
        _offer(
          id: 'dave',
          name: 'Dave',
          isWithdrawn: true,
          stake: CommitmentStakeState.released,
          response: CoordinationResponseType.useful,
        ),
        _offer(
          id: 'bob',
          name: 'Bob',
          isWithdrawn: true,
          stake: CommitmentStakeState.offered,
          response: CoordinationResponseType.notSuitable,
        ),
      ],
      edges: [_edge('bob', 'Bob')],
    );

    await _pump(tester, state: state, locale: const Locale('ru'));
    await tester.pumpAndSettle();

    expect(
      find.text('${ru.beaconPeopleLensParticipationEndedHeading} (1)'),
      findsOneWidget,
    );
    expect(
      find.text('${ru.beaconPeopleLensNotFittingHeading} (1)'),
      findsOneWidget,
    );
    expect(find.text(ru.labelWithdrawn), findsNothing);
    expect(find.text(ru.forwardWithdrawn), findsNothing);

    await tester.tap(
      find.text('${ru.beaconPeopleLensParticipationEndedHeading} (1)'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('${ru.beaconPeopleLensNotFittingHeading} (1)'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.textContaining(ru.labelForwards));
    await tester.tap(find.textContaining(ru.labelForwards));
    await tester.pumpAndSettle();

    expect(find.text(ru.helpOfferParticipationEndedLabel), findsWidgets);
    expect(find.text(ru.helpOfferStatusDeclined), findsWidgets);
    expect(find.text('Dave'), findsOneWidget);
    expect(find.text('Bob'), findsWidgets);
    expect(overflows, isEmpty);
  });
}
