import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/invitation_entity.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/forward/domain/entity/forward_candidate.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/forward/ui/screen/forward_beacon_screen.dart';
import 'package:tentura/features/forward/ui/widget/compact_beacon_context_strip.dart';
import 'package:tentura/features/invitation/data/repository/invitation_repository.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../ui/effect/fake_ui_effect_port.dart';

class _MockProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState();

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

class _FakeInvitationRepository extends Fake implements InvitationRepository {
  @override
  Stream<void> get changes => const Stream<void>.empty();

  @override
  Future<List<InvitationEntity>> fetchMine({
    int offset = 0,
    int limit = 0,
  }) async => <InvitationEntity>[];

  @override
  Future<InvitationFetchByIdResult?> fetchById(String id) async => null;

  @override
  Future<InvitationEntity> create({
    required String addresseeName,
    String? beaconId,
  }) => throw UnimplementedError();

  @override
  Future<void> deleteById(String id) async {}

  @override
  Future<void> dispose() async {}
}

void _registerInvitationRepository() {
  final getIt = GetIt.I;
  unawaited(
    (() async {
      if (getIt.isRegistered<InvitationRepository>()) {
        await getIt.unregister<InvitationRepository>();
      }
    })(),
  );

  getIt.registerSingleton<InvitationRepository>(_FakeInvitationRepository());

  addTearDown(() {
    unawaited(
      (() async {
        if (getIt.isRegistered<InvitationRepository>()) {
          await getIt.unregister<InvitationRepository>();
        }
      })(),
    );
  });
}

void _registerUiEffectPort() {
  final getIt = GetIt.I;
  if (!getIt.isRegistered<UiEffectPort>()) {
    getIt.registerSingleton<UiEffectPort>(FakeUiEffectPort());
    addTearDown(() {
      unawaited(
        (() async {
          if (getIt.isRegistered<UiEffectPort>()) {
            await getIt.unregister<UiEffectPort>();
          }
        })(),
      );
    });
  }
}

