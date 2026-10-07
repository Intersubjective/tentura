// Opening a Post is reading its room: the read watermark reaches the server as
// soon as the message list is at the bottom (on open, or after scrolling
// there), exactly as it does in a Request chat — the viewer never has to send a
// message to clear the unread state. «Clear» includes the Post's unread badge
// (and the Conversations dot) in the «Разговоры» list, which the viewer sees
// next.

import 'package:auto_route/auto_route.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/beacon_threads/domain/coordination_item_room_sync.dart';
import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';
import 'package:tentura/features/beacon_threads/domain/room_host.dart';
import 'package:tentura/features/beacon_threads/domain/room_read_watermark_store.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/thread_host_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/threads_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/threads_state.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_room_body.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/forward_edge.dart';
import 'package:tentura/features/inbox/domain/entity/post_summary.dart';
import 'package:tentura/features/inbox/domain/port/posts_repository_port.dart';
import 'package:tentura/features/inbox/domain/use_case/posts_case.dart';
import 'package:tentura/features/inbox/ui/bloc/posts_cubit.dart';
import 'package:tentura/features/post_view/ui/bloc/post_view_cubit.dart';
import 'package:tentura/features/post_view/ui/screen/post_view_screen.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../beacon_threads/room_cubit_fakes.dart';
import '../beacon_threads/support/room_body_harness.dart'
    show RoomBodyHarnessPresenceCubit;
import '../beacon_view/beacon_view_screen_harness.dart'
    show BeaconViewHarnessRouter;

const _postId = 'Bpostread001';
const _rootId = 'Mpostreadroot';
const _author = Profile(id: 'Uauthor', displayName: 'Олег');
const _reader = Profile(id: 'Ureader', displayName: 'Мария');
const _other = Profile(id: 'Uother', displayName: 'Дима');

final _createdAt = DateTime.utc(2026, 10, 2, 12);

/// The reader last saw the room just after the root message.
final _seenAt = _createdAt.add(const Duration(seconds: 30));

Beacon _post() => Beacon(
  id: _postId,
  kind: BeaconKind.post,
  createdAt: _createdAt,
  updatedAt: _createdAt,
  status: BeaconStatus.open,
  canReadContent: true,
  author: _author,
  postRootMessageId: _rootId,
);

RoomMessage _message(
  String id, {
  required String body,
  required Profile author,
  required DateTime at,
}) => RoomMessage(
  id: id,
  beaconId: _postId,
  authorId: author.id,
  author: author,
  body: body,
  createdAt: at,
);

/// The root (already read) followed by [unread] peer replies the reader has not
/// seen.
List<RoomMessage> _conversation(int unread) => [
  _message(
    _rootId,
    body: 'Кто в субботу на велопрогулку?',
    author: _author,
    at: _createdAt,
  ),
  for (var i = 0; i < unread; i++)
    _message(
      'Mreply$i',
      body: 'Ответ номер $i',
      author: _other,
      at: _seenAt.add(Duration(minutes: i + 1)),
    ),
];

/// Room repository that records every read watermark flushed to the server.
class _RecordingRoomRepository extends FakeBeaconThreadsRepository {
  _RecordingRoomRepository() : super(userId: _reader.id) {
    participants = [
      BeaconParticipant(
        id: 'p-${_reader.id}',
        beaconId: _postId,
        userId: _reader.id,
        role: 0,
        status: 0,
        roomAccess: 1,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        lastSeenRoomAt: _seenAt,
      ),
    ];
  }

  final List<DateTime> seenThrough = [];

  @override
  Future<DateTime> markThreadSeen({
    required String beaconId,
    required String threadId,
    required DateTime readThroughAt,
  }) async {
    seenThrough.add(readThroughAt);
    return readThroughAt;
  }
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

class _FakeForwardRepository implements ForwardRepository {
  @override
  Future<List<ForwardEdge>> fetchEdges({required String beaconId}) async =>
      const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The «Разговоры» list as the server answers it: a Post's unread count is what
/// its room still holds past the read watermark the viewer last flushed.
class _ServerPostsRepository implements PostsRepositoryPort {
  _ServerPostsRepository(this._room);

  final _RecordingRoomRepository _room;

