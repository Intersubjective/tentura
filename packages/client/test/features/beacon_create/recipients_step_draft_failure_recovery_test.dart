import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/contacts/contact_name_store.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/invitation_entity.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/beacon_create/ui/screen/beacon_create_screen.dart';
import 'package:tentura/features/beacon_create/ui/widget/recipients_tab.dart';
import 'package:tentura/features/context/data/repository/context_repository.dart';
import 'package:tentura/features/context/domain/entity/context_entity.dart';
import 'package:tentura/features/context/ui/bloc/context_cubit.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/contacts/domain/use_case/contacts_case.dart';
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

/// Server side of draft creation.
///
/// Every [create] call commits a new draft on the server (plain creates carry
/// no idempotency key, so a repeated call really makes another draft). The
/// answer can be slow ([hold]) or never reach the client ([answersLost]),
/// after the commit happened either way.
class _ScriptedCreatePort extends FakeBeaconWritePort {
  /// While set, [create] waits for it before answering (a slow request).
  Completer<void>? hold;

  /// While true, the commit happens but the answer is lost on the way back.
  bool answersLost = false;

  final committedIds = <String>[];
  int createAttempts = 0;

  @override
  Future<Beacon> create(Beacon fields, {bool draft = false}) async {
    createAttempts++;
    final id = 'draft-${committedIds.length + 1}';
    committedIds.add(id);
    beacon = beacon.copyWith(id: id, title: fields.title, needs: fields.needs);
    final pending = hold;
    if (pending != null) await pending.future;
    if (answersLost) {
      throw Exception('response lost');
    }
    return beacon;
  }
}

void main() {
  const retryKey = Key('BeaconCreate.RecipientsRetry');
  const preparingLabel = 'Preparing draft…';

  late BeaconCreateCubit createCubit;
  late ContextCubit contextCubit;
  late _ScriptedCreatePort write;

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

  /// Opens the screen on the Recipients step for a valid, not yet saved form.
  Future<void> pumpRecipientsStep(
    WidgetTester tester,
    _ScriptedCreatePort port, {
    Duration wait = Duration.zero,
  }) async {
    write = port;
    createCubit =
        BeaconCreateCubit(
            beaconCreateCase: fakeBeaconCreateCase(write: port),
            effects: FakeUiEffectPort(),
          )
          ..setTitle('Need a piano moved')
          ..setDescription('Two flights of stairs, this weekend.');
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
    if (wait > Duration.zero) {
      await tester.pump(wait);
      await settle(tester);
    }
  }

  /// The draft the recipient picker is bound to, which must be one the server
  /// really committed and the one the create cubit reports.
  void expectPickerOnCommittedDraft(WidgetTester tester) {
    final pickerDraftId = tester
        .widget<BeaconRecipientsTab>(find.byType(BeaconRecipientsTab))
        .beaconId;
    expect(write.committedIds, contains(pickerDraftId));
    expect(createCubit.state.draftId, pickerDraftId);
    expect(find.text(preparingLabel), findsNothing);
    expect(find.byKey(retryKey), findsNothing);
  }

  group('Recipients step while the draft is being created', () {
    testWidgets(
      'shows the preparing spinner while the server is slow, then the '
      'recipient picker once the draft exists',
      (tester) async {
        await pumpRecipientsStep(
          tester,
          _ScriptedCreatePort()..hold = Completer<void>(),
        );

        expect(find.text(preparingLabel), findsOneWidget);
        expect(find.byType(BeaconRecipientsTab), findsNothing);

        write.hold!.complete();
        await settle(tester);

        expectPickerOnCommittedDraft(tester);
      },
    );
  });

  group(
    'Recipients step when the create response never reaches the client',
    () {
      testWidgets(
        'leaves the preparing spinner for a retry control, with no recipient '
        'picker, once the pending create fails',
        (tester) async {
          await pumpRecipientsStep(
            tester,
            _ScriptedCreatePort()
              ..hold = Completer<void>()
              ..answersLost = true,
          );
          expect(find.text(preparingLabel), findsOneWidget);

          write.hold!.complete();
          await settle(tester);

          expect(write.committedIds, isNotEmpty);
          expect(createCubit.state.draftId, isNull);
          expect(find.text(preparingLabel), findsNothing);
          expect(find.byType(CircularProgressIndicator), findsNothing);
          expect(find.byType(BeaconRecipientsTab), findsNothing);
          expect(find.byKey(retryKey), findsOneWidget);
        },
      );

      testWidgets(
        'retry shows a recipient picker bound to a draft the server committed, '
        'once answers get through again',
        (tester) async {
          await pumpRecipientsStep(
            tester,
            _ScriptedCreatePort()..answersLost = true,
          );
          expect(createCubit.state.draftId, isNull);
          expect(find.byKey(retryKey), findsOneWidget);
          expect(find.byType(BeaconRecipientsTab), findsNothing);

          write.answersLost = false;
          await tester.tap(find.byKey(retryKey));
          await settle(tester);

          expectPickerOnCommittedDraft(tester);

          // Settled: nothing keeps re-creating drafts behind the picker.
          final attemptsWhenSettled = write.createAttempts;
          await settle(tester);
          expect(write.createAttempts, attemptsWhenSettled);
        },
      );

      testWidgets(
        'retry that fails again keeps offering the retry control',
        (tester) async {
          await pumpRecipientsStep(
            tester,
            _ScriptedCreatePort()..answersLost = true,
          );
          final attemptsBeforeRetry = write.createAttempts;

          await tester.tap(find.byKey(retryKey));
          await settle(tester);

          expect(write.createAttempts, greaterThan(attemptsBeforeRetry));
          expect(find.byKey(retryKey), findsOneWidget);
          expect(find.text(preparingLabel), findsNothing);
          expect(find.byType(BeaconRecipientsTab), findsNothing);
        },
      );
    },
  );

  group('Recipients step when the create request never answers', () {
    testWidgets(
      'gives up the preparing spinner for a retry control within two minutes',
      (tester) async {
        await pumpRecipientsStep(
          tester,
          _ScriptedCreatePort()..hold = Completer<void>(),
        );
        expect(find.text(preparingLabel), findsOneWidget);

        await tester.pump(const Duration(minutes: 2));
        await settle(tester);

        expect(createCubit.state.draftId, isNull);
        expect(find.text(preparingLabel), findsNothing);
        expect(find.byType(BeaconRecipientsTab), findsNothing);
        expect(find.byKey(retryKey), findsOneWidget);
      },
    );

    testWidgets(
      'a late answer after the retry control appeared still opens the '
      'recipient picker on the committed draft',
      (tester) async {
        await pumpRecipientsStep(
          tester,
          _ScriptedCreatePort()..hold = Completer<void>(),
          wait: const Duration(minutes: 2),
        );
        expect(find.byKey(retryKey), findsOneWidget);

        write.hold!.complete();
        await settle(tester);

        expectPickerOnCommittedDraft(tester);
      },
    );
  });
}

/// Lets cubit futures and post-frame callbacks run without waiting on the
/// never-resolving forward band.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
