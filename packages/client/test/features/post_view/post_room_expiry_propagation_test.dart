// A Post's room locks the moment the Post is archived by time, not only by
// status. A remote shorten (status still open, `expiresAt` now in the past)
// must reach an open room, and the clock passing `expiresAt` must do the same
// with no network event: the composer closes, a started reply is dropped and
// a send is refused. Built on the real PostViewScope → ThreadHostCubit →
// RoomCubit chain.

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/data/repository/presence_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/beacon_threads/domain/coordination_item_room_sync.dart';
import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/thread_host_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_room_body.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/forward_edge.dart';
import 'package:tentura/features/inbox/domain/entity/post_summary.dart';
import 'package:tentura/features/inbox/domain/port/posts_repository_port.dart';
import 'package:tentura/features/post_view/ui/screen/post_view_scope.dart';
import 'package:tentura/features/post_view/ui/screen/post_view_screen.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
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
const _archivedHint =
    'Пост в архиве — писать нельзя. Продолжить разговор можно в запросе.';
const _budLabel = 'Оформить запрос';

final _root = RoomMessage(
  id: _rootId,
  beaconId: _postId,
  authorId: _author.id,
  author: _author,
  body: 'Кто в субботу на велопрогулку?',
  createdAt: _createdAt,
);
Beacon _post({required DateTime expiresAt}) => Beacon(
  id: _postId,
  kind: BeaconKind.post,
  createdAt: _createdAt,
  updatedAt: _createdAt,
  author: _author,
  expiresAt: expiresAt,
  postRootMessageId: _rootId,
);

/// The Post as the server has it; [push] is a remote change of it.
class _PostRepository implements BeaconRepository {
  _PostRepository(this.beacon);
  Beacon beacon;
  final _changes = StreamController<RepositoryEvent<Beacon>>.broadcast();
  void push(Beacon next) {
    beacon = next;
    _changes.add(RepositoryEventUpdate(next));
  }

  @override
  Future<void> dispose() => _changes.close();

  @override
  Stream<RepositoryEvent<Beacon>> get changes => _changes.stream;
  @override
  Future<Beacon> fetchBeaconById(String id) async => beacon;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The Post's room: the root message and the viewer admitted.
class _RoomRepository extends FakeBeaconThreadsRepository {
  _RoomRepository() : super(userId: _reader.id) {
    messages = [_root];
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

  @override
  Future<List<RequestThread>> fetchThreads(String beaconId) async => [
    RequestThread(
      threadId: RequestThread.generalId,
      kind: RequestThreadKind.general,
      lastSeenAt: _createdAt,
    ),
  ];
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

typedef _Harness = ({_PostRepository posts, _RoomRepository room});

/// Opens the Post through its scope, as its route does. Keeps fake time spent
/// here short: the clock test's deadline is only seconds away.
Future<_Harness> _openPost(
  WidgetTester tester, {
  required DateTime expiresAt,
  void Function()? onRoomShown,
}) async {
  final getIt = GetIt.I;
  await getIt.reset();
  addTearDown(getIt.reset);
  final sync = buildTestRealtimeSync();
  addTearDown(sync.port.dispose);
  final posts = _PostRepository(_post(expiresAt: expiresAt));
  addTearDown(posts.dispose);
  final room = _RoomRepository();
  addTearDown(room.dispose);
  final profileCubit = _ProfileCubit();
  final effects = FakeUiEffectPort();
  getIt
    ..registerSingleton<ProfileCubit>(profileCubit)
    ..registerSingleton<UiEffectPort>(effects)
    ..registerSingleton<ImageRepository>(ImageRepository())
    ..registerSingleton<ClipboardImageRepository>(ClipboardImageRepository())
    ..registerSingleton<ForwardRepository>(_ForwardRepository())
    ..registerSingleton<PostsRepositoryPort>(_PostsRepository())
    ..registerSingleton<BeaconRepository>(posts)
    ..registerSingleton<BeaconThreadsCase>(
      roomCubitMakeCase(room, realtimeSyncCase: sync.case_),
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
              child: const PostViewScope(id: _postId, myProfile: _reader),
            ),
          ),
        ),
      ),
    ),
  );
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    if (find.byType(BeaconRoomBody).evaluate().isNotEmpty) break;
  }
  onRoomShown?.call();
  await _frames(tester);
  expect(find.byType(BeaconRoomBody), findsOneWidget);
  return (posts: posts, room: room);
}

