import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/invitation_entity.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/forward/domain/entity/forward_candidate.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/forward/ui/widget/forward_recipient_picker.dart';
import 'package:tentura/features/invitation/data/repository/invitation_repository.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/self_aware_profile_avatar.dart';

import 'package:tentura/ui/test_ids.dart';

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
  Future<InvitationsFetchResult> fetchMine({
    int pendingOffset = 0,
    int pendingLimit = 0,
    int acceptedOffset = 0,
    int acceptedLimit = 0,
  }) async => (
    pending: <InvitationEntity>[],
    accepted: <InvitationEntity>[],
    pendingCount: 0,
  );

  @override
  Future<InvitationFetchByIdResult?> fetchById(String id) async => null;

  @override
  Future<InvitationEntity> create({
    required String addresseeName,
    String? beaconId,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> deleteById(String id) async {}

  @override
  Future<void> dispose() async {}
}

void main() {
  setUp(() {
    if (!GetIt.I.isRegistered<UiEffectPort>()) {
      GetIt.I.registerSingleton<UiEffectPort>(FakeUiEffectPort());
    }
    if (!GetIt.I.isRegistered<InvitationRepository>()) {
      GetIt.I.registerSingleton<InvitationRepository>(
        _FakeInvitationRepository(),
      );
    }
  });

  tearDown(() async {
    if (GetIt.I.isRegistered<InvitationRepository>()) {
      await GetIt.I.unregister<InvitationRepository>();
    }
    if (GetIt.I.isRegistered<UiEffectPort>()) {
      await GetIt.I.unregister<UiEffectPort>();
    }
  });
  testWidgets('embedded ForwardRecipientPicker hides standalone send CTA', (
    tester,
  ) async {
    final cubit = ForwardCubit(
      beaconId: 'draft-1',
      debugSkipInitialLoad: true,
      embedded: true,
      effects: FakeUiEffectPort(),
    );
    cubit.emit(
      ForwardState(
        beaconId: 'draft-1',
        beacon: Beacon.empty.copyWith(id: 'draft-1', title: 'Draft'),
        candidates: const [
          ForwardCandidate(
            profile: Profile(
              id: 'u1',
              displayName: 'Alex',
              score: 10,
              rScore: 1,
            ),
          ),
        ],
        selectedIds: {'u1'},
        candidatesLoad: const ForwardCandidatesReady(),
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
          child: const Scaffold(
            body: ForwardRecipientPicker(
              beaconId: 'draft-1',
              embedded: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Forward to 1'), findsNothing);
    expect(find.byIcon(Icons.close), findsNothing);
  });

  testWidgets(
    'recipient avatars hide value-score arcs and keep the contact badge',
    (tester) async {
      final cubit = ForwardCubit(
        beaconId: 'draft-1',
        debugSkipInitialLoad: true,
        embedded: true,
        effects: FakeUiEffectPort(),
      );
      cubit.emit(
        ForwardState(
          beaconId: 'draft-1',
          beacon: Beacon.empty.copyWith(id: 'draft-1', title: 'Draft'),
          candidates: const [
            ForwardCandidate(
              profile: Profile(
                id: 'u1',
                displayName: 'Alex',
                score: 10,
                rScore: 1,
                myVote: 1,
                subjectExplicitlyTrustsViewer: true,
              ),
            ),
          ],
          selectedIds: {'u1'},
          candidatesLoad: const ForwardCandidatesReady(),
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
            child: const Scaffold(
              body: ForwardRecipientPicker(
                beaconId: 'draft-1',
                embedded: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final avatar = tester.widget<SelfAwareAvatar>(
        find.byType(SelfAwareAvatar),
      );
      expect(avatar.withRating, isFalse);
      expect(avatar.withContactBadge, isTrue);
    },
  );

  testWidgets(
    'embedded ForwardRecipientPicker enables send when onSendPressed provided',
    (tester) async {
      final cubit = ForwardCubit(
        beaconId: 'draft-1',
        debugSkipInitialLoad: true,
        embedded: true,
        effects: FakeUiEffectPort(),
      );
      cubit.emit(
        ForwardState(
          beaconId: 'draft-1',
          beacon: Beacon.empty.copyWith(id: 'draft-1', title: 'Draft'),
          candidates: const [
            ForwardCandidate(
              profile: Profile(id: 'u1', displayName: 'Alex'),
            ),
          ],
          selectedIds: {'u1'},
          candidatesLoad: const ForwardCandidatesReady(),
        ),
      );
      var sendPressed = false;

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
            child: Scaffold(
              body: ForwardRecipientPicker(
                beaconId: 'draft-1',
                embedded: true,
                onSendPressed: () => sendPressed = true,
                sendEnabled: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Forward to 1'), findsOneWidget);
      cubit.skipPersonalNote('u1');
      await tester.tap(find.text('Forward to 1'));
      await tester.pumpAndSettle();
      expect(sendPressed, isTrue);
    },
  );

  testWidgets(
    'embedded ForwardRecipientPicker keeps send disabled when sendEnabled is false',
    (tester) async {
      final cubit = ForwardCubit(
        beaconId: 'draft-1',
        debugSkipInitialLoad: true,
        embedded: true,
        effects: FakeUiEffectPort(),
      );
      cubit.emit(
        ForwardState(
          beaconId: 'draft-1',
          beacon: Beacon.empty.copyWith(id: 'draft-1', title: 'Draft'),
          candidates: const [
            ForwardCandidate(
              profile: Profile(id: 'u1', displayName: 'Alex'),
            ),
          ],
          selectedIds: {'u1'},
          candidatesLoad: const ForwardCandidatesReady(),
        ),
      );
      var sendPressed = false;

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
            child: Scaffold(
              body: ForwardRecipientPicker(
                beaconId: 'draft-1',
                embedded: true,
                onSendPressed: () => sendPressed = true,
                sendEnabled: false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Select recipients'), findsOneWidget);
      expect(find.text('Forward to 1'), findsNothing);
      await tester.tap(find.text('Select recipients'));
      await tester.pump();
      expect(sendPressed, isFalse);
    },
  );

  testWidgets(
    'ForwardRecipientPicker shows a spinner while candidatesLoad is loading',
    (tester) async {
      final cubit = ForwardCubit(
        beaconId: 'draft-1',
        debugSkipInitialLoad: true,
        embedded: true,
        effects: FakeUiEffectPort(),
      );
      cubit.emit(
        const ForwardState(
          beaconId: 'draft-1',
          candidatesLoad: ForwardCandidatesLoading(),
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
            child: const Scaffold(
              body: ForwardRecipientPicker(
                beaconId: 'draft-1',
                embedded: true,
              ),
            ),
          ),
        ),
      );
      // Deliberately bounded pumps, not pumpAndSettle: the adaptive spinner
      // animates indefinitely and would never let pumpAndSettle return.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('No reachable contacts'), findsNothing);
    },
  );

  testWidgets(
    'ForwardRecipientPicker shows an error panel with retry on candidatesLoad error',
    (tester) async {
      final cubit = ForwardCubit(
        beaconId: 'draft-1',
        debugSkipInitialLoad: true,
        embedded: true,
        effects: FakeUiEffectPort(),
      );
      cubit.emit(
        ForwardState(
          beaconId: 'draft-1',
          candidatesLoad: ForwardCandidatesError(Exception('network down')),
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
            child: const Scaffold(
              body: ForwardRecipientPicker(
                beaconId: 'draft-1',
                embedded: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text("Couldn't load"), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('No reachable contacts'), findsNothing);

      // Tapping retry must not throw even though this harness has no
      // backing ForwardCase to actually reload from.
      await tester.tap(find.text('Try again'));
      await tester.pump();
    },
  );

  testWidgets(
    'ForwardRecipientPicker shows the empty-contacts message only once '
    'candidatesLoad is genuinely empty',
    (tester) async {
      final cubit = ForwardCubit(
        beaconId: 'draft-1',
        debugSkipInitialLoad: true,
        embedded: true,
        effects: FakeUiEffectPort(),
      );
      cubit.emit(
        const ForwardState(
          beaconId: 'draft-1',
          candidatesLoad: ForwardCandidatesEmpty(),
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
            child: const Scaffold(
              body: ForwardRecipientPicker(
                beaconId: 'draft-1',
                embedded: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No reachable contacts'), findsOneWidget);
      expect(find.text("Couldn't load"), findsNothing);
    },
  );

  Future<void> pumpPicker(
    WidgetTester tester, {
    required ForwardCubit cubit,
    bool embedded = false,
    VoidCallback? onSendPressed,
    bool sendEnabled = false,
  }) async {
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
          child: Scaffold(
            body: ForwardRecipientPicker(
              beaconId: 'draft-1',
              embedded: embedded,
              onSendPressed: onSendPressed,
              sendEnabled: sendEnabled,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('skipping personal note marks recipient in cubit skip set', (
    tester,
  ) async {
    final cubit = ForwardCubit(
      beaconId: 'draft-1',
      debugSkipInitialLoad: true,
      embedded: true,
      effects: FakeUiEffectPort(),
    );
    cubit.emit(
      ForwardState(
        beaconId: 'draft-1',
        beacon: Beacon.empty.copyWith(id: 'draft-1', title: 'Draft'),
        candidates: const [
          ForwardCandidate(
            profile: Profile(
              id: 'u1',
              displayName: 'Alex',
              score: 10,
              rScore: 1,
            ),
          ),
        ],
        selectedIds: {'u1'},
        candidatesLoad: const ForwardCandidatesReady(),
      ),
    );

    await pumpPicker(tester, cubit: cubit, embedded: true);

    // Note field opens automatically on selection (no "add note" tap).
    expect(find.byType(TextField), findsWidgets);
    expect(find.byTooltip('add personalized note'), findsNothing);
    expect(find.byTooltip('Skip personal note'), findsOneWidget);
    await tester.tap(find.byTooltip('Skip personal note'));
    await tester.pumpAndSettle();

    expect(cubit.state.skippedPersonalNoteIds, {'u1'});
    expect(find.byTooltip('Add a personal note'), findsOneWidget);
  });

  testWidgets('submit after skip proceeds without uncovered sheet', (
    tester,
  ) async {
    final cubit = ForwardCubit(
      beaconId: 'draft-1',
      debugSkipInitialLoad: true,
      embedded: true,
      effects: FakeUiEffectPort(),
    );
    cubit.emit(
      ForwardState(
        beaconId: 'draft-1',
        beacon: Beacon.empty.copyWith(id: 'draft-1', title: 'Draft'),
        candidates: const [
          ForwardCandidate(
            profile: Profile(
              id: 'u1',
              displayName: 'Alex',
              score: 10,
              rScore: 1,
            ),
          ),
        ],
        selectedIds: {'u1'},
        skippedPersonalNoteIds: {'u1'},
        perRecipientNotes: {'u1': 'leftover typed note'},
        candidatesLoad: const ForwardCandidatesReady(),
      ),
    );
    var sendPressed = false;

    await pumpPicker(
      tester,
      cubit: cubit,
      embedded: true,
      onSendPressed: () => sendPressed = true,
      sendEnabled: true,
    );

    await tester.tap(find.text('Forward to 1'));
    await tester.pumpAndSettle();

    expect(sendPressed, isTrue);
    expect(find.text('No personal note yet'), findsNothing);
    expect(cubit.state.skippedPersonalNoteIds, {'u1'});
  });

  testWidgets('submit with uncovered recipients shows shared-note sheet', (
    tester,
  ) async {
    final cubit = ForwardCubit(
      beaconId: 'draft-1',
      debugSkipInitialLoad: true,
      effects: FakeUiEffectPort(),
    );
    cubit.emit(
      ForwardState(
        beaconId: 'draft-1',
        beacon: Beacon.empty.copyWith(id: 'b1', title: 'Open request'),
        candidates: const [
          ForwardCandidate(
            profile: Profile(
              id: 'u1',
              displayName: 'Alex',
              score: 10,
              rScore: 1,
            ),
          ),
          ForwardCandidate(
            profile: Profile(
              id: 'u2',
              displayName: 'Blake',
              score: 10,
              rScore: 1,
            ),
          ),
        ],
        selectedIds: {'u1', 'u2'},
        candidatesLoad: const ForwardCandidatesReady(),
      ),
    );

    await pumpPicker(tester, cubit: cubit);
    await tester.tap(find.text('Forward to 2'));
    await tester.pumpAndSettle();

    expect(find.text('No personal note yet'), findsOneWidget);
    expect(find.text('Send without a shared note'), findsOneWidget);
  });
}
