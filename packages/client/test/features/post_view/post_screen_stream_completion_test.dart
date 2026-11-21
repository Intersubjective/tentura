// A Post screen must survive its request/cubit streams ending without the
// element it waits for: the screen closing while the Post or its thread list
// is still loading, and a transport stream that completes with no Link
// response. Built on the real PostViewScope; the failure cases go through the
// real BeaconRepository / BeaconThreadsRepository over clients whose stream
// closes with no response.

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:ferry/ferry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/data/repository/presence_repository.dart';
import 'package:tentura/data/service/remote_api_client/exception.dart';
import 'package:tentura/data/service/remote_api_client/remote_api_client_web.dart';
import 'package:tentura/data/service/remote_api_client/remote_request_client.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_threads_repository.dart';
import 'package:tentura/features/beacon_threads/domain/coordination_item_room_sync.dart';
import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';
import 'package:tentura/features/beacon_threads/domain/room_read_watermark_store.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/thread_host_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_room_body.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/forward_edge.dart';
import 'package:tentura/features/inbox/domain/entity/post_summary.dart';
import 'package:tentura/features/inbox/domain/port/posts_repository_port.dart';
import 'package:tentura/features/post_view/ui/screen/post_view_scope.dart';
import 'package:tentura/features/post_view/ui/screen/post_view_screen.dart';
import 'package:tentura/features/post_view/ui/util/post_participants_sheet_request.dart';
import 'package:tentura/features/post_view/ui/widget/post_info_sheet.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../beacon_threads/room_cubit_fakes.dart';
import '../beacon_threads/support/room_body_harness.dart';
import '../beacon_view/beacon_view_screen_harness.dart'
    show BeaconViewHarnessRouter;

const _postId = kRoomCubitFakeBeaconId;
const _rootId = 'Mpostroot001';
const _author = Profile(id: 'Uauthor', displayName: 'Олег');
const _reader = Profile(id: kRoomCubitFakeMyUserId, displayName: 'Мария');
final _createdAt = DateTime.utc(2026, 10, 27, 9);
final _post = Beacon(
  id: _postId,
  kind: BeaconKind.post,
  createdAt: _createdAt,
  updatedAt: _createdAt,
  author: _author,
  expiresAt: DateTime.now().add(const Duration(hours: 5)),
  postRootMessageId: _rootId,
);

/// Answers every request with a stream that closes at once: no Link response.
class _EmptyStreamClient implements RemoteRequestClient {
  @override
  Stream<OperationResponse<TData, TVars>> request<TData, TVars>(
    OperationRequest<TData, TVars> request, [
    Stream<OperationResponse<TData, TVars>> Function(
      OperationRequest<TData, TVars>,
    )?
    forward,
  ]) => const Stream.empty();
}

