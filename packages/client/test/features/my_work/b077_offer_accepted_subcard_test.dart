// B077: a helper must see that the author accepted their offer as an event
// sub-card inside the Request card on their «Requests» (My Work) tab,
// dismissible with ×, and the dismissal is remembered.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_access.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/data/repository/mock/client_repository_mocks.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/offer_accepted_dismissals.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/commitment_stake_state.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/closure/data/repository/closure_repository.dart';
import 'package:tentura/features/inbox/ui/widget/attention_mini_card.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_fetch_types.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_cubit.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_cards.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/offer_accepted_event_subcard.dart';

import 'my_work_test_support.dart';

const _viewerId = 'helper-1';

final class _TestProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state =>
      const ProfileState(profile: Profile(id: _viewerId, displayName: 'Me'));

  @override
  Stream<ProfileState> get stream =>
      Stream<ProfileState>.value(state).asBroadcastStream();
}

/// Survives "app restarts": a new [OfferAcceptedDismissals] reads it back.
final class _RecordingPort implements OfferAcceptedDismissalPort {
  Set<String> stored = {};

  @override
  Future<Set<String>> load() async => {...stored};

  @override
  Future<void> save(Set<String> keys) async => stored = {...keys};
}

Beacon _openBeacon(String id, {bool admitted = false}) => Beacon.empty.copyWith(
  id: id,
  // The viewer's access reasons: admitted to the room (bit 4) once accepted.
  accessReasons: admitted ? BeaconAccessReason.admitted.bit : 0,
  title: 'Moving day $id',
  updatedAt: DateTime(2026, 9, 5),
  status: BeaconStatus.open,
  author: const Profile(id: 'auth', displayName: 'Author Co'),
);

MyWorkHelpOfferedRow _row(
  Beacon beacon, {
  CoordinationResponseType? response,
}) => (
  beacon: beacon,
  offerHelpMessage: 'I can help',
  helpType: null,
  authorResponseType: response,
  stakeState: CommitmentStakeState.none,
  forwarderSenders: const <Profile>[],
  helpOfferRowUpdatedAt: DateTime(2026, 9, 4),
  authorCoordinationUpdatedAt: response == null ? null : DateTime(2026, 9, 5),
);

Future<MyWorkCubit> _cubitFor(MyWorkHelpOfferedRow row) async {
  final repo = FakeMyWorkRepository()
    ..initResult = (
      authoredNonArchived: const <Beacon>[],
      helpOfferedNonArchived: [row],
      obligationBeacons: const [],
      archivedCountHint: 0,
    );
  final cubit = MyWorkCubit(
    userId: _viewerId,
    myWorkCase: buildTestMyWorkCase(repo: repo),
  );
  await cubit.stream.firstWhere((s) => s.isSuccess);
  return cubit;
}

