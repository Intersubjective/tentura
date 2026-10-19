import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/contacts/contact_name_store.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/invitation_entity.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/beacon_create/ui/screen/beacon_create_screen.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/contacts/domain/use_case/contacts_case.dart';
import 'package:tentura/features/context/data/repository/context_repository.dart';
import 'package:tentura/features/context/domain/entity/context_entity.dart';
import 'package:tentura/features/context/ui/bloc/context_cubit.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/use_case/forward_case.dart';
import 'package:tentura/features/invitation/data/repository/invitation_repository.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../auth/auth_test_helpers.dart';
import '../block/support/controllable_block_case.dart';
import '../contacts/contacts_case_test.dart';
import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import 'fake_beacon_ports.dart';

class _ContextRepositoryFake extends Fake implements ContextRepository {
  @override
  Stream<RepositoryEvent<ContextEntity>> get changes =>
      const Stream<RepositoryEvent<ContextEntity>>.empty();

  @override
  Future<Iterable<String>> fetch({bool fromCache = true}) async => [];
}

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
  Future<void> dispose() async {}
}

class _NeverLoadingForwardRepository implements ForwardRepository {
  @override
  Stream<String> get forwardChanges => const Stream<String>.empty();

  @override
  Future<Iterable<Profile>> fetchForwardCandidates({String context = ''}) =>
      Completer<Iterable<Profile>>().future;

