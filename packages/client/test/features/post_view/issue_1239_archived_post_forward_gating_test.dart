// #1239: SQL `viewer_can_forward` ignores Post expiry; the client must hide
// Forward / «Invite new person» when [Beacon.isPostArchivedAt] is true while
// `viewerCanForward` stays true. Requests are unchanged.

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/data/gql/_g/beacon_model.data.gql.dart';
import 'package:tentura/data/model/beacon_model.dart';
import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';
import 'package:tentura/features/beacon_threads/domain/room_host.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/thread_host_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/threads_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/threads_state.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_room_body.dart';
import 'package:tentura/features/block/domain/use_case/block_case.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/forward_candidate.dart';
import 'package:tentura/features/forward/domain/entity/forward_edge.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/forward/ui/screen/forward_beacon_screen.dart';
import 'package:tentura/features/inbox/domain/entity/post_summary.dart';
import 'package:tentura/features/inbox/domain/port/posts_repository_port.dart';
import 'package:tentura/features/post_view/ui/bloc/post_view_cubit.dart';
import 'package:tentura/features/post_view/ui/screen/post_view_screen.dart';
import 'package:tentura/features/post_view/ui/widget/post_info_sheet.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/features/profile_view/domain/use_case/profile_view_case.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/l10n/l10n_en.dart';
import 'package:tentura/ui/l10n/l10n_ru.dart';

import '../../support/fake_app_navigator.dart';
import '../../support/graph_trust_write_fixture.dart';
import '../../support/phone_surface.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../beacon_threads/support/room_body_harness.dart';
import '../beacon_view/beacon_view_screen_harness.dart'
    show BeaconViewHarnessRouter;

const _postId = 'Bpost1239001';
const _rootId = 'Mpostroot001';
const _author = Profile(id: 'Uauthor', displayName: 'Олег');
const _reader = Profile(id: 'Ureader', displayName: 'Мария');

final _createdAt = DateTime.utc(2026, 10, 20, 12);
final _clockNow = DateTime.utc(2026, 10, 27, 12);

class _IdleBlockCase extends Mock implements BlockCase {}

class _FakeForwardRepository implements ForwardRepository {
  @override
  Future<List<ForwardEdge>> fetchEdges({required String beaconId}) async => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ProfileCubit extends Mock implements ProfileCubit {
  _ProfileCubit(this.profile);

  final Profile profile;

  @override
  ProfileState get state => ProfileState(profile: profile);

  @override
  Stream<ProfileState> get stream => Stream.value(state);
}

class _PostRepository implements BeaconRepository {
  _PostRepository(this.beacon);

  final Beacon beacon;

  @override
  Stream<RepositoryEvent<Beacon>> get changes => const Stream.empty();

  @override
  Future<Beacon> fetchBeaconById(String id) async => beacon;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePostsRepository implements PostsRepositoryPort {
  @override
  Future<List<PostSummary>> myPosts() async => [];

  @override
  Future<PostSummary?> postSummary(String id) async => PostSummary(
    id: _postId,
    authorId: _author.id,
    authorName: _author.displayName,
    rootExcerpt: 'Тест',
    lastActivityAt: _createdAt,
  );
}

RoomMessage _rootMessage() => RoomMessage(
  id: _rootId,
  beaconId: _postId,
  authorId: _author.id,
  author: _author,
  body: 'Кто в субботу на велопрогулку?',
  createdAt: _createdAt,
);

Future<void> _pumpPostScreen(
  WidgetTester tester, {
  required Beacon beacon,
  required Locale locale,
  required Size surface,
  required DateTime Function() clock,
}) async {
  final getIt = GetIt.I;
  await getIt.reset();
  addTearDown(getIt.reset);
  registerFakeAppNavigator();
  final profileCubit = _ProfileCubit(_reader);
  final profiles = GraphTrustWriteFixture();
  addTearDown(profiles.dispose);
  getIt
    ..registerSingleton<ProfileCubit>(profileCubit)
    ..registerSingleton<ProfileViewCase>(profiles.profileViewCase)
    ..registerSingleton<BlockCase>(_IdleBlockCase())
    ..registerSingleton<UiEffectPort>(FakeUiEffectPort())
    ..registerSingleton<ImageRepository>(ImageRepository())
    ..registerSingleton<ClipboardImageRepository>(ClipboardImageRepository())
    ..registerSingleton<ForwardRepository>(_FakeForwardRepository())
    ..registerSingleton<PostsRepositoryPort>(_FakePostsRepository());

  final cubit = PostViewCubit(
    id: _postId,
    myProfile: _reader,
    beaconRepository: _PostRepository(beacon),
    effects: FakeUiEffectPort(),
    clock: clock,
  );
  addTearDown(cubit.close);
  await cubit.fetch();

  final room = _RoomCubit(
    roomBodyState(
      beaconId: _postId,
      myUserId: _reader.id,
      messages: [_rootMessage()],
    ).copyWith(
      participants: [
        roomBodyAdmittedParticipant(
          beaconId: _postId,
          profile: _reader,
          role: BeaconParticipantRoleBits.addressee,
        ),
      ],
      participantsLoaded: true,
    ),
  );
  final threadHost = ThreadHostCubit(
    beaconId: _postId,
    capabilities: const RoomCapabilities.post(),
    roomCubitFactory:
        ({
          required beaconId,
          threadItemId,
          initialUnreadAnchorAt,
          capabilities = const RoomCapabilities.request(),
        }) => room,
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    final closing = threadHost.close();
    await tester.pump();
    await closing;
  });

