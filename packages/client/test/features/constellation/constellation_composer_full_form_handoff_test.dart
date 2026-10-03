// «Подробнее» in the graph composer opens the full create form on the same
// server draft, with the composer's recipients and per-recipient notes already
// selected. The sheet button hands a `BeaconCreateRoute` to its navigator; the
// real `BeaconCreateScreen` then seeds its recipients `ForwardCubit` from the
// route's initial recipients and notes.

import 'dart:async';
import 'dart:ui' show Offset;

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/contacts/contact_name_store.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/domain/entity/invitation_entity.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/use_case/beacon_create_case.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/auth/domain/use_case/auth_case.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/beacon_create/ui/screen/beacon_create_screen.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_composer_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_composer_sheet.dart';
import 'package:tentura/features/context/data/repository/context_repository.dart';
import 'package:tentura/features/context/domain/entity/context_entity.dart';
import 'package:tentura/features/contacts/domain/use_case/contacts_case.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/lineage_suggestion_group.dart';
import 'package:tentura/features/forward/domain/use_case/forward_case.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/forward/ui/widget/forward_recipient_picker.dart';
import 'package:tentura/features/invitation/data/repository/invitation_repository.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../auth/auth_test_helpers.dart';
import '../block/support/controllable_block_case.dart';
import '../beacon_create/fake_beacon_ports.dart';
import '../contacts/contacts_case_test.dart';

const _detailsButton = Key('constellation.composer.details_button');

const _positions = <String, Offset>{
  'Ua': Offset(10, 0),
  'Ub': Offset(20, 0),
  'Uc': Offset(30, 0),
};

const _target = Profile(
  id: 'Ua',
  displayName: 'Person Ua',
  score: 1,
  rScore: 1,
);

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

class _ForwardRepository implements ForwardRepository {
  final _changes = StreamController<String>.broadcast();

  @override
  Stream<String> get forwardChanges => _changes.stream;

  @override
  Future<Iterable<Profile>> fetchForwardCandidates({
    String context = '',
  }) async => const [_target];

  @override
  Future<BeaconInvolvementData> fetchBeaconInvolvement({
    required String beaconId,
  }) async => (
    beacon: Beacon.empty.copyWith(
      id: beaconId,
      author: const Profile(id: 'U-me'),
    ),
    forwardedToIds: <String>{},
    helpOfferedIds: <String>{},
    withdrawnIds: <String>{},
    rejectedIds: <String>{},
    watchingIds: <String>{},
    onwardForwarderIds: <String>{},
    myForwardedRecipientNotes: <String, String>{},
    myForwardedRecipientEdgeIds: <String, String>{},
    myForwardedRecipientReadAts: <String, DateTime?>{},
    myForwardedRecipientHasOnwardChild: <String, bool>{},
    myForwardedRecipientRejected: <String, bool>{},
  );

  @override
  Future<LineageForwardSuggestions> fetchLineageForwardSuggestions({
    required String beaconId,
  }) async => const LineageForwardSuggestions(
    sourceBeaconId: '',
    rootBeaconId: '',
    suggestedNote: '',
    suggestions: [],
  );

