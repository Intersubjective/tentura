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
import 'package:tentura/domain/port/post_conversion_port.dart';
import 'package:tentura/domain/use_case/beacon_create_case.dart';
import 'package:tentura/domain/use_case/post_conversion_case.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/auth/domain/use_case/auth_case.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/beacon_create/ui/dialog/beacon_send_confirmation_dialog.dart';
import 'package:tentura/features/beacon_create/ui/screen/beacon_create_screen.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/contacts/domain/use_case/contacts_case.dart';
import 'package:tentura/features/context/data/repository/context_repository.dart';
import 'package:tentura/features/context/domain/entity/context_entity.dart';
import 'package:tentura/features/context/ui/bloc/context_cubit.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/forward_candidate.dart';
import 'package:tentura/features/forward/domain/use_case/forward_case.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/forward/ui/bloc/forward_state.dart';
import 'package:tentura/features/invitation/data/repository/invitation_repository.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

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

/// Forward repository whose band never resolves: the recipients step only
/// needs to exist, not to finish loading.
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

/// Server side of publishing: every [publishDraft] call is counted and parked
/// on [publishHold], then answers with a failure so that no navigation to the
/// live Request follows (these tests only look at what the editor sent).
class _SlowPublishPort extends FakeBeaconWritePort {
  _SlowPublishPort({super.beacon});

  final Completer<void> publishHold = Completer<void>();
  int publishCalls = 0;

  @override
  Future<void> publishDraft(String id) async {
    publishCalls++;
    await publishHold.future;
    throw Exception('publish stopped by the test');
  }
}

/// A [FakeBeaconWritePort] whose publish succeeds, but only once released.
class _HeldSuccessfulPublishPort extends FakeBeaconWritePort {
  _HeldSuccessfulPublishPort({super.beacon});

  final Completer<void> publishHold = Completer<void>();
  int publishCalls = 0;

  @override
  Future<void> publishDraft(String id) async {
    publishCalls++;
    await publishHold.future;
    return super.publishDraft(id);
  }
}

/// A [FakeBeaconWritePort] whose draft save parks until released.
class _HeldDraftSavePort extends FakeBeaconWritePort {
  _HeldDraftSavePort({super.beacon});

  final Completer<void> updateHold = Completer<void>();
  int updateDraftCalls = 0;

  @override
  Future<Beacon> updateDraft(Beacon fields) async {
    updateDraftCalls++;
    await updateHold.future;
    return super.updateDraft(fields);
  }
}

/// Post-to-Request conversion that parks until released, then fails so that no
/// navigation to the converted Request follows.
class _HeldConversionPort implements PostConversionPort {
  /// Created on first use, inside the test's fake-async zone: a Completer made
  /// in `setUp` completes in the real zone, so its waiters would not resume
  /// while the test pumps.
  late final Completer<void> hold = Completer<void>();
  int convertCalls = 0;

  @override
  Future<PostRootContent> fetchRootContent(String beaconId) async =>
      const PostRootContent(body: 'Need a ladder\nI can pick it up.');

  @override
  Future<void> convertToRequest({
    required String beaconId,
    required String title,
    required String description,
    required Set<String> needs,
    required String? primaryNeedSlug,
    required DateTime? startAt,
    required DateTime? endAt,
    required bool isDiscoverable,
    List<String> helperIds = const [],
  }) async {
    convertCalls++;
    await hold.future;
    throw Exception('conversion stopped by the test');
  }
}

BeaconCreateCubit _cubit(FakeBeaconWritePort write) => BeaconCreateCubit(
  beaconCreateCase: fakeBeaconCreateCase(write: write),
  effects: FakeUiEffectPort(),
);

void _fillRequired(BeaconCreateCubit cubit) {
  cubit
    ..setTitle('Need a piano moved')
    ..setDescription('Two flights of stairs, this weekend.');
}

ForwardCubit _forwardWithRecipient(String beaconId) {
  final forward = ForwardCubit(
    beaconId: beaconId,
    embedded: true,
    debugSkipInitialLoad: true,
    debugInitialState: ForwardState(
      beaconId: beaconId,
      candidates: [
        const ForwardCandidate(
          profile: Profile(
            id: 'U1',
            displayName: 'Recipient',
            myVote: 1,
            subjectExplicitlyTrustsViewer: true,
          ),
        ),
      ],
    ),
    effects: FakeUiEffectPort(),
  )..toggleSelection('U1');
  return forward;
}

