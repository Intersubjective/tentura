// #486: the author of an open Request reads the HUD "you" row on the
// Overview. When there is nothing else for them to do, that row nudges them to
// forward: "Everyone declined — forward to someone else" once every person
// they forwarded to chose «Can't help», otherwise "You can forward" — never
// "No open items".
//
// The state is the one the screen gets: a real `BeaconViewCubit` loads the
// Request and the author's forwards through its use case, and the real header
// card renders that state.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_operational_header_card.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/forward_edge.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'beacon_view_case_test_support.dart';

const _author = Profile(id: 'Uauthor', displayName: 'Author');
const _bob = Profile(id: 'Ubob', displayName: 'Bob');
const _carol = Profile(id: 'Ucarol', displayName: 'Carol');
const _beaconId = 'Bopen486';

class _MockProfileCubit extends Mock implements ProfileCubit {
  _MockProfileCubit(this.profile);

  final Profile profile;

  @override
  ProfileState get state => ProfileState(profile: profile);

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

/// The author's forwards as the server returns them: one edge per recipient,
/// `true` values marking the people who chose «Can't help».
class _AuthorForwards extends FakeBeaconViewForwardRepository {
  _AuthorForwards({required this.request, required this.recipients});

  final Beacon request;
  final Map<Profile, bool> recipients;

  List<ForwardEdge> get _edges => [
    for (final entry in recipients.entries)
      ForwardEdge(
        id: 'edge-${entry.key.id}',
        beaconId: request.id,
        createdAt: DateTime.utc(2026, 10, 19, 12),
        sender: request.author,
        recipient: entry.key,
        recipientRejected: entry.value,
      ),
  ];

  @override
  Future<List<ForwardEdge>> fetchEdges({required String beaconId}) async =>
      _edges;

  @override
  Future<List<ForwardEdge>> fetchMyForwardEdges({
    required String beaconId,
    required String myUserId,
  }) async => _edges;

  @override
  Future<bool> currentUserHasForwardedBeacon(String beaconId) async =>
      recipients.isNotEmpty;

  @override
  Future<Map<String, List<String>>> fetchReasonsByBeacon({
    required String beaconId,
  }) async => const {};

  BeaconInvolvementData _involvement() => (
    beacon: request,
    forwardedToIds: {for (final p in recipients.keys) p.id},
    helpOfferedIds: const <String>{},
    withdrawnIds: const <String>{},
    rejectedIds: {
      for (final e in recipients.entries)
        if (e.value) e.key.id,
    },
    watchingIds: const <String>{},
    onwardForwarderIds: const <String>{},
    myForwardedRecipientNotes: {for (final p in recipients.keys) p.id: ''},
    myForwardedRecipientEdgeIds: {
      for (final p in recipients.keys) p.id: 'edge-${p.id}',
    },
    myForwardedRecipientReadAts: {for (final p in recipients.keys) p.id: null},
    myForwardedRecipientHasOnwardChild: {
      for (final p in recipients.keys) p.id: false,
    },
    myForwardedRecipientRejected: {
      for (final e in recipients.entries) e.key.id: e.value,
    },
  );

  @override
  Future<BeaconInvolvementData> fetchBeaconInvolvement({
    required String beaconId,
  }) async => _involvement();

  @override
  Future<BeaconInvolvementData> fetchInvolvementForBeacon(
    Beacon beacon,
  ) async => _involvement();
}

final _openRequest = Beacon(
  id: _beaconId,
  title: 'Need a ladder on Saturday',
  createdAt: DateTime.utc(2026, 10, 19),
  updatedAt: DateTime.utc(2026, 10, 19),
  startAt: DateTime.utc(2099, 6, 20, 12),
  viewerCanForward: true,
  author: _author,
);

/// Opens the author's Request on a real cubit (forwards read included) and
/// renders its header card in [locale].
Future<void> _openAsAuthor(
  WidgetTester tester, {
  required Map<Profile, bool> forwardedTo,
  String locale = 'en',
}) async {
  tester.view.physicalSize = const Size(800, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final cubit = BeaconViewCubit(
    id: _beaconId,
    myProfile: _author,
    beaconViewCase: buildTestBeaconViewCase(
      beaconRepo: TrackingBeaconRepository()
        ..fetchByIdHandler = (_) async => _openRequest,
      forward: _AuthorForwards(request: _openRequest, recipients: forwardedTo),
    ),
    effects: FakeUiEffectPort(),
  );
  addTearDown(cubit.close);

  Widget card(BeaconViewState state) => MaterialApp(
    theme: TenturaTheme.light(),
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    locale: Locale(locale),
    home: BlocProvider<ProfileCubit>.value(
      value: _MockProfileCubit(_author),
      child: TenturaResponsiveScope(
        child: Scaffold(
          body: BeaconOperationalHeaderCard(
            state: state,
            onAuthorTap: () {},
          ),
        ),
      ),
    ),
  );

  await tester.pumpWidget(card(cubit.state));
  // Let the load and the author's silent forwards read finish, then redraw
  // the card from the state the cubit ended up with.
  for (var i = 0; i < 30 && !cubit.state.forwardsLoaded; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(cubit.state.beaconContextLoaded, isTrue);
  expect(cubit.state.forwardsLoaded, isTrue);
  await tester.pumpWidget(card(cubit.state));
  await tester.pumpAndSettle();
}

Finder _text(String s) => find.text(s, findRichText: true);

void main() {
  final en = lookupL10n(const Locale('en'));
  final ru = lookupL10n(const Locale('ru'));

  group('author HUD you row on an open Request with nothing else to do', () {
    testWidgets('every forward declined: says everyone declined, forward on', (
      tester,
    ) async {
      await _openAsAuthor(tester, forwardedTo: {_bob: true, _carol: true});

      expect(
        _text('Everyone declined — forward to someone else'),
        findsOneWidget,
      );
      expect(_text(en.beaconYouNoOpenItems), findsNothing);
    });

    testWidgets('one forward still pending: says you can forward', (
      tester,
    ) async {
      await _openAsAuthor(tester, forwardedTo: {_bob: false});

      expect(_text('You can forward'), findsOneWidget);
      expect(_text(en.beaconYouNoOpenItems), findsNothing);
    });

    testWidgets(
      'some declined and some pending: still just «You can forward»',
      (
        tester,
      ) async {
        await _openAsAuthor(tester, forwardedTo: {_bob: true, _carol: false});

        expect(_text(en.beaconHudYouForward), findsOneWidget);
        expect(_text(en.beaconHudYouForwardAfterDecline), findsNothing);
        expect(_text(en.beaconYouNoOpenItems), findsNothing);
      },
    );

    testWidgets('forwarded to nobody yet: says you can forward', (
      tester,
    ) async {
      await _openAsAuthor(tester, forwardedTo: const {});

      expect(_text(en.beaconHudYouForward), findsOneWidget);
      expect(_text(en.beaconYouNoOpenItems), findsNothing);
    });

    testWidgets('every forward declined, in Russian', (tester) async {
      await _openAsAuthor(
        tester,
        forwardedTo: {_bob: true, _carol: true},
        locale: 'ru',
      );

      expect(
        _text('Все отказались — перешлите кому-нибудь ещё'),
        findsOneWidget,
      );
      expect(_text(ru.beaconYouNoOpenItems), findsNothing);
    });

    testWidgets('one forward still pending, in Russian', (tester) async {
      await _openAsAuthor(tester, forwardedTo: {_bob: false}, locale: 'ru');

      expect(_text('Можете переслать'), findsOneWidget);
      expect(_text(ru.beaconYouNoOpenItems), findsNothing);
    });
  });
}