Future<void> _frames(WidgetTester tester, [int count = 10]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

RoomCubit _roomCubit(WidgetTester tester) => tester
    .element(find.byType(PostViewScreen))
    .read<ThreadHostCubit>()
    .roomCubit!;

Finder _inRoom(Finder finder) =>
    find.descendant(of: find.byType(BeaconRoomBody), matching: finder);

/// A text field in the room a member could type into.
final _enabledComposer = _inRoom(
  find.byWidgetPredicate((w) => w is TextField && w.enabled != false),
);

/// The open Post before expiry: the composer works and a reply is started.
Future<RoomCubit> _startReply(WidgetTester tester) async {
  final room = _roomCubit(tester);
  expect(_enabledComposer, findsOneWidget);
  expect(find.text(_archivedHint), findsNothing);
  expect(_inRoom(find.text(_budLabel)), findsNothing);
  room.startReplyTo(_root);
  await _frames(tester);
  expect(room.state.replyTarget?.id, _rootId);
  return room;
}

/// The read-only shell of an archived room: hint and «Оформить запрос» in
/// place of the composer.
void _expectReadOnlyShell() {
  expect(_enabledComposer, findsNothing);
  expect(_inRoom(find.text(_archivedHint)), findsOneWidget);
  expect(_inRoom(find.text(_budLabel)), findsOneWidget);
}

/// What an archived room looks like after the flip.
Future<void> _expectLocked(
  WidgetTester tester,
  RoomCubit room,
  _RoomRepository repository,
) async {
  _expectReadOnlyShell();
  expect(room.state.replyTarget, isNull);
  expect(await room.sendMessage(body: 'Опоздал?'), isFalse);
  expect(repository.createMessageCalls, 0);
}

void main() {
  group('Post room locks at expiry', () {
    testWidgets('a remote shorten into the past (status still open) closes '
        'the composer and drops a started reply', (tester) async {
      final h = await _openPost(
        tester,
        expiresAt: DateTime.now().add(const Duration(hours: 5)),
      );
      final room = await _startReply(tester);
      h.posts.push(
        h.posts.beacon.copyWith(
          status: BeaconStatus.open,
          expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
        ),
      );
      await _frames(tester, 20);
      await _expectLocked(tester, room, h.room);
    });

    testWidgets('the clock passing expiresAt does the same with no update', (
      tester,
    ) async {
      final h = await _openPost(
        tester,
        expiresAt: DateTime.now().add(const Duration(seconds: 4)),
      );
      final room = await _startReply(tester);
      // Let both real and fake time pass the deadline; nothing is pushed.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 5)),
      );
      await tester.pump(const Duration(seconds: 5));
      await _frames(tester, 20);

      await _expectLocked(tester, room, h.room);
    });
  });

  group('Post opened after expiry', () {
    testWidgets('an open Post already past expiresAt shows the read-only '
        'room from its first frame', (tester) async {
      var composerOnFirstFrame = -1;
      final h = await _openPost(
        tester,
        expiresAt: DateTime.now().subtract(const Duration(hours: 1)),
        onRoomShown: () =>
            composerOnFirstFrame = _enabledComposer.evaluate().length,
      );
      expect(composerOnFirstFrame, 0);
      _expectReadOnlyShell();

      final room = _roomCubit(tester);
      expect(await room.sendMessage(body: 'Опоздал?'), isFalse);
      expect(h.room.createMessageCalls, 0);
    });
  });
}
