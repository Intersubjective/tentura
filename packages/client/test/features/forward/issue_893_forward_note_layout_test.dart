import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/forward/domain/entity/forward_candidate.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/forward/ui/widget/forward_recipient_picker.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import 'package:get_it/get_it.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import '../../support/phone_surface.dart';

class _MockProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState();

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

Future<void> _pumpEnPicker(
  WidgetTester tester, {
  required ForwardCubit cubit,
  Size surfaceSize = const Size(1280, 800),
  VoidCallback? onSendPressed,
  bool sendEnabled = false,
}) async {
  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));
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
            sendEnabled: sendEnabled,
            onSendPressed: onSendPressed,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpRuPicker(
  WidgetTester tester, {
  required ForwardCubit cubit,
  bool embedded = true,
}) async {
  await usePhoneSurface(tester);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ru'),
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

ForwardCubit _cubitWithCandidates(List<ForwardCandidate> candidates) {
  return ForwardCubit(
    beaconId: 'draft-1',
    debugSkipInitialLoad: true,
    embedded: true,
    effects: FakeUiEffectPort(),
  )..emit(
    ForwardState(
      beaconId: 'draft-1',
      beacon: Beacon.empty.copyWith(id: 'draft-1', title: 'Draft'),
      candidates: candidates,
      candidatesLoad: const ForwardCandidatesReady(),
    ),
  );
}

double _rowTop(WidgetTester tester, String userId) {
  final box = tester.renderObject<RenderBox>(
    find.byKey(TestIds.key(TestIds.forwardRecipient(userId))),
  );
  return box.localToGlobal(Offset.zero).dy;
}

void main() {
  setUp(() {
    if (!GetIt.I.isRegistered<UiEffectPort>()) {
      GetIt.I.registerSingleton<UiEffectPort>(FakeUiEffectPort());
    }
  });

  testWidgets('ticking five recipients in a row does not shift row offsets', (
    tester,
  ) async {
    final candidates = List.generate(
      5,
      (i) => ForwardCandidate(
        profile: Profile(
          id: 'u$i',
          displayName: 'Person $i',
          score: (10 - i).toDouble(),
          rScore: 1,
        ),
      ),
    );
    final cubit = _cubitWithCandidates(candidates);
    addTearDown(cubit.close);
    await _pumpRuPicker(tester, cubit: cubit);

    final baselineGaps = <String, double>{};
    for (var i = 0; i < candidates.length - 1; i++) {
      baselineGaps['${candidates[i].id}-${candidates[i + 1].id}'] =
          _rowTop(tester, candidates[i + 1].id) -
          _rowTop(tester, candidates[i].id);
    }

    for (var i = 0; i < candidates.length; i++) {
      await tester.tap(
        find.byKey(
          TestIds.key(TestIds.forwardRecipientCheckbox(candidates[i].id)),
        ),
      );
      await tester.pumpAndSettle();
      for (var j = 0; j < candidates.length - 1; j++) {
        final key = '${candidates[j].id}-${candidates[j + 1].id}';
        final gap =
            _rowTop(tester, candidates[j + 1].id) -
            _rowTop(tester, candidates[j].id);
        expect(
          gap,
          closeTo(baselineGaps[key]!, 0.5),
          reason: 'gap $key changed after tick $i',
        );
      }
    }
  });

  testWidgets(
    '+ Note → type → blur → preview keeps note in state',
    (tester) async {
      final cubit = _cubitWithCandidates(const [
        ForwardCandidate(
          profile: Profile(
            id: 'u1',
            displayName: 'Alex',
            score: 10,
            rScore: 1,
          ),
        ),
      ]);
      addTearDown(cubit.close);
      cubit.emit(cubit.state.copyWith(selectedIds: {'u1'}));
      await usePhoneSurface(tester);
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

      await tester.tap(find.byTooltip('Add a note for Alex'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'private hello');
      await tester.pump();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();

      expect(find.text('private hello'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(cubit.state.perRecipientNotes['u1'], 'private hello');
    },
  );

  testWidgets(
    'RU phone: untick and re-tick restores collapsed note preview',
    (tester) async {
      final cubit = _cubitWithCandidates(const [
        ForwardCandidate(
          profile: Profile(
            id: 'u1',
            displayName: 'Алекс',
            score: 10,
            rScore: 1,
          ),
        ),
      ]);
      addTearDown(cubit.close);
      cubit.emit(cubit.state.copyWith(selectedIds: {'u1'}));
      await _pumpRuPicker(tester, cubit: cubit);

      await tester.tap(find.byTooltip('Добавить заметку для Алекс'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'заметка 893');
      await tester.pump();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      expect(find.text('заметка 893'), findsOneWidget);

      await tester.tap(
        find.byKey(TestIds.key(TestIds.forwardRecipientCheckbox('u1'))),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(TestIds.key(TestIds.forwardRecipientCheckbox('u1'))),
      );
      await tester.pumpAndSettle();

      expect(find.text('заметка 893'), findsOneWidget);
      expect(cubit.state.perRecipientNotes['u1'], 'заметка 893');
    },
  );

  testWidgets(
    'desktop: untick and re-tick restores collapsed note preview',
    (tester) async {
      final cubit = _cubitWithCandidates(const [
        ForwardCandidate(
          profile: Profile(
            id: 'u1',
            displayName: 'Alex',
            score: 10,
            rScore: 1,
          ),
        ),
      ]);
      addTearDown(cubit.close);
      cubit.emit(cubit.state.copyWith(selectedIds: {'u1'}));
      await _pumpEnPicker(tester, cubit: cubit);

      await tester.tap(find.byTooltip('Add a note for Alex'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'desktop note');
      await tester.pump();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(TestIds.key(TestIds.forwardRecipientCheckbox('u1'))),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(TestIds.key(TestIds.forwardRecipientCheckbox('u1'))),
      );
      await tester.pumpAndSettle();

      expect(find.text('desktop note'), findsOneWidget);
    },
  );

  testWidgets('first keystrokes after opening personal note are kept', (
    tester,
  ) async {
    final cubit = _cubitWithCandidates(const [
      ForwardCandidate(
        profile: Profile(
          id: 'u1',
          displayName: 'Alex',
          score: 10,
          rScore: 1,
        ),
      ),
    ]);
    addTearDown(cubit.close);
    cubit.emit(cubit.state.copyWith(selectedIds: {'u1'}));
    await _pumpEnPicker(tester, cubit: cubit);

    await tester.tap(find.byTooltip('Add a note for Alex'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'hello note 893');
    await tester.pump();

    expect(cubit.state.perRecipientNotes['u1'], 'hello note 893');
  });

  testWidgets(
    'send sheet lists only selected recipients without a personal note',
    (tester) async {
      final cubit = _cubitWithCandidates(const [
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
            score: 9,
            rScore: 1,
          ),
        ),
      ]);
      addTearDown(cubit.close);
      cubit.emit(
        cubit.state.copyWith(
          selectedIds: {'u1', 'u2'},
          perRecipientNotes: {'u1': 'has note'},
        ),
      );
      await _pumpEnPicker(
        tester,
        cubit: cubit,
        sendEnabled: true,
        onSendPressed: () {},
      );

      await tester.tap(find.text('Forward to 2'));
      await tester.pumpAndSettle();

      expect(find.text('People without a personal note'), findsOneWidget);
      expect(find.text('Blake'), findsNWidgets(2));
      expect(find.text('Alex'), findsOneWidget);
    },
  );
}
