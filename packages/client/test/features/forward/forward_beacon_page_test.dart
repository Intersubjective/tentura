import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/forward/domain/entity/forward_candidate.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/forward/ui/screen/forward_beacon_screen.dart';
import 'package:tentura/features/forward/ui/widget/compact_beacon_context_strip.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

class _MockProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState();

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

void main() {
  testWidgets('compact forward page has no chip filters; shows scope row', (
    tester,
  ) async {
    final cubit = ForwardCubit(
      beaconId: 'b1',
      debugSkipInitialLoad: true,
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
          title: 'Clara',
          rScore: 1,
          score: 70,
        ),
      ),
      const ForwardCandidate(
        profile: Profile(
          id: 'u2',
          title: 'Zed',
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
    expect(find.textContaining('unseen'), findsWidgets);
    expect(find.textContaining('involved'), findsWidgets);
    expect(find.byType(CompactBeaconContextStrip), findsOneWidget);
  });

  testWidgets('search icon opens full-screen overlay with search field', (
    tester,
  ) async {
    final cubit = ForwardCubit(
      beaconId: 'b1',
      debugSkipInitialLoad: true,
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
    final cubit = ForwardCubit(
      beaconId: 'b1',
      debugSkipInitialLoad: true,
    );
    addTearDown(cubit.close);

    final beacon = Beacon.empty.copyWith(id: 'b1', title: 'Test');

    final candidates = List.generate(
      8,
      (i) => ForwardCandidate(
        profile: Profile(id: 'u$i', title: 'User $i', rScore: 1, score: 50),
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
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();

    // Scroll back up.
    await tester.drag(find.byType(ListView), const Offset(0, 400));
    await tester.pumpAndSettle();

    // u0's label icon still present — cubit state preserved the reasons.
    expect(find.byIcon(Icons.label_outline), findsOneWidget);
    expect(cubit.state.recipientReasons['u0'], equals(['transport']));
  });

  testWidgets('add shared note expands textarea', (tester) async {
    final cubit = ForwardCubit(
      beaconId: 'b1',
      debugSkipInitialLoad: true,
    );
    addTearDown(cubit.close);

    cubit.emit(const ForwardState());

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

    expect(find.text('add shared note'), findsOneWidget);
    await tester.tap(find.text('add shared note'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsWidgets);
  });
}