Future<void> _pumpDesk(WidgetTester tester, MyWorkCubit cubit) async {
  tester.view
    ..physicalSize = const Size(400, 1600)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      // A fresh tree each time: what is remembered must come from the store.
      key: UniqueKey(),
      locale: const Locale('en'),
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: TenturaResponsiveScope(
        child: MultiBlocProvider(
          providers: [
            BlocProvider<MyWorkCubit>.value(value: cubit),
            BlocProvider<ProfileCubit>.value(value: _TestProfileCubit()),
            BlocProvider<ScreenCubit>(create: (_) => ScreenCubit.local()),
          ],
          child: Scaffold(
            body: BlocBuilder<MyWorkCubit, MyWorkState>(
              builder: (context, state) => ListView(
                children: [
                  for (final vm in state.nonArchivedCards)
                    MyWorkCardRouter(vm: vm),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late _RecordingPort port;

  setUp(() async {
    if (!GetIt.I.isRegistered<Logger>()) {
      GetIt.I.registerSingleton<Logger>(Logger('b077'));
    }
    if (!GetIt.I.isRegistered<BeaconRepository>()) {
      GetIt.I.registerSingleton<BeaconRepository>(FakeBeaconRepository());
    }
    if (!GetIt.I.isRegistered<ClosureRepository>()) {
      GetIt.I.registerSingleton<ClosureRepository>(ClosureRepositoryMock());
    }
    port = _RecordingPort();
    final store = OfferAcceptedDismissals(port);
    await store.ready;
    GetIt.I.registerSingleton<OfferAcceptedDismissals>(store);
  });

  tearDown(() async {
    for (final unregister in <void Function()>[
      if (GetIt.I.isRegistered<BeaconRepository>())
        GetIt.I.unregister<BeaconRepository>,
      if (GetIt.I.isRegistered<ClosureRepository>())
        GetIt.I.unregister<ClosureRepository>,
      if (GetIt.I.isRegistered<OfferAcceptedDismissals>())
        GetIt.I.unregister<OfferAcceptedDismissals>,
    ]) {
      unregister();
    }
  });

  testWidgets('accepted offer shows an event sub-card in the helper card', (
    tester,
  ) async {
    final cubit = await _cubitFor(
      _row(
        _openBeacon('open-1', admitted: true),
        response: CoordinationResponseType.useful,
      ),
    );
    addTearDown(cubit.close);
    await _pumpDesk(tester, cubit);

    final l10n = lookupL10n(const Locale('en'));
    final subcard = find.byType(OfferAcceptedEventSubcard);
    expect(subcard, findsOneWidget);
    expect(
      find.descendant(
        of: subcard,
        matching: find.text(l10n.attentionCardOfferAccepted('Author Co')),
      ),
      findsOneWidget,
    );
    // The house event sub-card, with its ×.
    expect(
      find.descendant(of: subcard, matching: find.byType(AttentionMiniCard)),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: subcard,
        matching: find.byKey(AttentionMiniCard.dismissKey),
      ),
      findsOneWidget,
    );
  });

  testWidgets('× dismisses it, and the dismissal is remembered', (
    tester,
  ) async {
    final cubit = await _cubitFor(
      _row(
        _openBeacon('open-1', admitted: true),
        response: CoordinationResponseType.useful,
      ),
    );
    addTearDown(cubit.close);
    await _pumpDesk(tester, cubit);

    await tester.tap(find.byKey(AttentionMiniCard.dismissKey));
    await tester.pumpAndSettle();
    expect(find.byType(AttentionMiniCard), findsNothing);
    expect(
      port.stored,
      {OfferAcceptedDismissals.keyFor(viewerId: _viewerId, beaconId: 'open-1')},
    );

    // A new session (new store reading the same storage, new widget tree).
    GetIt.I.unregister<OfferAcceptedDismissals>();
    final reloaded = OfferAcceptedDismissals(port);
    await reloaded.ready;
    GetIt.I.registerSingleton<OfferAcceptedDismissals>(reloaded);
    await _pumpDesk(tester, cubit);
    expect(find.byType(AttentionMiniCard), findsNothing);
  });

  testWidgets('no sub-card while the offer is still waiting for the author', (
    tester,
  ) async {
    final cubit = await _cubitFor(_row(_openBeacon('open-2')));
    addTearDown(cubit.close);
    await _pumpDesk(tester, cubit);
    expect(find.byType(AttentionMiniCard), findsNothing);
  });

  testWidgets('no sub-card when the author declined the offer', (tester) async {
    final cubit = await _cubitFor(
      _row(
        _openBeacon('open-3'),
        response: CoordinationResponseType.notSuitable,
      ),
    );
    addTearDown(cubit.close);
    await _pumpDesk(tester, cubit);
    expect(find.byType(AttentionMiniCard), findsNothing);
  });

  // Review of #511, Blocking 1: one rule on both surfaces — admitted to the
  // room. Fails on da235b1, which read the author's response instead.
  testWidgets('no sub-card for a useful response without room admission', (
    tester,
  ) async {
    final cubit = await _cubitFor(
      _row(_openBeacon('open-4'), response: CoordinationResponseType.useful),
    );
    addTearDown(cubit.close);
    await _pumpDesk(tester, cubit);
    expect(find.byType(AttentionMiniCard), findsNothing);
  });

  testWidgets('sub-card once admitted, even with no author response', (
    tester,
  ) async {
    final cubit = await _cubitFor(
      _row(_openBeacon('open-5', admitted: true)),
    );
    addTearDown(cubit.close);
    await _pumpDesk(tester, cubit);
    expect(find.byType(AttentionMiniCard), findsOneWidget);
  });
}
