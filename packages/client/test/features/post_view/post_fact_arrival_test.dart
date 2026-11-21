// Arriving at a fact of a Post through `/post/view/<id>?focus_fact=<factId>`
// (the origin line of a fact copied from a Post): the real Post route builds
// the real Post room, which opens the focused fact's actions by itself once
// the Post's facts are in. When the origin answer that led here said the
// fact changed since it was copied, the actions say so and offer «See the
// copied version». Same as the Request route does for `/beacon/view/...`.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';
import 'package:tentura/features/beacon_threads/domain/room_read_watermark_store.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/beacon_fact_history_entry.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart'
    show BeaconFactCardRepository, BeaconFactOrigin;
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/home/ui/bloc/post_join_navigation_cubit.dart';
import 'package:tentura/features/settings/ui/bloc/settings_cubit.dart';
import 'package:logging/logging.dart' as lg;
import 'package:tentura/features/beacon_threads/domain/coordination_item_room_sync.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_room_body.dart';
import 'package:tentura/features/beacon_threads/ui/widget/fact_actions_sheet.dart';
import 'package:tentura/features/beacon_threads/ui/widget/fact_history_sheet.dart';
import 'package:tentura/features/post_view/data/repository/beacon_kind_repository.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/data/repository/presence_repository.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../beacon_threads/fact_origin_test_support.dart';
import '../beacon_threads/room_cubit_fakes.dart';
import '../../support/test_realtime_sync.dart';
import '../beacon_view/beacon_view_screen_harness.dart';

const _postId = 'Bpostarrival01';
const _factId = 'Fpostfact0001';
const _otherFactId = 'Fpostfact0002';
const _viewer = Profile(id: kRoomCubitFakeMyUserId, displayName: 'Viewer');

Beacon _post() => Beacon(
  id: _postId,
  title: 'A post',
  kind: BeaconKind.post,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  author: _viewer,
);

BeaconFactCard _fact(String id, String pinnedBy) => sourceFact().copyWith(
  id: id,
  beaconId: _postId,
  pinnedByTitle: pinnedBy,
  lastEditedByTitle: '',
);

class _PostRepository implements BeaconRepository {
  @override
  Stream<RepositoryEvent<Beacon>> get changes => const Stream.empty();

  @override
  Future<Beacon> fetchBeaconById(String id) async => _post();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Lists the Post's General room, as the server does for a member.
class _ThreadsRepository extends FakeBeaconThreadsRepository {
  _ThreadsRepository() : super(userId: kRoomCubitFakeMyUserId);

  @override
  Future<List<RequestThread>> fetchThreads(String beaconId) async => [
    RequestThread(
      threadId: RequestThread.generalId,
      kind: RequestThreadKind.general,
      lastSeenAt: DateTime.utc(2026),
    ),
  ];
}

class _KindRepository implements BeaconKindRepository {
  @override
  Future<BeaconKind> fetchKind(String beaconId) async => BeaconKind.post;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(profile: _viewer);

  @override
  Stream<ProfileState> get stream => Stream.value(state);
}

class _TestRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
    AutoRoute(
      page: PostViewRoute.page,
      path: '/post/view/:id',
      children: [
        AutoRoute(
          page: BeaconViewOperationalRoute.page,
          path: '',
          initial: true,
        ),
      ],
    ),
  ];
}

BeaconFactOrigin _origin({
  required bool changedSinceCopy,
  bool canSeeCopiedRevision = false,
  int? copiedRevisionSeq,
  String factId = _factId,
}) => (
  available: true,
  beaconId: _postId,
  factCardId: factId,
  beaconKind: 1,
  changedSinceCopy: changedSinceCopy,
  canSeeCopiedRevision: canSeeCopiedRevision,
  copiedRevisionSeq: copiedRevisionSeq,
);

/// Answers `origin` per requested copy fact id, so an arrival is keyed by
/// the source fact it led to; records which fact's history was read.
class _KeyedOriginRepository extends FakeOriginFactCardRepository {
  _KeyedOriginRepository({
    required super.facts,
    this.answers = const {},
  });

  final Map<String, BeaconFactOrigin> answers;
  final List<String> revisionFactIds = [];