  final general = RequestThread(
    threadId: RequestThread.generalId,
    kind: RequestThreadKind.general,
    lastSeenAt: _createdAt,
  );
  final router = BeaconViewHarnessRouter();

  await tester.binding.setSurfaceSize(surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    StackRouterScope(
      controller: router,
      stateHash: 0,
      child: MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: locale,
        home: MediaQuery(
          data: MediaQueryData(size: surface),
          child: TenturaResponsiveScope(
            child: MultiBlocProvider(
              providers: [
                BlocProvider<PostViewCubit>.value(value: cubit),
                BlocProvider<ThreadsCubit>.value(
                  value: _ThreadsCubit(
                    ThreadsState(
                      threads: [general],
                      myUserId: _reader.id,
                    ),
                  ),
                ),
                BlocProvider<ThreadHostCubit>.value(value: threadHost),
                BlocProvider<ProfileCubit>.value(value: profileCubit),
                BlocProvider<PresenceCubit>.value(
                  value: RoomBodyHarnessPresenceCubit(),
                ),
                BlocProvider<ScreenCubit>(
                  create: (_) => ScreenCubit(FakeUiEffectPort()),
                ),
              ],
              child: const PostViewScreen(id: _postId),
            ),
          ),
        ),
      ),
    ),
  );
  for (var i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    if (find.byType(BeaconRoomBody).evaluate().isNotEmpty) break;
  }
  await tester.pump(const Duration(milliseconds: 100));
  expect(find.byType(BeaconRoomBody), findsOneWidget);
}

class _RoomCubit extends RoomBodyHarnessCubit {
  _RoomCubit(super.initial);

  var _closed = false;

  @override
  bool get isClosed => _closed;

  @override
  Future<void> close() async => _closed = true;

  @override
  Future<void> load() async {}

  @override
  void prepareThreadScroll({String? messageId, String? coordinationItemId}) {}
}

class _ThreadsCubit extends Mock implements ThreadsCubit {
  _ThreadsCubit(this._state);

  final ThreadsState _state;

  @override
  ThreadsState get state => _state;

  @override
  Stream<ThreadsState> get stream => Stream.value(_state);

  @override
  Future<void> fetch({bool silent = false}) async {}
}

Beacon _post({
  required DateTime? expiresAt,
  BeaconKind kind = BeaconKind.post,
}) => Beacon(
  id: _postId,
  kind: kind,
  createdAt: _createdAt,
  updatedAt: _createdAt,
  author: _author,
  postRootMessageId: _rootId,
  viewerCanForward: true,
  expiresAt: expiresAt,
);

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

Finder _inAppBar(Finder f) =>
    find.descendant(of: find.byType(AppBar), matching: f);

Future<void> _openInfoSheet(WidgetTester tester, L10n l10n) async {
  await tester.tap(_inAppBar(find.byIcon(Icons.more_vert)));
  await _settle(tester);
  await tester.tap(find.text(l10n.postMenuInfo));
  await _settle(tester);
  expect(find.byType(PostInfoSheet), findsOneWidget);
}