  PostSummary _current() {
    final readThrough = _room.seenThrough.isEmpty
        ? _seenAt
        : _room.seenThrough.last;
    return PostSummary(
      id: _postId,
      authorId: _author.id,
      authorName: _author.displayName,
      rootExcerpt: 'Кто в субботу на велопрогулку?',
      lastActivityAt: _room.messages.last.createdAt,
      unreadCount: _room.messages
          .where(
            (m) => m.authorId != _reader.id && m.createdAt.isAfter(readThrough),
          )
          .length,
    );
  }

  @override
  Future<List<PostSummary>> myPosts() async => [_current()];

  @override
  Future<PostSummary?> postSummary(String id) async => _current();
}

class _ProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(profile: _reader);

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

class _MockThreadsCubit extends Mock implements ThreadsCubit {
  _MockThreadsCubit(this._state);

  final ThreadsState _state;

  @override
  ThreadsState get state => _state;

  @override
  Stream<ThreadsState> get stream => Stream.value(_state);

  @override
  Future<void> fetch({bool silent = false}) async {}
}

RoomCubit _realRoomCubit(
  _RecordingRoomRepository repository, {
  required RoomCapabilities capabilities,
  required RoomReadWatermarkStore watermarks,
  required RealtimeSyncCase realtimeSync,
  DateTime? initialUnreadAnchorAt,
}) => RoomCubit(
  beaconId: _postId,
  initialUnreadAnchorAt: initialUnreadAnchorAt,
  beaconRoomCase: roomCubitMakeCase(
    repository,
    realtimeSyncCase: realtimeSync,
    watermarkStore: watermarks,
  ),
  coordinationItemRoomSync: CoordinationItemRoomSync(),
  presenceRepository: roomCubitFakePresenceRepository(),
  effects: FakeUiEffectPort(),
  capabilities: capabilities,
);

Future<void> _pumpFrames(WidgetTester tester, [int frames = 40]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// What the viewer touches in one session: the open Post's room and the
/// «Разговоры» list it came from, sharing one read state.
typedef _Session = ({RoomCubit room, PostsCase postsCase, PostsCubit list});

/// Opens the «Разговоры» list, then the Post screen over a real [RoomCubit]
/// fed by [repository].
Future<_Session> _openPostFromConversations(
  WidgetTester tester,
  _RecordingRoomRepository repository,
) async {
  final getIt = GetIt.I;
  await getIt.reset();
  addTearDown(getIt.reset);
  final sync = buildTestRealtimeSync();
  addTearDown(sync.port.dispose);
  final watermarks = RoomReadWatermarkStore.testing();
  final postsRepository = _ServerPostsRepository(repository);
  final profileCubit = _ProfileCubit();
  getIt
    ..registerSingleton<ProfileCubit>(profileCubit)
    ..registerSingleton<ImageRepository>(ImageRepository())
    ..registerSingleton<ClipboardImageRepository>(ClipboardImageRepository())
    ..registerSingleton<ForwardRepository>(_FakeForwardRepository())
    ..registerSingleton<PostsRepositoryPort>(postsRepository)
    ..registerSingleton<RoomReadWatermarkStore>(watermarks);

  final postsCase = _makePostsCase(postsRepository, sync.case_);
  final list = PostsCubit(
    postsCase: postsCase,
    clock: () => _createdAt.add(const Duration(hours: 1)),
  );
  addTearDown(list.close);
  await list.fetch();

  final effects = FakeUiEffectPort();
  final postCubit = PostViewCubit(
    id: _postId,
    myProfile: _reader,
    beaconRepository: _PostRepository(_post()),
    effects: effects,
  );
  addTearDown(postCubit.close);
  await postCubit.fetch();

  late RoomCubit room;
  final threadHost = ThreadHostCubit(
    beaconId: _postId,
    capabilities: const RoomCapabilities.post(),
    roomCubitFactory:
        ({
          required String beaconId,
          String? threadItemId,
          DateTime? initialUnreadAnchorAt,
          RoomCapabilities capabilities = const RoomCapabilities.request(),
        }) => room = _realRoomCubit(
          repository,
          capabilities: capabilities,
          watermarks: watermarks,
          realtimeSync: sync.case_,
          initialUnreadAnchorAt: initialUnreadAnchorAt,
        ),
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
    lastSeenAt: _seenAt,
  );
  const surface = Size(700, 900);
  await tester.binding.setSurfaceSize(surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));

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
                BlocProvider<PostViewCubit>.value(value: postCubit),
                BlocProvider<ThreadsCubit>.value(
                  value: _MockThreadsCubit(
                    ThreadsState(
                      threads: [general],
                      myUserId: _reader.id,
                      status: const StateIsSuccess(),
                    ),
                  ),
                ),
                BlocProvider<ThreadHostCubit>.value(value: threadHost),
                BlocProvider<ProfileCubit>.value(value: profileCubit),
                BlocProvider<PresenceCubit>.value(
                  value: RoomBodyHarnessPresenceCubit(),
                ),
                BlocProvider<ScreenCubit>(
                  create: (_) => ScreenCubit(effects),
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
  await _pumpFrames(tester);
  expect(find.byType(BeaconRoomBody), findsOneWidget);
  return (room: room, postsCase: postsCase, list: list);
}

PostsCase _makePostsCase(
  PostsRepositoryPort repository,
  RealtimeSyncCase realtimeSync,
) => PostsCase(
  repository,
  realtimeSync,
  env: const Env(),
  logger: Logger('post-read-state-test'),
);

/// The unread count the «Разговоры» list shows for the Post under test.
int _listUnread(PostsCubit list) => list.state.active
    .followedBy(list.state.quiet)
    .followedBy(list.state.pinned)
    .singleWhere((p) => p.id == _postId)
    .unreadCount;

Finder _messageList() => find
    .descendant(
      of: find.byType(BeaconRoomBody),
      matching: find.byType(ListView),
    )
    .first;

/// Pixels of message list still below the viewport.
double _scrollRemaining(WidgetTester tester) {
  final position = tester
      .state<ScrollableState>(
        find.descendant(of: _messageList(), matching: find.byType(Scrollable)),
      )
      .position;
  return position.maxScrollExtent - position.pixels;
}

Future<void> _dragListToBottom(WidgetTester tester) async {
  final list = _messageList();
  for (var i = 0; i < 12; i++) {
    await tester.drag(
      list,
      const Offset(0, -600),
      kind: PointerDeviceKind.touch,
    );
    await _pumpFrames(tester, 6);
  }
  await _pumpFrames(tester);
}

void main() {
  group('Post room read state', () {
    testWidgets(
      'opening a Post with unread replies at the bottom marks it read without sending',
      (tester) async {
        final repository = _RecordingRoomRepository()
          ..messages = _conversation(3);
        addTearDown(repository.dispose);
        final session = await _openPostFromConversations(tester, repository);
        addTearDown(session.room.close);

        expect(
          _scrollRemaining(tester),
          lessThan(1),
          reason: 'precondition: the message list is at the bottom on open',
        );
        expect(
          repository.seenThrough,
          isNotEmpty,
          reason: 'the room list is at the bottom, so it counts as read',
        );
        expect(
          repository.seenThrough.last,
          _conversation(3).last.createdAt,
          reason: 'the watermark covers the newest loaded message',
        );
        expect(repository.createMessageCalls, 0);
        expect(session.room.state.unreadCount, 0);
        expect(session.room.state.firstUnreadMessageId, isNull);
        expect(
          _listUnread(session.list),
          0,
          reason: 'the Conversations badge clears once the Post has been read',
        );
        expect(session.postsCase.hasUnread, isFalse);
      },
    );

    testWidgets(
      'scrolling an initially not-at-bottom Post list to the bottom marks it read',
      (tester) async {
        final repository = _RecordingRoomRepository()
          ..messages = _conversation(60);
        addTearDown(repository.dispose);
        final session = await _openPostFromConversations(tester, repository);
        addTearDown(session.room.close);

        expect(
          session.room.state.unreadCount,
          greaterThan(0),
          reason:
              'long unread tail keeps the list away from the bottom on open',
        );
        expect(repository.seenThrough, isEmpty);
        expect(
          _listUnread(session.list),
          60,
          reason: 'nothing is read while the tail is still below the fold',
        );
        expect(session.postsCase.hasUnread, isTrue);
        expect(
          _scrollRemaining(tester),
          greaterThan(100),
          reason: 'precondition: the message list is not at the bottom on open',
        );

        await _dragListToBottom(tester);

        expect(_scrollRemaining(tester), lessThan(1));

        expect(repository.seenThrough, isNotEmpty);
        expect(
          repository.seenThrough.last,
          _conversation(60).last.createdAt,
        );
        expect(repository.createMessageCalls, 0);
        expect(session.room.state.unreadCount, 0);
        expect(session.room.state.firstUnreadMessageId, isNull);
        expect(_listUnread(session.list), 0);
        expect(session.postsCase.hasUnread, isFalse);
      },
    );
  });
}