  @override
  Future<BeaconFactOrigin> origin({
    required String beaconId,
    required String factCardId,
  }) async => answers[factCardId] ?? unavailableOrigin();

  @override
  Future<BeaconFactHistoryPage> revisions({
    required String beaconId,
    required String factCardId,
    String? before,
  }) {
    revisionFactIds.add(factCardId);
    return super.revisions(
      beaconId: beaconId,
      factCardId: factCardId,
      before: before,
    );
  }
}

/// The Post's facts from memory; origin and history over the real GraphQL
/// stack ([OriginWire]).
class _WireOriginRepository extends FakeOriginFactCardRepository {
  _WireOriginRepository(this.wire, {required super.facts});

  final OriginWire wire;

  @override
  Future<BeaconFactOrigin> origin({
    required String beaconId,
    required String factCardId,
  }) => wire.repository.origin(beaconId: beaconId, factCardId: factCardId);

  @override
  Future<BeaconFactHistoryPage> revisions({
    required String beaconId,
    required String factCardId,
    String? before,
  }) => wire.repository.revisions(
    beaconId: beaconId,
    factCardId: factCardId,
    before: before,
  );
}

Future<void> _register<T extends Object>(T instance) async {
  if (GetIt.I.isRegistered<T>()) await GetIt.I.unregister<T>();
  GetIt.I.registerSingleton<T>(instance);
}

List<BeaconFactCard> _postFacts() => [
  _fact(_factId, 'Fiona'),
  _fact(_otherFactId, 'Gus'),
];

/// The Post route's collaborators: the Post, its General room, [facts].
Future<void> _registerPostDeps(BeaconFactCardRepository facts) async {
  await registerBeaconViewHarnessGetIt(profile: _viewer);
  addTearDown(unregisterBeaconViewHarnessGetIt);
  await _register<BeaconFactCardRepository>(facts);
  await _register<BeaconThreadsCase>(
    BeaconThreadsCase(
      _ThreadsRepository(),
      facts,
      FakePollingRepository(),
      FakeBeaconRoomHintsRepository(),
      RoomReadWatermarkStore.testing(),
      buildTestRealtimeSync().case_,
    ),
  );
  await _register<BeaconKindRepository>(_KindRepository());
  await _register<BeaconRepository>(_PostRepository());
  await _register<CoordinationItemRoomSync>(CoordinationItemRoomSync());
  await _register<PresenceRepository>(roomCubitFakePresenceRepository());
  addTearDown(() async {
    await GetIt.I.unregister<BeaconFactCardRepository>();
    await GetIt.I.unregister<BeaconKindRepository>();
    await GetIt.I.unregister<BeaconRepository>();
    await GetIt.I.unregister<CoordinationItemRoomSync>();
    await GetIt.I.unregister<PresenceRepository>();
  });
}

/// Opens the Post route at [url]. Each of [arrivals] (source fact -> origin
/// answer) is recorded first, as the origin line's tap does.
Future<({_TestRouter router, _KeyedOriginRepository repo})> _pumpPostRoute(
  WidgetTester tester, {
  required String url,
  List<BeaconFactOrigin> arrivals = const [],
}) async {
  final repo = _KeyedOriginRepository(
    facts: _postFacts(),
    answers: {for (final a in arrivals) 'copy-${a.factCardId}': a},
  );
  await _registerPostDeps(repo);
  for (final a in arrivals) {
    await tester.runAsync(
      () => GetIt.I<BeaconThreadsCase>().factOrigin(
        beaconId: kCopyBeaconId,
        factCardId: 'copy-${a.factCardId}',
      ),
    );
  }

  final router = _TestRouter();
  tester.view
    ..physicalSize = kBeaconViewHarnessCompact
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    BlocProvider<ProfileCubit>.value(
      value: _ProfileCubit(),
      child: MaterialApp.router(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('en'),
        builder: (_, child) => TenturaResponsiveScope(child: child!),
        routerConfig: router.config(
          deepLinkBuilder: (_) => DeepLink.path(url),
        ),
      ),
    ),
  );
  await pumpRealAsync(tester);
  return (router: router, repo: repo);
}