  @override
  Future<void> dispose() => _changes.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ProfileRepository implements ProfileRepositoryPort {
  @override
  Future<List<Profile>> fetchProfilesByIds(Set<String> ids) async => [
    for (final id in ids)
      if (id == _target.id) _target,
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FactCardRepository implements BeaconFactCardRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PresenceCubit extends Mock implements PresenceCubit {
  @override
  Map<String, UserPresenceStatus> get state => const {};

  @override
  Stream<Map<String, UserPresenceStatus>> get stream => const Stream.empty();
}

class _Router extends Mock implements StackRouter {}

void main() {
  tearDown(() async {
    await GetIt.I.reset();
  });

  testWidgets('the «Подробнее» button hands BeaconCreateRoute with the same '
      'draft id, recipients and notes to the navigator', (tester) async {
    final effects = FakeUiEffectPort();
    GetIt.I
      ..registerSingleton<UiEffectPort>(effects)
      ..registerSingleton<InvitationRepository>(_FakeInvitationRepository());
    final forwards = <ForwardCubit>[];
    final composer = ConstellationComposerCubit(
      positions: _positions,
      eligible: _positions.keys.toSet(),
      createCubitFactory: (kind) => BeaconCreateCubit(
        kind: kind,
        beaconCreateCase: fakeBeaconCreateCase(write: FakeBeaconWritePort()),
        effects: effects,
      ),
      forwardCubitFactory: (beaconId) {
        final cubit = ForwardCubit(
          beaconId: beaconId,
          embedded: true,
          effects: effects,
          debugSkipInitialLoad: true,
        );
        forwards.add(cubit);
        return cubit;
      },
    );
    addTearDown(() async {
      await composer.close();
      for (final f in forwards) {
        await f.close();
      }
    });
    composer.start(BeaconKind.request, Offset.zero);
    await tester.runAsync(() async {
      await composer.contentChanged();
      await Future<void>.delayed(Duration.zero);
    });
    composer.forwardCubit!.setRecipientNote('Ua', 'ты же хотел');
    tester.view
      ..physicalSize = const Size(420, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final opened = <PageRouteInfo>[];

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: TenturaResponsiveScope(
          child: MultiBlocProvider(
            providers: [
              BlocProvider<ConstellationComposerCubit>.value(value: composer),
              BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
            ],
            child: Scaffold(
              body: ConstellationComposerSheet(
                composer: composer,
                onOpenFullForm: opened.add,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(_detailsButton));
    await tester.pump();

    final route = opened.single;
    expect(route, isA<BeaconCreateRoute>());
    final args = route.args! as BeaconCreateRouteArgs;
    expect(args.draftId, 'server-beacon');
    expect(args.initialRecipientIds, {'Ua', 'Ub', 'Uc'});
    expect(args.initialNotes, {'Ua': 'ты же хотел'});
  });

  testWidgets('the full form opened with initial recipients and notes seeds '
      'its recipients picker with them', (tester) async {
    tester.view
      ..physicalSize = const Size(800, 1200)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final getIt = GetIt.I;
    await getIt.reset();

    final authLocal = StreamingAuthLocal('U-me');
    final contactsRepo = FakeContactsRepository();
    final store = ContactNameStore();
    getIt.registerSingleton<ContactNameStore>(store);
    final contactsCase = ContactsCase(
      contactsRepo,
      buildTestAuthCase(authLocal, EmptyAuthRemote()),
      store,
      buildTestRealtimeSync().case_,
      env: const Env(),
      logger: Logger('test'),
    );
    contactsRepo.fetchMineHandler = () async => {};
    final synced = contactsRepo.nextSync();
    authLocal.emit('U-me');
    await synced;
    final forwardRepo = _ForwardRepository();
    addTearDown(() async {
      await forwardRepo.dispose();
      await contactsCase.dispose();
      await store.dispose();
    });
    final draft = Beacon.empty.copyWith(
      id: 'draft-1',
      status: BeaconStatus.draft,
      title: 'My draft title',
      description: 'Valid description for recipients tab.',
    );
    getIt
      ..registerSingleton<UiEffectPort>(FakeUiEffectPort())
      ..registerSingleton<InvitationRepository>(_FakeInvitationRepository())
      ..registerSingleton<ProfileCubit>(_MockProfileCubit())
      ..registerSingleton<Env>(const Env())
      ..registerSingleton<AuthCase>(
        buildTestAuthCase(authLocal, EmptyAuthRemote()),
      )
      ..registerSingleton<ContextRepository>(_ContextRepositoryFake())
      ..registerSingleton<ImageRepository>(ImageRepository())
      ..registerSingleton<ClipboardImageRepository>(ClipboardImageRepository())
      ..registerSingleton<BeaconCreateCase>(
        fakeBeaconCreateCase(write: FakeBeaconWritePort(beacon: draft)),
      )
      ..registerSingleton<ForwardCase>(
        ForwardCase(
          forwardRepo,
          authLocal,
          _FactCardRepository(),
          _ProfileRepository(),
          contactsCase,
          noopBlockCase(),
          env: const Env(),
          logger: Logger('test'),
        ),
      );
    final router = _Router();

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
            child: TenturaResponsiveScope(
              child: MultiBlocProvider(
                providers: [
                  BlocProvider<ProfileCubit>.value(
                    value: getIt<ProfileCubit>(),
                  ),
                  BlocProvider<PresenceCubit>.value(value: _PresenceCubit()),
                  BlocProvider<ScreenCubit>(
                    create: (_) => ScreenCubit.local(),
                  ),
                ],
                child: Builder(
                  builder: (context) => const BeaconCreateScreen(
                    draftId: 'draft-1',
                    initialTab: kBeaconCreateTabRecipients,
                    initialRecipientIds: {'Ua'},
                    initialNotes: {'Ua': 'ты же хотел'},
                  ).wrappedRoute(context),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    final forward = tester
        .element(find.byType(ForwardRecipientPicker))
        .read<ForwardCubit>();
    expect(forward.state.selectedIds, {'Ua'});
    expect(forward.state.perRecipientNotes, {'Ua': 'ты же хотел'});
  });
}