/// The client the thread repository is typed on, answering every request with
/// a stream that closes at once: no Link response.
base class _EmptyStreamApiClient extends RemoteApiClient {
  _EmptyStreamApiClient()
    : super(
        apiEndpointUrl: 'http://localhost',
        apiEndpointUrlV2: 'http://localhost',
        authJwtExpiresIn: const Duration(minutes: 5),
        requestTimeout: const Duration(seconds: 5),
        userAgent: 'test',
      );

  @override
  Stream<OperationResponse<TData, TVars>> request<TData, TVars>(
    OperationRequest<TData, TVars> request, [
    Stream<OperationResponse<TData, TVars>> Function(
      OperationRequest<TData, TVars>,
    )?
    forward,
  ]) => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _GatedBeaconRepository implements BeaconRepository {
  final gate = Completer<Beacon>();
  final _changes = StreamController<RepositoryEvent<Beacon>>.broadcast();
  @override
  Stream<RepositoryEvent<Beacon>> get changes => _changes.stream;
  @override
  Future<Beacon> fetchBeaconById(String id) => gate.future;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _GatedThreadsRepository extends FakeBeaconThreadsRepository {
  _GatedThreadsRepository() : super(userId: _reader.id) {
    messages = [
      RoomMessage(
        id: _rootId,
        beaconId: _postId,
        authorId: _author.id,
        author: _author,
        body: 'Кто в субботу на велопрогулку?',
        createdAt: _createdAt,
      ),
    ];
    participants = [
      BeaconParticipant(
        id: 'p-${_reader.id}',
        beaconId: _postId,
        userId: _reader.id,
        role: BeaconParticipantRoleBits.addressee,
        status: 0,
        roomAccess: RoomAccessBits.admitted,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
    ];
  }
  final gate = Completer<List<RequestThread>>();
  @override
  Future<List<RequestThread>> fetchThreads(String beaconId) => gate.future;
}

class _ForwardRepository implements ForwardRepository {
  @override
  Future<List<ForwardEdge>> fetchEdges({required String beaconId}) async =>
      const [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PostsRepository implements PostsRepositoryPort {
  @override
  Future<List<PostSummary>> myPosts() async => const [];
  @override
  Future<PostSummary?> postSummary(String id) async => null;
}

class _ProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(profile: _reader);
  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

final _generalThreads = [
  RequestThread(
    threadId: RequestThread.generalId,
    kind: RequestThreadKind.general,
    lastSeenAt: _createdAt,
  ),
];

typedef _Harness = ({FakeUiEffectPort effects});

/// Pumps the Post's own scope. [beacons]: the real BeaconRepository over a
/// Link-less client when null. [threads]: the real BeaconThreadsRepository over
/// a Link-less client when null.
Future<_Harness> _open(
  WidgetTester tester, {
  BeaconRepository? beacons,
  BeaconThreadsRepository? threads,
  bool openParticipantsWhenReady = false,
}) async {
  final getIt = GetIt.I;
  await getIt.reset();
  addTearDown(getIt.reset);
  final sync = buildTestRealtimeSync();
  addTearDown(sync.port.dispose);
  addTearDown(() => PostParticipantsSheetRequest.instance.pending = '');
  final effects = FakeUiEffectPort();
  final profileCubit = _ProfileCubit();
  final threadsRepo =
      threads ?? BeaconThreadsRepository(_EmptyStreamApiClient(), sync.port);
  getIt
    ..registerSingleton<ProfileCubit>(profileCubit)
    ..registerSingleton<UiEffectPort>(effects)
    ..registerSingleton<ImageRepository>(ImageRepository())
    ..registerSingleton<ClipboardImageRepository>(ClipboardImageRepository())
    ..registerSingleton<ForwardRepository>(_ForwardRepository())
    ..registerSingleton<PostsRepositoryPort>(_PostsRepository())
    ..registerSingleton<BeaconRepository>(
      beacons ?? BeaconRepository(_EmptyStreamClient(), sync.port),
    )
    ..registerSingleton<BeaconThreadsCase>(
      BeaconThreadsCase(
        threadsRepo,
        FakeBeaconFactCardRepository(),
        FakePollingRepository(),
        FakeBeaconRoomHintsRepository(),
        RoomReadWatermarkStore.testing(),
        sync.case_,
      ),
    )
    ..registerSingleton<CoordinationItemRoomSync>(CoordinationItemRoomSync())
    ..registerSingleton<PresenceRepository>(
      roomCubitFakePresenceRepository(),
    );

  const surface = Size(700, 900);
  await tester.binding.setSurfaceSize(surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  await tester.pumpWidget(
    StackRouterScope(
      controller: BeaconViewHarnessRouter(),
      stateHash: 0,
      child: MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('ru'),
        home: MediaQuery(
          data: const MediaQueryData(size: surface),
          child: TenturaResponsiveScope(
            child: MultiBlocProvider(
              providers: [
                BlocProvider<ProfileCubit>.value(value: profileCubit),
                BlocProvider<PresenceCubit>.value(
                  value: RoomBodyHarnessPresenceCubit(),
                ),
                BlocProvider<ScreenCubit>(
                  create: (_) => ScreenCubit(effects),
                ),
              ],
              child: PostViewScope(
                id: _postId,
                myProfile: _reader,
                openParticipantsWhenReady: openParticipantsWhenReady,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await _frames(tester);
  return (effects: effects);
}

Future<void> _frames(WidgetTester tester, [int count = 10]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// Lets real async work (closing cubits, streams ending) run, then renders.
Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await _frames(tester, 5);
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await _settle(tester);
}

Finder get _enabledComposer => find.byWidgetPredicate(
  (w) => w is TextField && w.enabled != false,
);

void main() {
  group('Participants opener when the Post scope closes while loading', () {
    testWidgets('no error and no «О посте» sheet', (tester) async {
      final beacons = _GatedBeaconRepository();
      await _open(
        tester,
        beacons: beacons,
        threads: _GatedThreadsRepository(),
        openParticipantsWhenReady: true,
      );
      await _unmount(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(PostInfoSheet), findsNothing);
    });
  });

  group('One-shot participants request when the Post scope closes loading', () {
    testWidgets('no error, no sheet, and the request is used up', (
      tester,
    ) async {
      PostParticipantsSheetRequest.instance.pending = _postId;
      await _open(
        tester,
        beacons: _GatedBeaconRepository(),
        threads: _GatedThreadsRepository(),
      );
      await _unmount(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(PostInfoSheet), findsNothing);
      expect(PostParticipantsSheetRequest.instance.takeFor(_postId), isFalse);
    });
  });

  group('Participants opener when the Post loads', () {
    testWidgets('opens «О посте» exactly once, scrolled to participants', (
      tester,
    ) async {
      final beacons = _GatedBeaconRepository();
      final threads = _GatedThreadsRepository();
      await _open(
        tester,
        beacons: beacons,
        threads: threads,
        openParticipantsWhenReady: true,
      );
      expect(find.byType(PostInfoSheet), findsNothing);

      beacons.gate.complete(_post);
      threads.gate.complete(_generalThreads);
      await _settle(tester);
      await _frames(tester, 30);

      expect(tester.takeException(), isNull);
      expect(find.byType(PostInfoSheet), findsOneWidget);
      expect(
        tester
            .widget<PostInfoSheet>(find.byType(PostInfoSheet))
            .scrollToParticipants,
        isTrue,
      );
    });
  });

  group('Post whose load ends with no Link response', () {
    testWidgets('reports one load error, no uncaught error and keeps the '
        'screen up', (tester) async {
      final h = await _open(tester);
      await _settle(tester);

      expect(tester.takeException(), isNull);
      final errors = h.effects.emitted.whereType<ShowError>().toList();
      expect(errors, hasLength(1));
      expect(errors.single.error, isA<GraphQLNoDataException>());
      expect(errors.single.error, isNot(isA<StateError>()));
      expect(find.byType(PostViewScreen), findsOneWidget);
      // The Post never loaded: its author is not shown in the title.
      expect(find.text(_author.displayName), findsNothing);
      expect(find.byType(PostInfoSheet), findsNothing);
    });

    testWidgets('does not open «О посте» for the Post that failed to load', (
      tester,
    ) async {
      await _open(tester, openParticipantsWhenReady: true);
      await _settle(tester);
      await _frames(tester, 30);

      expect(tester.takeException(), isNull);
      expect(find.byType(PostInfoSheet), findsNothing);
    });
  });

  group('Post room when the screen closes while the thread list loads', () {
    testWidgets('no error and no room is set up afterwards', (tester) async {
      final beacons = _GatedBeaconRepository()..gate.complete(_post);
      final threads = _GatedThreadsRepository();
      await _open(tester, beacons: beacons, threads: threads);
      await _settle(tester);

      await _unmount(tester);
      // The thread list arrives only after the screen is gone: no room may be
      // set up for it.
      threads.gate.complete(_generalThreads);
      await _settle(tester);

      expect(tester.takeException(), isNull);
      expect(threads.fetchMessagesCallCount, 0);
      expect(threads.fetchParticipantsCallCount, 0);
      expect(find.byType(BeaconRoomBody), findsNothing);
    });

    testWidgets('once the thread list loads the room opens with its composer', (
      tester,
    ) async {
      final beacons = _GatedBeaconRepository()..gate.complete(_post);
      final threads = _GatedThreadsRepository();
      await _open(tester, beacons: beacons, threads: threads);
      await _settle(tester);
      expect(find.byType(BeaconRoomBody), findsNothing);

      threads.gate.complete(_generalThreads);
      for (var i = 0; i < 60; i++) {
        await _settle(tester);
        if (find.byType(BeaconRoomBody).evaluate().isNotEmpty) break;
      }

      expect(tester.takeException(), isNull);
      expect(find.byType(BeaconRoomBody), findsOneWidget);
      expect(_enabledComposer, findsOneWidget);
      final host = tester
          .element(find.byType(PostViewScreen))
          .read<ThreadHostCubit>();
      expect(host.state.openThreadId, RequestThread.generalId);
      expect(threads.fetchMessagesCallCount, greaterThan(0));
    });
  });

  group('Post thread list that ends with no Link response', () {
    // A Post's admission is never blocked and its room has no coordination
    // items, so the Request-only stand-in General room does not apply: the
    // failed list shows the empty placeholder.
    testWidgets(
      'a Post room shows the empty-room placeholder, no uncaught error',
      (
        tester,
      ) async {
        final beacons = _GatedBeaconRepository()..gate.complete(_post);
        await _open(tester, beacons: beacons);
        await _settle(tester);
        await _frames(tester, 20);

        expect(tester.takeException(), isNull);
        final l10n = L10n.of(tester.element(find.byType(PostViewScreen)))!;
        expect(find.text(l10n.beaconItemsEmptyPlaceholder), findsOneWidget);
      },
    );
  });
}