final class _Auth extends Fake implements AuthCubit {
  @override
  AuthState get state =>
      AuthState(updatedAt: DateTime(2026), currentAccountId: _viewer.id);

  @override
  Stream<AuthState> get stream => const Stream.empty();
}

final class _Settings extends Fake implements SettingsCubit {
  @override
  SettingsState get state => const SettingsState(introEnabled: false);

  @override
  Stream<SettingsState> get stream => const Stream.empty();
}

/// The real RootRouter starting on a copy's Request page (a stub with an
/// `open-copy` button running [openCopy]); the Post route is the real one.
Future<RootRouter> _pumpCopyToPostRouter(
  WidgetTester tester, {
  required void Function(BuildContext context) openCopy,
}) async {
  final homePage = HomeRoute.page;
  final beaconPage = BeaconViewRoute.page;
  addTearDown(() {
    HomeRoute.page = homePage;
    BeaconViewRoute.page = beaconPage;
  });
  HomeRoute.page = PageInfo(
    HomeRoute.name,
    builder: (_) => const SizedBox.shrink(),
  );
  BeaconViewRoute.page = PageInfo(
    BeaconViewRoute.name,
    builder: (_) => Scaffold(
      body: Builder(
        builder: (ctx) => Column(
          children: [
            const Text(kCopyPageMarker),
            TextButton(
              onPressed: () => openCopy(ctx),
              child: const Text('open-copy'),
            ),
          ],
        ),
      ),
    ),
  );
  final router = RootRouter(
    lg.Logger('PostArrivalRouter'),
    _Auth(),
    _Settings(),
    PostJoinNavigationCubit(),
  );
  addTearDown(router.dispose);
  tester.binding.platformDispatcher.defaultRouteNameTestValue =
      '/beacon/view/$kCopyBeaconId';
  addTearDown(tester.binding.platformDispatcher.clearDefaultRouteNameTestValue);
  tester.view
    ..physicalSize = kBeaconViewHarnessCompact
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    BlocProvider<ProfileCubit>.value(
      value: _ProfileCubit(),
      child: MaterialApp.router(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('en'),
        builder: (_, child) => TenturaResponsiveScope(child: child!),
        routerConfig: router.config(
          deepLinkBuilder: router.deepLinkBuilder,
          deepLinkTransformer: router.deepLinkTransformer,
          reevaluateListenable: router.reevaluateListenable,
          includePrefixMatches: false,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.text(kCopyPageMarker), findsOneWidget);
  return router;
}

Finder _sheetTitle(L10n l10n) => find.text(l10n.beaconRoomFactManageSheetTitle);

/// The open fact actions sheet (the scroll view holding its title).
Finder _actionsSheet(L10n l10n) => find
    .ancestor(
      of: _sheetTitle(l10n),
      matching: find.byType(SingleChildScrollView),
    )
    .first;

/// The open sheet is the actions of the fact pinned by [pinnedBy] and not of
/// the one pinned by [notPinnedBy].
void _expectSheetOfFact(
  L10n l10n, {
  required String pinnedBy,
  required String notPinnedBy,
}) {
  expect(_sheetTitle(l10n), findsOneWidget);
  final sheet = _actionsSheet(l10n);
  expect(
    find.descendant(of: sheet, matching: find.textContaining(pinnedBy)),
    findsOneWidget,
  );
  expect(
    find.descendant(of: sheet, matching: find.textContaining(notPinnedBy)),
    findsNothing,
  );
}

BeaconViewState _nonMemberRequestState() => BeaconViewState(
  beacon: Beacon(
    id: kSourceBeaconId,
    title: 'Source request',
    author: const Profile(id: 'Uauthor000001', displayName: 'Author'),
    createdAt: kBeaconViewHarnessNow,
    updatedAt: kBeaconViewHarnessNow,
  ),
  myProfile: _viewer,
  firstLoadDone: true,
  load: BeaconViewLoad.contentRead,
  roomParticipantsLoaded: true,
  roomParticipants: [
    BeaconParticipant(
      id: 'p-author',
      beaconId: kSourceBeaconId,
      userId: 'Uauthor000001',
      role: 0,
      status: 0,
      roomAccess: RoomAccessBits.admitted,
      createdAt: kBeaconViewHarnessNow,
      updatedAt: kBeaconViewHarnessNow,
    ),
  ],
  factCards: [sourceFact().copyWith(pinnedByTitle: 'Fiona')],
);

void main() {
  group('Post route with focus_fact', () {
    testWidgets('opens the actions of exactly that fact of the Post', (
      tester,
    ) async {
      final l10n = await L10n.delegate.load(const Locale('en'));
      await _pumpPostRoute(
        tester,
        url: '/post/view/$_postId?focus_fact=$_factId',
      );

      _expectSheetOfFact(l10n, pinnedBy: 'Fiona', notPinnedBy: 'Gus');
    });

    testWidgets('without focus_fact the Post opens with no fact actions', (
      tester,
    ) async {
      final l10n = await L10n.delegate.load(const Locale('en'));
      await _pumpPostRoute(tester, url: '/post/view/$_postId');

      expect(find.byType(BeaconRoomBody), findsOneWidget);
      expect(_sheetTitle(l10n), findsNothing);
    });

    testWidgets('a fact id that is not a fact of the Post opens no sheet and '
        'no error', (tester) async {
      final l10n = await L10n.delegate.load(const Locale('en'));
      await _pumpPostRoute(
        tester,
        url: '/post/view/$_postId?focus_fact=Fnotthere0001',
      );

      expect(find.byType(BeaconRoomBody), findsOneWidget);
      expect(_sheetTitle(l10n), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('opened directly, with no earlier origin tap, the actions '
        'carry no arrival note', (tester) async {
      final l10n = await L10n.delegate.load(const Locale('en'));
      await _pumpPostRoute(
        tester,
        url: '/post/view/$_postId?focus_fact=$_factId',
      );

      expect(_sheetTitle(l10n), findsOneWidget);
      expect(find.text(kChangedSinceCopied), findsNothing);
      expect(find.text(kSeeCopiedVersion), findsNothing);
    });

    testWidgets('after dismissal the actions do not reopen when the room '
        'reloads its facts and messages', (tester) async {
      final l10n = await L10n.delegate.load(const Locale('en'));
      await _pumpPostRoute(
        tester,
        url: '/post/view/$_postId?focus_fact=$_factId',
      );
      expect(_sheetTitle(l10n), findsOneWidget);

      Navigator.of(tester.element(_sheetTitle(l10n))).pop();
      await pumpRealAsync(tester);
      expect(_sheetTitle(l10n), findsNothing);

      final room = tester
          .element(find.byType(BeaconRoomBody))
          .read<RoomCubit>();
      await tester.runAsync(() async {
        await room.refreshFactCards();
        await room.reloadMessages();
      });
      await pumpRealAsync(tester);
      await tester.runAsync(room.load);
      await pumpRealAsync(tester);

      expect(_sheetTitle(l10n), findsNothing);
    });

    testWidgets('with the Post already open, a route change to another '
        'focus_fact opens that fact (and not the earlier one) with its '
        'arrival note', (tester) async {
      final l10n = await L10n.delegate.load(const Locale('en'));
      final h = await _pumpPostRoute(
        tester,
        url: '/post/view/$_postId?focus_fact=$_factId',
        arrivals: [_origin(changedSinceCopy: true, factId: _otherFactId)],
      );
      _expectSheetOfFact(l10n, pinnedBy: 'Fiona', notPinnedBy: 'Gus');
      Navigator.of(tester.element(_sheetTitle(l10n))).pop();
      await pumpRealAsync(tester);
      expect(_sheetTitle(l10n), findsNothing);

      unawaited(
        h.router.navigatePath(
          '/post/view/$_postId?focus_fact=$_otherFactId',
        ),
      );
      await pumpRealAsync(tester);

      _expectSheetOfFact(l10n, pinnedBy: 'Gus', notPinnedBy: 'Fiona');
      expect(find.text(kChangedSinceCopied), findsOneWidget);
    });
  });

  group('Post fact actions after an origin answer', () {
    testWidgets('changedSinceCopy=true shows «Changed since it was copied»', (
      tester,
    ) async {
      await _pumpPostRoute(
        tester,
        url: '/post/view/$_postId?focus_fact=$_factId',
        arrivals: [_origin(changedSinceCopy: true)],
      );

      expect(find.text(kChangedSinceCopied), findsOneWidget);
    });

    testWidgets('changedSinceCopy=false shows no changed note', (tester) async {
      final l10n = await L10n.delegate.load(const Locale('en'));
      await _pumpPostRoute(
        tester,
        url: '/post/view/$_postId?focus_fact=$_factId',
        arrivals: [_origin(changedSinceCopy: false)],
      );

      expect(_sheetTitle(l10n), findsOneWidget);
      expect(find.text(kChangedSinceCopied), findsNothing);
    });

    testWidgets('«See the copied version» closes the actions and opens the '
        'history of the source fact with revision 2 highlighted', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final l10n = await L10n.delegate.load(const Locale('en'));
      final h = await _pumpPostRoute(
        tester,
        url: '/post/view/$_postId?focus_fact=$_factId',
        arrivals: [
          _origin(
            changedSinceCopy: true,
            canSeeCopiedRevision: true,
            copiedRevisionSeq: 2,
          ),
        ],
      );

      expect(find.text(kSeeCopiedVersion), findsOneWidget);
      await tester.tap(find.text(kSeeCopiedVersion));
      await pumpRealAsync(tester);

      expect(_sheetTitle(l10n), findsNothing);
      expect(find.byType(FactHistorySheet), findsOneWidget);
      expect(h.repo.revisionFactIds, isNotEmpty);
      expect(h.repo.revisionFactIds.toSet(), {_factId});
      await scrollToRevision(tester, 2);
      await pumpRealAsync(tester);
      expect(selectedRevisions(tester), {2});
      semantics.dispose();
    });

    testWidgets('no «See the copied version» without canSeeCopiedRevision', (
      tester,
    ) async {
      final l10n = await L10n.delegate.load(const Locale('en'));
      await _pumpPostRoute(
        tester,
        url: '/post/view/$_postId?focus_fact=$_factId',
        arrivals: [_origin(changedSinceCopy: true, copiedRevisionSeq: 2)],
      );

      expect(_sheetTitle(l10n), findsOneWidget);
      expect(find.text(kSeeCopiedVersion), findsNothing);
    });

    testWidgets('no «See the copied version» when copiedRevisionSeq is '
        'null', (tester) async {
      final l10n = await L10n.delegate.load(const Locale('en'));
      await _pumpPostRoute(
        tester,
        url: '/post/view/$_postId?focus_fact=$_factId',
        arrivals: [
          _origin(changedSinceCopy: true, canSeeCopiedRevision: true),
        ],
      );

      expect(_sheetTitle(l10n), findsOneWidget);
      expect(find.text(kSeeCopiedVersion), findsNothing);
    });

    testWidgets('the arrival belongs to the focused fact: with answers for '
        'two source facts, each fact shows only its own', (tester) async {
      final l10n = await L10n.delegate.load(const Locale('en'));
      final arrivals = [
        _origin(changedSinceCopy: true),
        _origin(changedSinceCopy: false, factId: _otherFactId),
      ];
      await _pumpPostRoute(
        tester,
        url: '/post/view/$_postId?focus_fact=$_otherFactId',
        arrivals: arrivals,
      );
      _expectSheetOfFact(l10n, pinnedBy: 'Gus', notPinnedBy: 'Fiona');
      expect(find.text(kChangedSinceCopied), findsNothing);
    });

    testWidgets('the arrival belongs to the focused fact: the changed one '
        'shows its note when the unchanged one was answered last', (
      tester,
    ) async {
      final l10n = await L10n.delegate.load(const Locale('en'));
      await _pumpPostRoute(
        tester,
        url: '/post/view/$_postId?focus_fact=$_factId',
        arrivals: [
          _origin(changedSinceCopy: true),
          _origin(changedSinceCopy: false, factId: _otherFactId),
        ],
      );
      _expectSheetOfFact(l10n, pinnedBy: 'Fiona', notPinnedBy: 'Gus');
      expect(find.text(kChangedSinceCopied), findsOneWidget);
    });
  });

  group('Arriving from a copy in a Request', () {
    testWidgets('tapping the origin line of a fact copied from a Post, '
        'answered over the real transport, opens the Post at the source '
        'fact with its actions, changed note and copied-version action', (
      tester,
    ) async {
      final l10n = await L10n.delegate.load(const Locale('en'));
      final wire = (await tester.runAsync(
        () => OriginWire.start(
          origin: {
            'available': true,
            'beaconId': _postId,
            'factCardId': _factId,
            'beaconKind': 1,
            'changedSinceCopy': true,
            'canSeeCopiedRevision': true,
            'copiedRevisionSeq': 2,
          },
          revisions: [
            for (final q in [6, 5, 4, 3, 2, 1]) wireRevisionRow(q),
          ],
        ),
      ))!;
      addTearDown(() => tester.runAsync(wire.close));
      await _registerPostDeps(
        _WireOriginRepository(wire, facts: _postFacts()),
      );

      final router = await _pumpCopyToPostRouter(
        tester,
        openCopy: (ctx) => unawaited(
          showFactActionsHostSheet(
            ctx,
            fact: copiedFact(originBeaconKind: 1),
            canMutate: false,
            onCorrect:
                ({
                  required factCardId,
                  required newText,
                  attachmentsJson,
                }) async {},
            onRemove: ({required factCardId}) async {},
            onSetVisibility:
                ({required factCardId, required visibility}) async {},
          ),
        ),
      );
      await tester.tap(find.text('open-copy'));
      await tester.pumpAndSettle();
      await tapAndPumpRealAsync(tester, find.text(kOriginFromPost));
      await pumpRealAsync(tester);

      expect(wire.sent, contains('BeaconFactCardOrigin'));
      final at = routerLocation(router);
      expect(at.path, '/post/view/$_postId');
      expect(at.queryParameters['focus_fact'], _factId);
      _expectSheetOfFact(l10n, pinnedBy: 'Fiona', notPinnedBy: 'Gus');
      expect(find.text(kChangedSinceCopied), findsOneWidget);
      expect(find.text(kSeeCopiedVersion), findsOneWidget);
    });

    testWidgets('Request path: /beacon/view/<id>?focus_fact= after a changed '
        'origin answer still shows «Changed since it was copied»', (
      tester,
    ) async {
      await registerBeaconViewHarnessGetIt(profile: _viewer);
      addTearDown(unregisterBeaconViewHarnessGetIt);
      final wire = (await tester.runAsync(
        () => OriginWire.start(
          origin: {
            'available': true,
            'beaconId': kSourceBeaconId,
            'factCardId': kSourceFactId,
            'beaconKind': 0,
            'changedSinceCopy': true,
            'canSeeCopiedRevision': false,
            'copiedRevisionSeq': null,
          },
        ),
      ))!;
      addTearDown(() => tester.runAsync(wire.close));
      registerFactRepository(wire.repository);

      final router = await pumpOriginRouter(
        tester,
        openCopy: (ctx) => unawaited(
          showFactActionsHostSheet(
            ctx,
            fact: copiedFact(),
            canMutate: false,
            onCorrect:
                ({
                  required factCardId,
                  required newText,
                  attachmentsJson,
                }) async {},
            onRemove: ({required factCardId}) async {},
            onSetVisibility:
                ({required factCardId, required visibility}) async {},
          ),
        ),
        sourceScope: (outlet) => beaconViewHarnessRouteScope(
          beaconState: _nonMemberRequestState(),
          threadsState: beaconViewHarnessThreadsState(
            authorId: 'Uauthor000001',
          ),
          child: outlet,
        ),
      );
      await tester.tap(find.text('open-copy'));
      await tester.pumpAndSettle();
      await tapAndPumpRealAsync(tester, find.text(kOriginFromRequest));

      expect(routerLocation(router).path, '/beacon/view/$kSourceBeaconId');
      expect(find.text(kChangedSinceCopied), findsOneWidget);
    });
  });
}
