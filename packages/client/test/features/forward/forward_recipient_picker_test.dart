import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/capability/forward_band_row.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/invitation_entity.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/forward/domain/entity/candidate_involvement.dart';
import 'package:tentura/features/forward/domain/entity/forward_candidate.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/forward/ui/widget/forward_band_strip.dart';
import 'package:tentura/features/forward/ui/widget/forward_recipient_picker.dart';
import 'package:tentura/features/forward/ui/widget/per_recipient_note_input.dart';
import 'package:tentura/features/invitation/data/repository/invitation_repository.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/self_aware_profile_avatar.dart';

import 'package:tentura/ui/test_ids.dart';

import '../../support/phone_surface.dart';
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
  }) => throw UnimplementedError();

  @override
  Future<void> deleteById(String id) async {}

  @override
  Future<void> dispose() async {}
}

ForwardCubit _alexSelectedPickerCubit() {
  return ForwardCubit(
    beaconId: 'draft-1',
    debugSkipInitialLoad: true,
    embedded: true,
    effects: FakeUiEffectPort(),
  )..emit(
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
}

void _expectPersonalNoteEditorPrimaryFocus(WidgetTester tester) {
  final editor = tester.widget<EditableText>(
    find.descendant(
      of: find.byType(PerRecipientNoteInput),
      matching: find.byType(EditableText),
    ),
  );
  expect(FocusManager.instance.primaryFocus, same(editor.focusNode));
  expect(tester.testTextInput.hasAnyClients, isTrue);
}

Future<void> _pumpPickerSurface(
  WidgetTester tester, {
  required ForwardCubit cubit,
  required Locale locale,
  required Size surfaceSize,
  bool embedded = true,
}) async {
  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
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
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapAddNoteAndPumpForFocus(
  WidgetTester tester,
  Finder addNote,
) async {
  await tester.tap(addNote);
  await tester.pump();
  await tester.pump();
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
  for (final language in ['en', 'ru']) {
    testWidgets(
      'stable recipient checkbox selects and enables send ($language)',
      (tester) async {
        final cubit = ForwardCubit(
          beaconId: 'draft-1',
          debugSkipInitialLoad: true,
          embedded: true,
          effects: FakeUiEffectPort(),
        );
        addTearDown(cubit.close);
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
            candidatesLoad: const ForwardCandidatesReady(),
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(language),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            theme: TenturaTheme.light(),
            home: MultiBlocProvider(
              providers: [
                BlocProvider<ForwardCubit>.value(value: cubit),
                BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
              ],
              child: Scaffold(
                body: BlocBuilder<ForwardCubit, ForwardState>(
                  builder: (context, state) => ForwardRecipientPicker(
                    beaconId: 'draft-1',
                    embedded: true,
                    onSendPressed: () {},
                    sendEnabled: state.selectedIds.isNotEmpty,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final submit = find.byKey(TestIds.key(TestIds.forwardSubmit));
        expect(tester.widget<OutlinedButton>(submit).onPressed, isNull);
        await tester.tap(
          find.byKey(TestIds.key(TestIds.forwardRecipientCheckbox('u1'))),
        );
        await tester.pumpAndSettle();
        expect(cubit.state.selectedIds, {'u1'});
        expect(tester.widget<OutlinedButton>(submit).onPressed, isNotNull);
      },
    );
  }

  Future<void> pumpSingleCandidate(
    WidgetTester tester, {
    required String displayName,
  }) async {
    final cubit = ForwardCubit(
      beaconId: 'draft-1',
      debugSkipInitialLoad: true,
      embedded: true,
      effects: FakeUiEffectPort(),
    );
    addTearDown(cubit.close);
    cubit.emit(
      ForwardState(
        beaconId: 'draft-1',
        beacon: Beacon.empty.copyWith(id: 'draft-1', title: 'Draft'),
        candidates: [
          ForwardCandidate(
            profile: Profile(
              id: 'u1',
              displayName: displayName,
              score: 10,
              rScore: 1,
            ),
          ),
        ],
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
          child: Scaffold(
            body: BlocBuilder<ForwardCubit, ForwardState>(
              builder: (context, state) => ForwardRecipientPicker(
                beaconId: 'draft-1',
                embedded: true,
                onSendPressed: () {},
                sendEnabled: state.selectedIds.isNotEmpty,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('recipient checkbox is named after the person (B071)', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpSingleCandidate(tester, displayName: 'Alex');

    final checkbox = find.byKey(
      TestIds.key(TestIds.forwardRecipientCheckbox('u1')),
    );
    expect(
      tester.getSemantics(checkbox),
      isSemantics(
        label: 'Alex',
        hasCheckedState: true,
        isChecked: false,
        hasTapAction: true,
        onTapHint: 'Select',
      ),
    );

    await tester.tap(checkbox);
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(checkbox),
      isSemantics(label: 'Alex', isChecked: true, onTapHint: 'Remove'),
    );
    handle.dispose();
  });

  testWidgets('nameless recipient checkbox still has a label (B071)', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    // Fails on the base: the label was the empty name, so the box read as
    // a bare "checkbox, not checked".
    await pumpSingleCandidate(tester, displayName: '');

    expect(
      tester.getSemantics(
        find.byKey(TestIds.key(TestIds.forwardRecipientCheckbox('u1'))),
      ),
      isSemantics(label: 'Select', hasCheckedState: true, isChecked: false),
    );
    handle.dispose();
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
    expect(find.byTooltip('Close'), findsNothing);
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

      // The button keeps its label while disabled (#720).
      expect(find.text('Forward to 1'), findsOneWidget);
      await tester.tap(find.text('Forward to 1'));
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
      expect(find.text('No one to send to yet'), findsNothing);
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
      expect(find.text('No one to send to yet'), findsNothing);

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

      // #252: what is missing, why trust matters, and a way out.
      expect(find.text('No one to send to yet'), findsOneWidget);
      expect(
        find.text(
          'People you trust, and who trust you back, widen whom you can '
          'see and send to.',
        ),
        findsOneWidget,
      );
      // A create-flow draft that cannot mint an invite does not offer one:
      // leaving for People › Invitations would abandon the draft.
      expect(find.byKey(TenturaEmptyState.actionKey), findsNothing);
      expect(find.text("Couldn't load"), findsNothing);
    },
  );

  testWidgets(
    'the genuinely empty picker offers an invite where it can mint one',
    (tester) async {
      final cubit = ForwardCubit(
        beaconId: 'b1',
        debugSkipInitialLoad: true,
        embedded: true,
        effects: FakeUiEffectPort(),
      );
      addTearDown(cubit.close);
      cubit.emit(
        ForwardState(
          beaconId: 'b1',
          beacon: Beacon.empty.copyWith(id: 'b1', viewerCanForward: true),
          candidatesLoad: const ForwardCandidatesEmpty(),
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
              body: ForwardRecipientPicker(beaconId: 'b1', embedded: true),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No one to send to yet'), findsOneWidget);
      expect(find.byKey(TenturaEmptyState.actionKey), findsOneWidget);
      expect(find.text('Invite someone you know'), findsOneWidget);
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

  group('#893 + Note focuses the note field for typing', () {
    testWidgets('desktop EN: open, type, blur, reopen from preview', (
      tester,
    ) async {
      final cubit = _alexSelectedPickerCubit();
      addTearDown(cubit.close);
      await _pumpPickerSurface(
        tester,
        cubit: cubit,
        locale: const Locale('en'),
        surfaceSize: const Size(1280, 800),
      );

      expect(find.byType(TextField), findsNothing);
      await _tapAddNoteAndPumpForFocus(
        tester,
        find.byTooltip('Add a note for Alex'),
      );
      expect(find.byType(TextField), findsOneWidget);
      _expectPersonalNoteEditorPrimaryFocus(tester);

      const typed = 'hello without enterText';
      tester.testTextInput.enterText(typed);
      await tester.pump();
      expect(cubit.state.perRecipientNotes['u1'], typed);

      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(find.text(typed), findsOneWidget);

      await _tapAddNoteAndPumpForFocus(tester, find.text(typed));
      _expectPersonalNoteEditorPrimaryFocus(tester);
      tester.testTextInput.enterText('$typed more');
      await tester.pump();
      expect(cubit.state.perRecipientNotes['u1'], '$typed more');
    });

    testWidgets('phone RU: open, type, blur collapses field', (tester) async {
      final cubit = _alexSelectedPickerCubit();
      addTearDown(cubit.close);
      cubit.emit(
        cubit.state.copyWith(
          candidates: const [
            ForwardCandidate(
              profile: Profile(
                id: 'u1',
                displayName: 'Алекс',
                score: 10,
                rScore: 1,
              ),
            ),
          ],
        ),
      );
      await _pumpPickerSurface(
        tester,
        cubit: cubit,
        locale: const Locale('ru'),
        surfaceSize: kPhoneSurface,
      );

      await _tapAddNoteAndPumpForFocus(
        tester,
        find.byTooltip('Добавить заметку для Алекс'),
      );
      _expectPersonalNoteEditorPrimaryFocus(tester);
      tester.testTextInput.enterText('заметка');
      await tester.pump();
      expect(cubit.state.perRecipientNotes['u1'], 'заметка');

      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(find.text('заметка'), findsOneWidget);
    });

    testWidgets('band strip + Note focuses editor at desktop width', (
      tester,
    ) async {
      final cubit = _alexSelectedPickerCubit();
      addTearDown(cubit.close);
      cubit.emit(
        cubit.state.copyWith(band: const [ForwardBandRow(userId: 'u1')]),
      );
      await _pumpPickerSurface(
        tester,
        cubit: cubit,
        locale: const Locale('en'),
        surfaceSize: const Size(1280, 800),
      );

      expect(find.byType(ForwardBandStrip), findsOneWidget);
      await _tapAddNoteAndPumpForFocus(
        tester,
        find.byTooltip('Add a note for Alex'),
      );
      _expectPersonalNoteEditorPrimaryFocus(tester);
      tester.testTextInput.enterText('band note');
      await tester.pump();
      expect(cubit.state.perRecipientNotes['u1'], 'band note');
    });

    testWidgets('band strip + Note focuses editor on phone RU', (tester) async {
      final cubit = _alexSelectedPickerCubit();
      addTearDown(cubit.close);
      cubit.emit(
        cubit.state.copyWith(
          candidates: const [
            ForwardCandidate(
              profile: Profile(
                id: 'u1',
                displayName: 'Алекс',
                score: 10,
                rScore: 1,
              ),
            ),
          ],
          band: const [ForwardBandRow(userId: 'u1')],
        ),
      );
      await _pumpPickerSurface(
        tester,
        cubit: cubit,
        locale: const Locale('ru'),
        surfaceSize: kPhoneSurface,
      );

      await _tapAddNoteAndPumpForFocus(
        tester,
        find.byTooltip('Добавить заметку для Алекс'),
      );
      _expectPersonalNoteEditorPrimaryFocus(tester);
    });

    testWidgets('keyboard Enter on + Note focuses the editor', (tester) async {
      final cubit = _alexSelectedPickerCubit();
      addTearDown(cubit.close);
      await _pumpPickerSurface(
        tester,
        cubit: cubit,
        locale: const Locale('en'),
        surfaceSize: const Size(1280, 800),
      );

      final noteControl = find.byTooltip('Add a note for Alex');
      Tristate focused() => tester
          .getSemantics(noteControl)
          .getSemanticsData()
          .flagsCollection
          .isFocused;

      for (var i = 0; i < 40 && focused() != Tristate.isTrue; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      expect(focused(), Tristate.isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump();
      _expectPersonalNoteEditorPrimaryFocus(tester);
      tester.testTextInput.enterText('from keyboard');
      await tester.pump();
      expect(cubit.state.perRecipientNotes['u1'], 'from keyboard');
    });
  });

  testWidgets('personal note opens from + Note control, not on tick', (
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

    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.byTooltip('Add a note for Alex'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('submit with one selected recipient proceeds without sheet', (
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
    expect(find.text('Shared note'), findsNothing);
  });

  testWidgets(
    '#669 one recipient without a personal note sends with no shared-note '
    'sheet',
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
              ),
            ),
          ],
          selectedIds: {'u1'},
          note: 'composer shared',
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

      expect(find.text('Shared note'), findsNothing);
      expect(
        find.text("Sent to anyone who doesn't have a personal note."),
        findsNothing,
      );
      expect(sendPressed, isTrue);
      // Whatever the composer already holds is left alone.
      expect(cubit.state.note, 'composer shared');
    },
  );

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
        note: 'already typed shared',
        candidatesLoad: const ForwardCandidatesReady(),
      ),
    );

    await pumpPicker(tester, cubit: cubit);
    await tester.tap(find.text('Forward to 2'));
    await tester.pumpAndSettle();

    expect(find.text('Shared note'), findsWidgets);
    expect(
      find.text("Sent to anyone who doesn't have a personal note."),
      findsWidgets,
    );
    expect(find.text('People without a personal note'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Send without a shared note'), findsNothing);
    expect(find.text('already typed shared'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Forward to 2'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Forward to 2'));
    await tester.pumpAndSettle();

    expect(cubit.state.note, 'already typed shared');
  });

  testWidgets(
    'uncovered sheet empty Forward clears shared note and skips',
    (tester) async {
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
          note: 'composer shared',
          candidatesLoad: const ForwardCandidatesReady(),
        ),
      );

      await pumpPicker(tester, cubit: cubit);
      await tester.tap(find.text('Forward to 2'));
      await tester.pumpAndSettle();

      expect(find.text('composer shared'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, '');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Forward to 2'));
      await tester.pumpAndSettle();

      expect(cubit.state.note, '');
    },
  );

  testWidgets(
    'uncovered sheet Cancel abandons without sending',
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
      var sendPressed = false;

      await pumpPicker(
        tester,
        cubit: cubit,
        embedded: true,
        onSendPressed: () => sendPressed = true,
        sendEnabled: true,
      );
      await tester.tap(find.text('Forward to 2'));
      await tester.pumpAndSettle();

      expect(find.text('Shared note'), findsWidgets);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(sendPressed, isFalse);
      expect(cubit.state.note, '');
    },
  );

  testWidgets(
    'recipient avatar on forward screen does not navigate on tap',
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
              ),
            ),
          ],
          selectedIds: const {},
          candidatesLoad: const ForwardCandidatesReady(),
        ),
      );

      await pumpPicker(tester, cubit: cubit, embedded: true);

      final avatarFinder = find.byType(SelfAwareAvatar);
      expect(avatarFinder, findsOneWidget);

      final avatar = tester.widget<SelfAwareAvatar>(avatarFinder);
      expect(avatar.onTap, isNull);
    },
  );

  testWidgets(
    'alreadyInvolved tab shows composer with enabled send for selection',
    (tester) async {
      final cubit = ForwardCubit(
        beaconId: 'b1',
        debugSkipInitialLoad: true,
        effects: FakeUiEffectPort(),
      );
      cubit.emit(
        ForwardState(
          beaconId: 'b1',
          beacon: Beacon.empty.copyWith(id: 'b1', title: 'Open request'),
          activeFilter: ForwardFilter.alreadyInvolved,
          candidates: const [
            ForwardCandidate(
              profile: Profile(
                id: 'u1',
                displayName: 'Alex',
                score: 10,
                rScore: 1,
              ),
              involvement: CandidateInvolvement.watching,
            ),
          ],
          selectedIds: {'u1'},
          candidatesLoad: const ForwardCandidatesReady(),
        ),
      );

      await pumpPicker(tester, cubit: cubit);

      expect(find.byKey(TestIds.key(TestIds.forwardSubmit)), findsOneWidget);
      expect(find.text('Forward to 1'), findsOneWidget);
      final button = tester.widget<OutlinedButton>(
        find.byKey(TestIds.key(TestIds.forwardSubmit)),
      );
      expect(button.onPressed, isNotNull);
    },
  );

  group('#440 recipient groups', () {
    ForwardCubit groupedCubit({
      ForwardFilter filter = ForwardFilter.unseen,
      List<ForwardCandidate> candidates = const [
        ForwardCandidate(
          profile: Profile(
            id: 'stranger',
            displayName: 'Kesi',
            score: 50,
            rScore: 1,
          ),
        ),
        ForwardCandidate(
          profile: Profile(
            id: 'friend',
            displayName: 'Vadim',
            score: 5,
            rScore: 1,
            myVote: 1,
          ),
        ),
      ],
    }) {
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
          candidates: candidates,
          activeFilter: filter,
          candidatesLoad: const ForwardCandidatesReady(),
        ),
      );
      return cubit;
    }

    testWidgets('direct contacts come first under their own header', (
      tester,
    ) async {
      final cubit = groupedCubit();
      addTearDown(cubit.close);
      await pumpPicker(tester, cubit: cubit, embedded: true);

      final direct = find.byKey(ForwardRecipientPicker.directSectionKey);
      final others = find.byKey(ForwardRecipientPicker.othersSectionKey);
      expect(direct, findsOneWidget);
      expect(others, findsOneWidget);
      expect(find.text('YOUR CONNECTIONS'), findsOneWidget);
      expect(find.text('OTHERS YOU CAN REACH'), findsOneWidget);
      expect(
        find.text(
          'Not your direct connections: you see each other through the '
          'trust network or a shared request.',
        ),
        findsOneWidget,
      );
      // Vadim (trusted, lower score) sits above the header for others, and
      // Kesi (higher score, not trusted) below it.
      final directY = tester.getTopLeft(direct).dy;
      final vadimY = tester.getTopLeft(find.text('Vadim')).dy;
      final othersY = tester.getTopLeft(others).dy;
      final kesiY = tester.getTopLeft(find.text('Kesi')).dy;
      expect(directY, lessThan(vadimY));
      expect(vadimY, lessThan(othersY));
      expect(othersY, lessThan(kesiY));
    });

    testWidgets('no direct contacts: only the others header', (tester) async {
      final cubit = groupedCubit(
        candidates: const [
          ForwardCandidate(
            profile: Profile(id: 'stranger', displayName: 'Kesi', score: 5),
          ),
        ],
      );
      addTearDown(cubit.close);
      await pumpPicker(tester, cubit: cubit, embedded: true);

      expect(
        find.byKey(ForwardRecipientPicker.directSectionKey),
        findsNothing,
      );
      expect(
        find.byKey(ForwardRecipientPicker.othersSectionKey),
        findsOneWidget,
      );
    });

    testWidgets('the involved scope stays one flat list', (tester) async {
      final cubit = groupedCubit(
        filter: ForwardFilter.alreadyInvolved,
        candidates: const [
          ForwardCandidate(
            profile: Profile(id: 'friend', displayName: 'Vadim', myVote: 1),
            involvement: CandidateInvolvement.forwardedByMe,
          ),
        ],
      );
      addTearDown(cubit.close);
      await pumpPicker(tester, cubit: cubit, embedded: true);

      expect(find.text('Vadim'), findsOneWidget);
      expect(
        find.byKey(ForwardRecipientPicker.directSectionKey),
        findsNothing,
      );
      expect(
        find.byKey(ForwardRecipientPicker.othersSectionKey),
        findsNothing,
      );
    });

    testWidgets('a band holding the only unseen person is not an empty '
        'picker (#252)', (tester) async {
      final cubit = groupedCubit(
        candidates: const [
          ForwardCandidate(
            profile: Profile(id: 'u1', displayName: 'Alex', score: 3),
          ),
        ],
      );
      addTearDown(cubit.close);
      cubit.emit(
        cubit.state.copyWith(band: const [ForwardBandRow(userId: 'u1')]),
      );
      await pumpPicker(tester, cubit: cubit, embedded: true);

      expect(find.byType(ForwardBandStrip), findsOneWidget);
      expect(
        find.text('Everyone you can send to is already involved.'),
        findsNothing,
      );
      expect(find.text('No one to send to yet'), findsNothing);
    });

    testWidgets('an empty «Not yet seen» tab says everyone is involved, not '
        '"no contacts" (#252)', (tester) async {
      final cubit = groupedCubit(
        candidates: const [
          ForwardCandidate(
            profile: Profile(id: 'friend', displayName: 'Vadim', myVote: 1),
            involvement: CandidateInvolvement.forwardedByMe,
          ),
        ],
      );
      addTearDown(cubit.close);
      await pumpPicker(tester, cubit: cubit, embedded: true);

      expect(
        find.text('Everyone you can send to is already involved.'),
        findsOneWidget,
      );
      expect(find.text('No one to send to yet'), findsNothing);
    });
  });
}