Future<void> _pumpForwardPage(
  WidgetTester tester, {
  required Beacon beacon,
  required DateTime Function() clock,
  required Locale locale,
  required Size surface,
}) async {
  final cubit = ForwardCubit(
    beaconId: _postId,
    debugSkipInitialLoad: true,
    effects: FakeUiEffectPort(),
    clock: clock,
  );
  addTearDown(cubit.close);
  cubit.emit(
    ForwardState(
      beaconId: _postId,
      beacon: beacon,
      candidates: const [
        ForwardCandidate(
          profile: Profile(
            id: 'u1',
            displayName: 'Клара',
            rScore: 1,
            score: 70,
          ),
        ),
      ],
      candidatesLoad: const ForwardCandidatesReady(),
    ),
  );

  await tester.binding.setSurfaceSize(surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      theme: TenturaTheme.light(),
      home: MediaQuery(
        data: MediaQueryData(size: surface),
        child: MultiBlocProvider(
          providers: [
            BlocProvider<ForwardCubit>.value(value: cubit),
            BlocProvider<ProfileCubit>.value(value: _ProfileCubit(_reader)),
          ],
          child: const ForwardBeaconPage(beaconId: _postId),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Map<String, dynamic> _wireRow({
  required String? expiresAt,
  required bool viewerCanForward,
}) => {
  '__typename': 'beacon',
  'id': 'B1',
  'cover_source': 0,
  'title': 't',
  'description': 'd',
  'needs': '',
  'created_at': '2026-01-01T00:00:00+00:00',
  'updated_at': '2026-01-01T00:00:00+00:00',
  'status': 0,
  'tags': '',
  'beacon_images': <dynamic>[],
  'author': {
    '__typename': 'user',
    'id': 'U1',
    'display_name': 'A',
    'description': '',
  },
  'help_offers_aggregate': {
    '__typename': 'beacon_help_offer_aggregate',
    'aggregate': null,
  },
  'unanswered_help_offers': {
    '__typename': 'beacon_help_offer_aggregate',
    'aggregate': null,
  },
  'admitted_helpers_aggregate': {
    '__typename': 'beacon_help_offer_aggregate',
    'aggregate': null,
  },
  'is_discoverable': true,
  'kind': 1,
  'forward_policy': 1,
  'last_activity_at': '2026-02-03T04:05:06+00:00',
  'post_root_message_id': 'M1',
  'viewer_can_forward': viewerCanForward,
  'expires_at': expiresAt,
};

void main() {
  test(
    'BeaconModel wire row with viewer_can_forward maps viewerCanForwardAt',
    () {
      final entity = BeaconModel(
        GBeaconModelData.fromJson(
          _wireRow(
            expiresAt: '2026-10-26T10:00:00+00:00',
            viewerCanForward: true,
          ),
        )!,
      ).toEntity();
      final now = DateTime.utc(2026, 10, 27, 12);
      expect(entity.viewerCanForward, isTrue);
      expect(entity.isPostArchivedAt(now), isTrue);
      expect(entity.viewerCanForwardAt(now), isFalse);
    },
  );

  group('#1239 forward UI hidden on expired Post', () {
    final l10nRu = L10nRu();
    final l10nEn = L10nEn();
    final inviteRu = l10nRu.forwardInviteNewPerson;
    final inviteEn = l10nEn.forwardInviteNewPerson;
    final sheetForwardRu = l10nRu.postInfoActionForward;
    final sheetForwardEn = l10nEn.postInfoActionForward;
    final appBarForwardRu = l10nRu.labelForward;
    final appBarForwardEn = l10nEn.labelForward;

    testWidgets('375×667 RU: expired Post hides Forward icon and sheet row', (
      tester,
    ) async {
      await usePhoneSurface(tester);
      await _pumpPostScreen(
        tester,
        beacon: _post(expiresAt: _clockNow.subtract(const Duration(hours: 1))),
        locale: const Locale('ru'),
        surface: kPhoneSurface,
        clock: () => _clockNow,
      );

      expect(find.byTooltip(appBarForwardRu), findsNothing);
      await _openInfoSheet(tester, l10nRu);
      expect(find.text(sheetForwardRu), findsNothing);
    });

    testWidgets('1280×800 EN: open Post keeps Forward in app bar and sheet', (
      tester,
    ) async {
      final futureExpiry = _clockNow.add(const Duration(days: 2));
      await _pumpPostScreen(
        tester,
        beacon: _post(expiresAt: futureExpiry),
        locale: const Locale('en'),
        surface: const Size(1280, 800),
        clock: () => _clockNow,
      );

      expect(find.byTooltip(appBarForwardEn), findsOneWidget);
      await _openInfoSheet(tester, l10nEn);
      expect(find.text(sheetForwardEn), findsOneWidget);
    });

    testWidgets('1280×800 EN: open Post forward picker shows invite bar', (
      tester,
    ) async {
      await _pumpForwardPage(
        tester,
        beacon: _post(expiresAt: _clockNow.add(const Duration(days: 2))),
        clock: () => _clockNow,
        locale: const Locale('en'),
        surface: const Size(1280, 800),
      );
      expect(find.text(inviteEn), findsOneWidget);
    });

    testWidgets('375×667 RU: expired Post forward picker has no invite bar', (
      tester,
    ) async {
      await usePhoneSurface(tester);
      await _pumpForwardPage(
        tester,
        beacon: _post(expiresAt: _clockNow.subtract(const Duration(hours: 1))),
        clock: () => _clockNow,
        locale: const Locale('ru'),
        surface: kPhoneSurface,
      );
      expect(find.text(inviteRu), findsNothing);
    });

    testWidgets('Request with viewerCanForward is unchanged', (tester) async {
      final request = _post(expiresAt: null, kind: BeaconKind.request);
      expect(request.viewerCanForwardAt(_clockNow), isTrue);
      await _pumpForwardPage(
        tester,
        beacon: request,
        clock: () => _clockNow,
        locale: const Locale('en'),
        surface: const Size(400, 800),
      );
      expect(find.text(inviteEn), findsOneWidget);
    });
  });
}