Future<void> _pumpForwardPage(
  WidgetTester tester, {
  required ForwardCubit cubit,
  Size size = const Size(360, 780),
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      theme: TenturaTheme.light(),
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: MultiBlocProvider(
          providers: [
            BlocProvider<ForwardCubit>.value(value: cubit),
            BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
          ],
          child: const ForwardBeaconPage(beaconId: 'b1'),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

ForwardCubit _forwardCubitWithBeacon({
  Set<String> selectedIds = const {},
  Set<String> needs = const {},
}) {
  final cubit = ForwardCubit(
    beaconId: 'b1',
    debugSkipInitialLoad: true,
    effects: FakeUiEffectPort(),
  );

  final beacon = Beacon.empty.copyWith(
    id: 'aaaaaaaa-bbbb-cccc-dddd-1234567890ab',
    title: 'Test beacon',
    context: 'General',
    needs: needs,
    startAt: DateTime.utc(2025, 5, 12),
    endAt: DateTime.utc(2025, 5, 19),
  );

  cubit.emit(
    ForwardState(
      beaconId: 'b1',
      beacon: beacon,
      candidates: const [
        ForwardCandidate(
          profile: Profile(
            id: 'u1',
            displayName: 'Clara',
            rScore: 1,
            score: 70,
          ),
        ),
      ],
      selectedIds: selectedIds,
      candidatesLoad: const ForwardCandidatesReady(),
    ),
  );

  return cubit;
}

void main() {
  testWidgets('compact forward page has no chip filters; shows scope row', (
    tester,
  ) async {
    _registerInvitationRepository();
    _registerUiEffectPort();

    final cubit = ForwardCubit(
      beaconId: 'b1',
      debugSkipInitialLoad: true,
      effects: FakeUiEffectPort(),
    );
    addTearDown(cubit.close);

    final beacon = Beacon.empty.copyWith(
      id: 'aaaaaaaa-bbbb-cccc-dddd-1234567890ab',
      title: 'Test beacon',
      context: 'General',
      startAt: DateTime.utc(2025, 5, 12),
      endAt: DateTime.utc(2025, 5, 19),
    );

    final candidates = [
      const ForwardCandidate(
        profile: Profile(
          id: 'u1',
          displayName: 'Clara',
          rScore: 1,
          score: 70,
        ),
      ),
      const ForwardCandidate(
        profile: Profile(
          id: 'u2',
          displayName: 'Zed',
          rScore: 1,
          score: 20,
        ),
      ),
    ];

    cubit.emit(
      ForwardState(
        beaconId: 'b1',
        beacon: beacon,
        candidates: candidates,
        candidatesLoad: const ForwardCandidatesReady(),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        theme: TenturaTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(size: Size(360, 780)),
          child: MultiBlocProvider(
            providers: [
              BlocProvider<ForwardCubit>.value(value: cubit),
              BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
            ],
            child: const ForwardBeaconPage(beaconId: 'b1'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(FilterChip), findsNothing);
    expect(find.text('BEST NEXT'), findsNothing);
    expect(find.textContaining('Not yet seen'), findsOneWidget);
    expect(find.textContaining('Already involved'), findsOneWidget);
    expect(find.byType(CompactBeaconContextStrip), findsOneWidget);
  });

  testWidgets('search icon opens full-screen overlay with search field', (
    tester,
  ) async {
    _registerInvitationRepository();
    _registerUiEffectPort();

    final cubit = ForwardCubit(
      beaconId: 'b1',
      debugSkipInitialLoad: true,
      effects: FakeUiEffectPort(),
    );
    addTearDown(cubit.close);

    final beacon = Beacon.empty.copyWith(
      id: 'id',
      title: 'T',
    );

    cubit.emit(
      ForwardState(
        beaconId: 'b1',
        beacon: beacon,
        candidatesLoad: const ForwardCandidatesEmpty(),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        theme: TenturaTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(size: Size(360, 800)),
          child: MultiBlocProvider(
            providers: [
              BlocProvider<ForwardCubit>.value(value: cubit),
              BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
            ],
            child: const ForwardBeaconPage(beaconId: 'b1'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CompactBeaconContextStrip), findsOneWidget);

    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();

    expect(find.text('search recipients'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('reason chip selection persists after list scroll', (
    tester,
  ) async {
    _registerInvitationRepository();
    _registerUiEffectPort();

    final cubit = ForwardCubit(
      beaconId: 'b1',
      debugSkipInitialLoad: true,
      effects: FakeUiEffectPort(),
    );
    addTearDown(cubit.close);

    final beacon = Beacon.empty.copyWith(id: 'b1', title: 'Test');

    final candidates = List.generate(
      8,
      (i) => ForwardCandidate(
        profile: Profile(
          id: 'u$i',
          displayName: 'User $i',
          rScore: 1,
          score: 50,
        ),
      ),
    );

    cubit.emit(
      ForwardState(
        beaconId: 'b1',
        beacon: beacon,
        candidates: candidates,
        selectedIds: {'u0'},
        recipientReasons: {
          'u0': ['transport'],
        },
        candidatesLoad: const ForwardCandidatesReady(),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        theme: TenturaTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(size: Size(360, 600)),
          child: MultiBlocProvider(
            providers: [
              BlocProvider<ForwardCubit>.value(value: cubit),
              BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
            ],
            child: const ForwardBeaconPage(beaconId: 'b1'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Label icon for u0 is visible and reasons are set (u0 is selected + has reasons).
    expect(find.byIcon(Icons.label_outline), findsOneWidget);

    // Scroll down past u0.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
    await tester.pumpAndSettle();

    // Scroll back up.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 400));
    await tester.pumpAndSettle();

    // u0's label icon still present — cubit state preserved the reasons.
    expect(find.byIcon(Icons.label_outline), findsOneWidget);
    expect(cubit.state.recipientReasons['u0'], equals(['transport']));
  });

  testWidgets('collapsed composer has no proactive add-shared-note button', (
    tester,
  ) async {
    _registerInvitationRepository();
    _registerUiEffectPort();

    final cubit = ForwardCubit(
      beaconId: 'b1',
      debugSkipInitialLoad: true,
      effects: FakeUiEffectPort(),
    );
    addTearDown(cubit.close);

    cubit.emit(
      const ForwardState(candidatesLoad: ForwardCandidatesEmpty()),
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        theme: TenturaTheme.light(),
        home: MultiBlocProvider(
          providers: [
            BlocProvider<ForwardCubit>.value(value: cubit),
            BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
          ],
          child: const ForwardBeaconPage(beaconId: 'b1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Removed: the reminder sheet shown on Forward-press already nudges
    // the user to add a shared note, so there's no proactive affordance.
    expect(find.text('add shared note'), findsNothing);
  });

  testWidgets(
    'invite-new-person bar shows on both scope tabs, above the tab content',
    (tester) async {
      _registerInvitationRepository();
      _registerUiEffectPort();

      final cubit = _forwardCubitWithBeacon();
      addTearDown(cubit.close);

      await _pumpForwardPage(tester, cubit: cubit);

      expect(find.text('invite new person'), findsOneWidget);

      await tester.tap(find.textContaining('Already involved'));
      await tester.pumpAndSettle();

      expect(find.text('invite new person'), findsOneWidget);
    },
  );

  testWidgets(
    'invite bar stays pinned while the rest of the top sections scroll away; '
    'switching tabs resets the scroll back to the top',
    (tester) async {
      _registerInvitationRepository();
      _registerUiEffectPort();

      final candidates = List.generate(
        10,
        (i) => ForwardCandidate(
          profile: Profile(
            id: 'u$i',
            displayName: 'User $i',
            rScore: 1,
            score: 50,
          ),
        ),
      );

      final cubit = _forwardCubitWithBeacon();
      cubit.emit(cubit.state.copyWith(candidates: candidates));
      addTearDown(cubit.close);

      await _pumpForwardPage(
        tester,
        cubit: cubit,
        size: const Size(360, 600),
      );

      expect(find.text('invite new person'), findsOneWidget);

      // A single drag on the outer scroll view carries recipient rows off
      // while the invite bar — pinned like the scope tab bar below it —
      // stays put, unlike the old fixed-header-plus-inner-list split.
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
      await tester.pumpAndSettle();

      expect(find.text('invite new person'), findsOneWidget);

      // Switching tabs resets the scroll position back to 0; the invite
      // bar is still reachable there too.
      await tester.tap(find.textContaining('Already involved'));
      await tester.pumpAndSettle();

      expect(find.text('invite new person'), findsOneWidget);
    },
  );

  testWidgets('compact hints replace inline explainer paragraphs', (
    tester,
  ) async {
    _registerInvitationRepository();
    _registerUiEffectPort();

    const reachExplainer =
        'These are people you can reach. They get access only after they accept your forward.';
    const aheadHint =
        'After selecting someone, you can explain why you\'re forwarding and add a personal note.';

    final cubit = _forwardCubitWithBeacon();
    addTearDown(cubit.close);

    await _pumpForwardPage(tester, cubit: cubit);

    expect(find.text(reachExplainer), findsNothing);
    expect(find.text(aheadHint), findsNothing);
  });

  testWidgets('invite bar swaps to clear-selection once a recipient is picked', (
    tester,
  ) async {
    _registerInvitationRepository();
    _registerUiEffectPort();

    final cubit = _forwardCubitWithBeacon();
    addTearDown(cubit.close);

    await _pumpForwardPage(tester, cubit: cubit);
    expect(find.text('invite new person'), findsOneWidget);
    expect(find.text('clear selection'), findsNothing);

    cubit.toggleSelection('u1');
    await tester.pumpAndSettle();

    expect(find.text('invite new person'), findsNothing);
    expect(find.text('clear selection'), findsOneWidget);

    await tester.tap(find.text('clear selection'));
    await tester.pumpAndSettle();

    expect(find.text('invite new person'), findsOneWidget);
    expect(find.text('clear selection'), findsNothing);
    expect(cubit.state.selectedIds, isEmpty);
  });

  testWidgets('forward page layout has no overflow at compact widths', (
    tester,
  ) async {
    _registerInvitationRepository();
    _registerUiEffectPort();

    final cubit = _forwardCubitWithBeacon(
      needs: {'transport', 'tools', 'housing'},
    );
    addTearDown(cubit.close);

    for (final size in [
      const Size(320, 640),
      const Size(360, 780),
      const Size(720, 900),
    ]) {
      await _pumpForwardPage(tester, cubit: cubit, size: size);
      expect(tester.takeException(), isNull);
    }
  });
}
