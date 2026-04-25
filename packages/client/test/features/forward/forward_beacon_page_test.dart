import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/forward/domain/entity/forward_candidate.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/forward/ui/bloc/forward_state.dart';
import 'package:tentura/features/forward/ui/screen/forward_beacon_screen.dart';
import 'package:tentura/features/forward/ui/widget/compact_beacon_context_strip.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/state_base.dart';
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
      createdAt: DateTime.utc(2025, 5, 1),
      updatedAt: DateTime.utc(2025, 5, 1),
      id: 'aaaaaaaa-bbbb-cccc-dddd-1234567890ab',
      title: 'Test beacon',
      context: 'General',
      lifecycle: BeaconLifecycle.open,
      startAt: DateTime.utc(2025, 5, 12),
      endAt: DateTime.utc(2025, 5, 19),
    );

    final candidates = [
      ForwardCandidate(
        profile: const Profile(
          id: 'u1',
          title: 'Clara',
          rScore: 1,
          score: 70,
        ),
      ),
      ForwardCandidate(
        profile: const Profile(
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
        status: const StateIsSuccess(),
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
            child: const ForwardBeaconPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(FilterChip), findsNothing);
    expect(find.text('BEST NEXT'), findsNothing);
    expect(find.text('best'), findsWidgets);
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
      createdAt: DateTime.utc(2025, 5, 1),
      updatedAt: DateTime.utc(2025, 5, 1),
      id: 'id',
      title: 'T',
      lifecycle: BeaconLifecycle.open,
    );

    cubit.emit(
      ForwardState(
        beaconId: 'b1',
        beacon: beacon,
        candidates: const [],
        status: const StateIsSuccess(),
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
            child: const ForwardBeaconPage(),
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

  testWidgets('add shared note expands textarea', (tester) async {
    final cubit = ForwardCubit(
      beaconId: 'b1',
      debugSkipInitialLoad: true,
    );
    addTearDown(cubit.close);

    cubit.emit(
      const ForwardState(
        status: StateIsSuccess(),
      ),
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
          child: const ForwardBeaconPage(),
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