  @override
  Future<BeaconInvolvementData> fetchBeaconInvolvement({
    required String beaconId,
  }) => Completer<BeaconInvolvementData>().future;

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeProfileRepository implements ProfileRepositoryPort {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeBeaconFactCardRepository implements BeaconFactCardRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ForwardCase _buildForwardCase(ContactNameStore store) {
  final authLocal = StreamingAuthLocal();
  final contactsCase = ContactsCase(
    FakeContactsRepository(),
    buildTestAuthCase(authLocal, EmptyAuthRemote()),
    store,
    buildTestRealtimeSync().case_,
    env: const Env(),
    logger: Logger('test'),
  );
  return ForwardCase(
    _NeverLoadingForwardRepository(),
    authLocal,
    _FakeBeaconFactCardRepository(),
    _FakeProfileRepository(),
    contactsCase,
    noopBlockCase(),
    env: const Env(),
    logger: Logger('test'),
  );
}

class _NavRouter extends Mock implements StackRouter {
  @override
  PagelessRoutesObserver get pagelessRoutesObserver => PagelessRoutesObserver();

  @override
  bool canPop({
    bool ignoreChildRoutes = false,
    bool ignoreParentRoutes = false,
    bool ignorePagelessRoutes = false,
  }) => true;
}

/// Draft store whose every create commits a draft carrying the submitted
/// title, and whose answer can be lost on the way back (the draft id then
/// never reaches the client).
class _DraftStore extends FakeBeaconWritePort {
  bool answersLost = false;
  int createAttempts = 0;

  @override
  Future<Beacon> create(Beacon fields, {bool draft = false}) async {
    createAttempts++;
    beacon = beacon.copyWith(
      id: 'draft-$createAttempts',
      title: fields.title,
      description: fields.description,
      needs: fields.needs,
      status: BeaconStatus.draft,
    );
    if (answersLost) throw Exception('response lost');
    createdFields.add(fields);
    return beacon;
  }
}

const _title = 'Need a piano moved';
const _description = 'Two flights of stairs, this weekend.';

void main() {
  late BeaconCreateCubit createCubit;
  late ContextCubit contextCubit;
  late _DraftStore store;

  setUp(() {
    final names = ContactNameStore();
    store = _DraftStore();
    GetIt.I
      ..registerSingleton<Env>(const Env(googleMapsApiKey: 'test-key'))
      ..registerSingleton<UiEffectPort>(FakeUiEffectPort())
      ..registerSingleton<ContactNameStore>(names)
      ..registerSingleton<ForwardCase>(_buildForwardCase(names))
      ..registerSingleton<InvitationRepository>(_FakeInvitationRepository());
    contextCubit = ContextCubit(
      authCase: buildTestAuthCase(EmptyAuthLocal(), EmptyAuthRemote()),
      contextRepository: _ContextRepositoryFake(),
      effects: FakeUiEffectPort(),
    );
    createCubit = BeaconCreateCubit(
      beaconCreateCase: fakeBeaconCreateCase(write: store),
      effects: FakeUiEffectPort(),
    )..setAutosaveContext('');
  });

  tearDown(() async {
    await createCubit.close();
    await contextCubit.close();
    await GetIt.I.reset();
  });

  /// Opens the editor as a route pushed over a host page, so one pop of the
  /// whole flow lands back on the host.
  Future<void> openEditor(
    WidgetTester tester, {
    String initialTab = '',
    String draftId = '',
    BeaconCreateCubit? cubit,
    Locale locale = const Locale('en'),
  }) async {
    final router = _NavRouter();
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        theme: TenturaTheme.light(),
        home: Builder(
          builder: (homeContext) => TextButton(
            onPressed: () => Navigator.of(homeContext).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => RouterScope(
                  controller: router,
                  stateHash: 0,
                  inheritableObserversBuilder: () => const [],
                  child: StackRouterScope(
                    controller: router,
                    stateHash: 0,
                    child: MultiBlocProvider(
                      providers: [
                        BlocProvider<ContextCubit>.value(value: contextCubit),
                        BlocProvider<BeaconCreateCubit>.value(
                          value: cubit ?? createCubit,
                        ),
                        BlocProvider<ProfileCubit>.value(
                          value: _MockProfileCubit(),
                        ),
                      ],
                      child: BeaconCreateScreen(
                        initialTab: initialTab,
                        draftId: draftId,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            child: const Text('open-editor'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open-editor'));
    await _settle(tester);
    expect(find.byType(BeaconCreateScreen), findsOneWidget);
  }

  Finder topBarIcon(IconData icon) => find.descendant(
    of: find.byType(TenturaTopBar),
    matching: find.byIcon(icon),
  );

  void typeContent() => createCubit
    ..setTitle(_title)
    ..setDescription(_description);

  /// Types into the form fields, as the user does; the autosave debounce
  /// (one second) has not elapsed when this returns.
  Future<void> typeIntoForm(WidgetTester tester) async {
    await tester.enterText(find.byType(TextFormField).at(0), _title);
    await tester.enterText(find.byType(TextFormField).at(1), _description);
    await tester.pump();
  }

  group('Request editor «✕» on the recipients step', () {
    testWidgets(
      'exits the whole create flow back to where the user started in one tap',
      (tester) async {
        typeContent();
        await openEditor(tester, initialTab: kBeaconCreateTabRecipients);
        expect(find.text('Recipients'), findsWidgets);

        await tester.tap(topBarIcon(Icons.close));
        await _settle(tester);

        expect(find.byType(BeaconCreateScreen), findsNothing);
        expect(find.text('open-editor'), findsOneWidget);
      },
    );

    testWidgets(
      'flushes the draft with the current content before leaving, even when '
      'the draft id never reached the client',
      (tester) async {
        typeContent();
        store.answersLost = true;
        await openEditor(tester, initialTab: kBeaconCreateTabRecipients);
        expect(createCubit.state.draftId, isNull);
        final attemptsBeforeClose = store.createAttempts;

        store.answersLost = false;
        await tester.tap(topBarIcon(Icons.close));
        await _settle(tester);

        expect(store.createAttempts, greaterThan(attemptsBeforeClose));
        expect(store.createdFields.last.title, _title);
        expect(store.createdFields.last.description, _description);
        expect(find.byType(BeaconCreateScreen), findsNothing);
      },
    );

    testWidgets(
      'is also offered when the recipients step opened after a failed '
      'delivery left no draft to pick recipients for',
      (tester) async {
        typeContent();
        store.answersLost = true;
        await openEditor(tester, initialTab: kBeaconCreateTabRecipients);
        expect(
          find.byKey(const Key('BeaconCreate.RecipientsRetry')),
          findsOneWidget,
        );

        await tester.tap(topBarIcon(Icons.close));
        await _settle(tester);

        expect(find.byType(BeaconCreateScreen), findsNothing);
        expect(find.text('open-editor'), findsOneWidget);
      },
    );

    testWidgets('keeps «←» as one step back to the info step', (tester) async {
      typeContent();
      await openEditor(tester, initialTab: kBeaconCreateTabRecipients);
      expect(topBarIcon(Icons.close), findsOneWidget);

      await tester.tap(topBarIcon(Icons.arrow_back));
      await _settle(tester);

      expect(find.byType(BeaconCreateScreen), findsOneWidget);
      expect(find.text('Recipients'), findsNothing);
      expect(find.text('open-editor'), findsNothing);
    });

    testWidgets('has an accessible, localized label in English and Russian', (
      tester,
    ) async {
      typeContent();
      await openEditor(tester, initialTab: kBeaconCreateTabRecipients);
      final enLabel = tester
          .getSemantics(
            find.ancestor(
              of: topBarIcon(Icons.close),
              matching: find.byType(IconButton),
            ),
          )
          .label;
      expect(enLabel, 'Close');
      expect(
        tester
            .widget<IconButton>(
              find.ancestor(
                of: topBarIcon(Icons.close),
                matching: find.byType(IconButton),
              ),
            )
            .tooltip,
        'Close',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await openEditor(
        tester,
        initialTab: kBeaconCreateTabRecipients,
        locale: const Locale('ru'),
      );
      final ruLabel = tester
          .getSemantics(
            find.ancestor(
              of: topBarIcon(Icons.close),
              matching: find.byType(IconButton),
            ),
          )
          .label;
      expect(ruLabel, 'Закрыть');
      expect(
        tester
            .widget<IconButton>(
              find.ancestor(
                of: topBarIcon(Icons.close),
                matching: find.byType(IconButton),
              ),
            )
            .tooltip,
        'Закрыть',
      );
    });
  });

  // Issue #428: on the info step «←» and «✕» both left the editor with no
  // visible difference. The info step now has ONE exit, «←», which asks
  // «Keep draft» / «Discard» when the form holds content. The recipients step
  // keeps #265's «←» (one step back) + «✕» (exit the flow, keep the draft).
  group('Request editor info step has a single exit (#428)', () {
    testWidgets('shows only the back arrow, no close control', (tester) async {
      typeContent();
      await openEditor(tester);

      expect(topBarIcon(Icons.arrow_back), findsOneWidget);
      expect(topBarIcon(Icons.close), findsNothing);
      await _drainAutosave(tester);
    });

    testWidgets(
      '«←» with typed content asks Keep draft or Discard and stays in the '
      'editor until answered',
      (tester) async {
        await openEditor(tester);
        await typeIntoForm(tester);

        await tester.tap(topBarIcon(Icons.arrow_back));
        await _settle(tester);

        expect(find.text('Keep draft'), findsOneWidget);
        expect(find.text('Discard'), findsOneWidget);
        expect(find.byType(BeaconCreateScreen), findsOneWidget);
        expect(find.text('open-editor'), findsNothing);
        await _drainAutosave(tester);
      },
    );

    testWidgets('the system back gesture asks the same question', (
      tester,
    ) async {
      await openEditor(tester);
      await typeIntoForm(tester);

      await tester.binding.handlePopRoute();
      await _settle(tester);

      expect(find.text('Keep draft'), findsOneWidget);
      expect(find.text('Discard'), findsOneWidget);
      expect(find.byType(BeaconCreateScreen), findsOneWidget);
      await _drainAutosave(tester);
    });

    testWidgets(
      'Keep draft exits the flow in one go and flushes the not-yet-autosaved '
      'content to the draft store',
      (tester) async {
        await openEditor(tester);
        await typeIntoForm(tester);
        expect(store.createdFields, isEmpty);

        await tester.tap(topBarIcon(Icons.arrow_back));
        await _settle(tester);
        await tester.tap(find.text('Keep draft'));
        await _settle(tester);

        expect(store.createdFields, isNotEmpty);
        expect(store.createdFields.last.title, _title);
        expect(store.createdFields.last.description, _description);
        expect(store.deletedIds, isEmpty);
        expect(find.byType(BeaconCreateScreen), findsNothing);
        expect(find.text('open-editor'), findsOneWidget);
      },
    );

    testWidgets(
      'Discard exits the flow and leaves no draft behind',
      (tester) async {
        await openEditor(tester);
        await typeIntoForm(tester);

        await tester.tap(topBarIcon(Icons.arrow_back));
        await _settle(tester);
        await tester.tap(find.text('Discard'));
        await _settle(tester);
        // A draft autosave may have created while the question was open must
        // be gone again; ids are draft-1..draft-N in create order.
        expect(
          store.deletedIds,
          containsAll(<String>[
            for (var i = 1; i <= store.createAttempts; i++) 'draft-$i',
          ]),
        );
        final attemptsAfterDiscard = store.createAttempts;
        await tester.pump(const Duration(seconds: 2));
        await _settle(tester);
        expect(store.createAttempts, attemptsAfterDiscard);
        expect(find.byType(BeaconCreateScreen), findsNothing);
        expect(find.text('open-editor'), findsOneWidget);
      },
    );

    testWidgets('Discard deletes the draft autosave had already created', (
      tester,
    ) async {
      await openEditor(tester);
      await typeIntoForm(tester);
      await createCubit.flushAutosave();
      await _settle(tester);
      final savedId = createCubit.state.draftId;
      expect(savedId, isNotNull);
      expect(store.deletedIds, isEmpty);

      await tester.tap(topBarIcon(Icons.arrow_back));
      await _settle(tester);
      await tester.tap(find.text('Discard'));
      await _settle(tester);

      expect(store.deletedIds, [savedId]);
      expect(find.byType(BeaconCreateScreen), findsNothing);
      expect(find.text('open-editor'), findsOneWidget);
    });

    testWidgets('an empty form leaves on «←» at once, without asking and '
        'without saving', (tester) async {
      await openEditor(tester);

      await tester.tap(topBarIcon(Icons.arrow_back));
      await _settle(tester);

      expect(find.text('Keep draft'), findsNothing);
      expect(find.text('Discard'), findsNothing);
      expect(store.createAttempts, 0);
      expect(find.byType(BeaconCreateScreen), findsNothing);
      expect(find.text('open-editor'), findsOneWidget);
    });

    testWidgets('the question is localized in Russian', (tester) async {
      await openEditor(tester, locale: const Locale('ru'));
      await typeIntoForm(tester);

      await tester.tap(topBarIcon(Icons.arrow_back));
      await _settle(tester);

      expect(find.text('Сохранить черновик'), findsOneWidget);
      expect(find.text('Удалить черновик'), findsOneWidget);
      expect(find.text('Keep draft'), findsNothing);
      expect(find.text('Discard'), findsNothing);
      expect(find.byType(BeaconCreateScreen), findsOneWidget);
      await _drainAutosave(tester);
    });

    testWidgets('re-opening the editor restores the draft kept on «←»', (
      tester,
    ) async {
      await openEditor(tester);
      await typeIntoForm(tester);
      await tester.tap(topBarIcon(Icons.arrow_back));
      await _settle(tester);
      await tester.tap(find.text('Keep draft'));
      await _settle(tester);
      final savedId = createCubit.state.draftId;
      expect(savedId, isNotNull);

      final reopened = BeaconCreateCubit(
        beaconCreateCase: fakeBeaconCreateCase(write: store),
        effects: FakeUiEffectPort(),
        draftBeaconIdToLoad: savedId,
      );
      addTearDown(reopened.close);
      await tester.pumpWidget(const SizedBox.shrink());
      await openEditor(tester, draftId: savedId!, cubit: reopened);

      expect(reopened.state.title, _title);
      expect(reopened.state.description, _description);
      expect(find.text(_title), findsOneWidget);
      expect(find.text(_description), findsOneWidget);
    });
  });

  group('Draft restoration after exiting the recipients step', () {
    testWidgets(
      're-opening after leaving from the recipients step restores the draft',
      (tester) async {
        typeContent();
        await openEditor(tester, initialTab: kBeaconCreateTabRecipients);
        await tester.tap(topBarIcon(Icons.close));
        await _settle(tester);
        final savedId = createCubit.state.draftId;
        expect(savedId, isNotNull);

        final reopened = BeaconCreateCubit(
          beaconCreateCase: fakeBeaconCreateCase(write: store),
          effects: FakeUiEffectPort(),
          draftBeaconIdToLoad: savedId,
        );
        addTearDown(reopened.close);
        await tester.pumpWidget(const SizedBox.shrink());
        await openEditor(tester, draftId: savedId!, cubit: reopened);

        expect(reopened.state.title, _title);
        expect(reopened.state.description, _description);
        expect(find.text(_title), findsOneWidget);
        expect(find.text(_description), findsOneWidget);
      },
    );
  });
}

/// Lets cubit futures, route transitions and post-frame callbacks run without
/// waiting on the never-resolving forward band.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 16; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Runs out the cubit's 1 s autosave debounce so no Timer is left pending
/// when a test ends while the editor (or its exit question) is still open.
Future<void> _drainAutosave(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 2));
  await _settle(tester);
}