void main() {
  group('Publishing a Request from the editor cubit', () {
    test('a second make-live while the first is in flight publishes nothing '
        'more', () async {
      final write = _HeldSuccessfulPublishPort(
        beacon: Beacon.empty.copyWith(id: 'B1', status: BeaconStatus.draft),
      );
      final cubit = _cubit(write);
      addTearDown(cubit.close);
      _fillRequired(cubit);
      await cubit.ensureDraft(context: 'c', showMessage: false);

      final first = cubit.makeLive(context: 'c');
      final second = cubit.makeLive(context: 'c');
      await pumpEventQueue();

      expect(write.publishCalls, 1);
      expect(cubit.state.isLoading, isTrue);

      write.publishHold.complete();
      await Future.wait<void>([first, second]);

      expect(write.publishedIds, ['B1']);
      expect(write.updatedDraftFields, hasLength(1));
      expect(cubit.state.isLive, isTrue);
    });

    test('a second send while the first is in flight publishes and saves '
        'nothing more', () async {
      final write = _HeldSuccessfulPublishPort(
        beacon: Beacon.empty.copyWith(id: 'B1', status: BeaconStatus.draft),
      );
      final cubit = _cubit(write);
      addTearDown(cubit.close);
      _fillRequired(cubit);
      await cubit.ensureDraft(context: 'c', showMessage: false);
      final forward = _forwardWithRecipient('B1');
      addTearDown(forward.close);

      final first = cubit.sendRequest(context: 'c', forwardCubit: forward);
      final second = cubit.sendRequest(context: 'c', forwardCubit: forward);
      await pumpEventQueue();

      expect(write.publishCalls, 1);
      expect(cubit.state.isLoading, isTrue);

      write.publishHold.complete();
      await Future.wait<Object?>([first, second]);

      expect(write.publishedIds, ['B1']);
      expect(write.updatedDraftFields, hasLength(1));
    });
  });

  group('Saving a draft from the editor cubit', () {
    test('a second save while the first is in flight writes nothing more', () async {
      final write = _HeldDraftSavePort(
        beacon: Beacon.empty.copyWith(id: 'B1', status: BeaconStatus.draft),
      );
      final cubit = _cubit(write);
      addTearDown(cubit.close);
      _fillRequired(cubit);
      await cubit.ensureDraft(context: 'c', showMessage: false);

      final first = cubit.saveDraft(context: 'c');
      final second = cubit.saveDraft(context: 'c');
      await pumpEventQueue();

      expect(write.updateDraftCalls, 1);
      expect(cubit.state.isLoading, isTrue);

      write.updateHold.complete();
      await Future.wait<void>([first, second]);

      expect(write.updatedDraftFields, hasLength(1));
    });
  });

  group('Make live button on the recipients step', () {
    late BeaconCreateCubit createCubit;
    late ContextCubit contextCubit;
    late _SlowPublishPort write;

    setUp(() {
      final store = ContactNameStore();
      GetIt.I
        ..registerSingleton<Env>(const Env(googleMapsApiKey: 'test-key'))
        ..registerSingleton<UiEffectPort>(FakeUiEffectPort())
        ..registerSingleton<ContactNameStore>(store)
        ..registerSingleton<ForwardCase>(_buildForwardCase(store))
        ..registerSingleton<InvitationRepository>(_FakeInvitationRepository());
      contextCubit = ContextCubit(
        authCase: buildTestAuthCase(EmptyAuthLocal(), EmptyAuthRemote()),
        contextRepository: _ContextRepositoryFake(),
        effects: FakeUiEffectPort(),
      );
    });

    tearDown(() async {
      await createCubit.close();
      await contextCubit.close();
      await GetIt.I.reset();
    });

    Finder makeLiveButton() => find.byKey(TestIds.key(TestIds.requestMakeLive));

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    /// Opens the screen on the recipients step for a valid, autosaved draft.
    Future<void> pumpRecipientsStep(WidgetTester tester) async {
      write = _SlowPublishPort(
        beacon: Beacon.empty.copyWith(id: 'B1', status: BeaconStatus.draft),
      );
      createCubit = _cubit(write);
      _fillRequired(createCubit);
      final router = _NavRouter();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          theme: TenturaTheme.light(),
          home: RouterScope(
            controller: router,
            stateHash: 0,
            inheritableObserversBuilder: () => const [],
            child: StackRouterScope(
              controller: router,
              stateHash: 0,
              child: MultiBlocProvider(
                providers: [
                  BlocProvider<ContextCubit>.value(value: contextCubit),
                  BlocProvider<BeaconCreateCubit>.value(value: createCubit),
                  BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
                ],
                child: const BeaconCreateScreen(
                  initialTab: kBeaconCreateTabRecipients,
                ),
              ),
            ),
          ),
        ),
      );
      await settle(tester);
      expect(createCubit.state.draftId, 'B1');
      expect(tester.widget<TextButton>(makeLiveButton()).onPressed, isNotNull);
    }

    testWidgets(
      'two taps before the button has rebuilt publish the Request once',
      (tester) async {
        await pumpRecipientsStep(tester);

        // Both taps land in the same frame, before the first one's loading
        // state could disable the button.
        final onPressed = tester
            .widget<TextButton>(makeLiveButton())
            .onPressed!;
        onPressed();
        onPressed();
        await settle(tester);

        expect(write.publishCalls, 1);
        expect(write.updatedDraftFields, hasLength(1));
      },
    );

    testWidgets(
      'shows a spinner in the button right after the first tap and drops it '
      'once publishing has ended',
      (tester) async {
        await pumpRecipientsStep(tester);
        final spinnerInButton = find.descendant(
          of: makeLiveButton(),
          matching: find.byType(CircularProgressIndicator),
        );
        expect(spinnerInButton, findsNothing);

        await tester.tap(makeLiveButton());
        await tester.pump();

        expect(
          spinnerInButton,
          findsOneWidget,
          reason: 'A slow publish must read as busy, not as an ignored tap',
        );
        expect(tester.widget<TextButton>(makeLiveButton()).onPressed, isNull);

        write.publishHold.complete();
        await settle(tester);

        expect(spinnerInButton, findsNothing);
        expect(write.publishCalls, 1);
      },
    );
  });

  group('Save draft action on the create form', () {
    late BeaconCreateCubit createCubit;
    late ContextCubit contextCubit;
    late _HeldDraftSavePort write;

    setUp(() {
      final store = ContactNameStore();
      GetIt.I
        ..registerSingleton<Env>(const Env(googleMapsApiKey: 'test-key'))
        ..registerSingleton<UiEffectPort>(FakeUiEffectPort())
        ..registerSingleton<ContactNameStore>(store)
        ..registerSingleton<ForwardCase>(_buildForwardCase(store))
        ..registerSingleton<InvitationRepository>(_FakeInvitationRepository());
      contextCubit = ContextCubit(
        authCase: buildTestAuthCase(EmptyAuthLocal(), EmptyAuthRemote()),
        contextRepository: _ContextRepositoryFake(),
        effects: FakeUiEffectPort(),
      );
    });

    tearDown(() async {
      await createCubit.close();
      await contextCubit.close();
      await GetIt.I.reset();
    });

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    L10n l10nOf(WidgetTester tester) =>
        L10n.of(tester.element(find.byType(Scaffold).first))!;

    Finder draftAction(WidgetTester tester) => find.widgetWithText(
      TenturaTextAction,
      l10nOf(tester).beaconCreateDraftAction,
    );

    /// Opens the create form for a valid draft that already exists on the
    /// server, so that "Save draft" goes through the slow update.
    Future<void> pumpFormWithDraft(WidgetTester tester) async {
      write = _HeldDraftSavePort(
        beacon: Beacon.empty.copyWith(id: 'B1', status: BeaconStatus.draft),
      );
      createCubit = _cubit(write);
      _fillRequired(createCubit);
      await createCubit.ensureDraft(context: 'c', showMessage: false);
      final router = _NavRouter();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          theme: TenturaTheme.light(),
          home: RouterScope(
            controller: router,
            stateHash: 0,
            inheritableObserversBuilder: () => const [],
            child: StackRouterScope(
              controller: router,
              stateHash: 0,
              child: MultiBlocProvider(
                providers: [
                  BlocProvider<ContextCubit>.value(value: contextCubit),
                  BlocProvider<BeaconCreateCubit>.value(value: createCubit),
                  BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
                ],
                child: const BeaconCreateScreen(),
              ),
            ),
          ),
        ),
      );
      await settle(tester);
      expect(createCubit.state.draftId, 'B1');
    }

    Future<void> chooseSaveDraft(WidgetTester tester) async {
      await tester.tap(draftAction(tester));
      await settle(tester);
      final item = find.text(l10nOf(tester).buttonSaveDraft);
      if (item.evaluate().isEmpty) return;
      await tester.tap(item);
      await settle(tester);
    }

    testWidgets(
      'choosing Save draft twice while the first save is in flight writes the '
      'draft once',
      (tester) async {
        await pumpFormWithDraft(tester);

        await chooseSaveDraft(tester);
        expect(write.updateDraftCalls, 1);

        await chooseSaveDraft(tester);
        expect(
          write.updateDraftCalls,
          1,
          reason: 'A slow save must not accept a second Save draft',
        );

        write.updateHold.complete();
        await settle(tester);
        expect(write.updatedDraftFields, hasLength(1));
      },
    );

    testWidgets(
      'the Draft action is disabled while a save is in flight and comes back '
      'once it has ended',
      (tester) async {
        await pumpFormWithDraft(tester);
        Finder actionButton() => find.descendant(
          of: draftAction(tester),
          matching: find.byType(TextButton),
        );
        expect(tester.widget<TextButton>(actionButton()).onPressed, isNotNull);

        await chooseSaveDraft(tester);
        expect(createCubit.state.isLoading, isTrue);

        expect(
          tester.widget<TextButton>(actionButton()).onPressed,
          isNull,
          reason: 'A slow save must read as busy, not as an ignored tap',
        );

        write.updateHold.complete();
        await settle(tester);

        expect(tester.widget<TextButton>(actionButton()).onPressed, isNotNull);
      },
    );
  });

  group('Publish button when converting a Post to a Request', () {
    late _HeldConversionPort conversion;

    setUp(() {
      conversion = _HeldConversionPort();
      GetIt.I
        ..registerSingleton<Env>(const Env(googleMapsApiKey: 'test-key'))
        ..registerSingleton<UiEffectPort>(FakeUiEffectPort())
        ..registerSingleton<AuthCase>(
          buildTestAuthCase(EmptyAuthLocal(), EmptyAuthRemote()),
        )
        ..registerSingleton<ContextRepository>(_ContextRepositoryFake())
        ..registerSingleton<BeaconCreateCase>(fakeBeaconCreateCase())
        ..registerSingleton<PostConversionCase>(PostConversionCase(conversion));
    });

    tearDown(() => GetIt.I.reset());

    Finder publishButton() =>
        find.byKey(const Key('BeaconCreate.ConvertButton'));

    Future<void> pumpConversionForm(WidgetTester tester) async {
      final router = _NavRouter();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          theme: TenturaTheme.light(),
          home: RouterScope(
            controller: router,
            stateHash: 0,
            inheritableObserversBuilder: () => const [],
            child: StackRouterScope(
              controller: router,
              stateHash: 0,
              child: Builder(
                builder: (context) => const BeaconCreateScreen(
                  convertFromPostId: 'post-1',
                ).wrappedRoute(context),
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(tester.widget<FilledButton>(publishButton()).onPressed, isNotNull);
    }

    testWidgets(
      'two presses before the button has rebuilt convert the Post once',
      (tester) async {
        await pumpConversionForm(tester);

        final onPressed = tester
            .widget<FilledButton>(publishButton())
            .onPressed!;
        onPressed();
        onPressed();
        await tester.pump();

        expect(conversion.convertCalls, 1);

        conversion.hold.complete();
        await tester.pump(const Duration(milliseconds: 50));
      },
    );

    testWidgets(
      'shows a spinner in the button right after the tap and drops it once '
      'the conversion has ended',
      (tester) async {
        await pumpConversionForm(tester);
        final spinnerInButton = find.descendant(
          of: publishButton(),
          matching: find.byType(CircularProgressIndicator),
        );
        expect(spinnerInButton, findsNothing);

        await tester.tap(publishButton());
        await tester.pump();

        expect(
          spinnerInButton,
          findsOneWidget,
          reason: 'A slow publish must read as busy, not as an ignored tap',
        );
        expect(tester.widget<FilledButton>(publishButton()).onPressed, isNull);

        conversion.hold.complete();
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }

        expect(spinnerInButton, findsNothing);
        expect(conversion.convertCalls, 1);
      },
    );
  });

  group('Send confirmation dialog', () {
    testWidgets(
      'two OK presses before the dialog has closed dismiss only the dialog',
      (tester) async {
        final navigatorKey = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigatorKey,
            locale: const Locale('en'),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            theme: TenturaTheme.light(),
            home: const Scaffold(body: Text('home page')),
          ),
        );
        unawaited(
          navigatorKey.currentState!.push<void>(
            MaterialPageRoute<void>(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => unawaited(
                    BeaconSendConfirmationDialog.show(
                      context,
                      outcome: const ForwardDeliveryOutcome(
                        requestedRecipientIds: ['U1'],
                        deliveredRecipientIds: ['U1'],
                        availabilitySkippedRecipientIds: [],
                      ),
                    ),
                  ),
                  child: const Text('request page'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('request page'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);

        final ok = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(FilledButton),
        );
        final onPressed = tester.widget<FilledButton>(ok).onPressed!;
        onPressed();
        onPressed();
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsNothing);
        expect(
          find.text('request page'),
          findsOneWidget,
          reason: 'The second press must not also leave the page behind',
        );
      },
    );
  });
}
