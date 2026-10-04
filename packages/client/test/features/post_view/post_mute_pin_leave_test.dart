// A Post's ⋮ menu mutes («Заглушить» → 1 ч / 3 ч / день / 3 дня / навсегда,
// «Включить звук» when muted), pins in conversations («Закрепить в
// разговорах» / «Открепить», the existing favorites pin) and leaves
// («Выйти из разговора», recipients only, behind a confirm). The «Не
// интересно» archive brings a Post row back through `postReturn` and a
// Request row through the plain status change.
// UI copy is asserted verbatim in Russian (docs/plans/post-ux-mockups.md, M10).

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

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
import 'package:tentura/features/favorites/data/repository/favorites_remote_repository.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/forward_edge.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_item.dart';
import 'package:tentura/features/inbox/domain/entity/post_summary.dart';
import 'package:tentura/features/inbox/domain/enum.dart';
import 'package:tentura/features/inbox/domain/port/posts_repository_port.dart';
import 'package:tentura/features/inbox/ui/bloc/inbox_cubit.dart';
import 'package:tentura/features/inbox/ui/screen/inbox_rejected_screen.dart';
import 'package:tentura/features/post_view/ui/message/post_messages.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/features/post_view/data/repository/post_membership_repository.dart';
import 'package:tentura/features/post_view/data/repository/post_mute_repository.dart';
import 'package:tentura/features/post_view/ui/bloc/post_view_cubit.dart';
import 'package:tentura/features/post_view/ui/screen/post_view_screen.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import '../beacon_threads/support/room_body_harness.dart';
import '../beacon_view/beacon_view_screen_harness.dart'
    show BeaconViewHarnessRouter;
import '../inbox/inbox_case_test.dart'
    show FakeInboxRepository, buildTestBeaconThreadsCase, buildTestInboxCase;

const _postId = 'Bpostmute001';
const _rootId = 'Mpostroot001';
const _rootText = 'Кто в субботу на велопрогулку?';
const _author = Profile(id: 'Uauthor', displayName: 'Олег');
const _reader = Profile(id: 'Ureader', displayName: 'Мария');

final _createdAt = DateTime.utc(2026, 10, 2, 12);

/// The instant every mute duration is counted from (injected as the clock).
final _now = DateTime.utc(2026, 10, 3, 12);

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

RoomMessage _rootMessage() => RoomMessage(
  id: _rootId,
  beaconId: _postId,
  authorId: _author.id,
  author: _author,
  body: _rootText,
  createdAt: _createdAt,
);

PostSummary _summary({
  DateTime? mutedUntil,
  bool mutedForever = false,
  DateTime? pinnedAt,
}) => PostSummary(
  id: _postId,
  authorId: _author.id,
  authorName: _author.displayName,
  rootExcerpt: _rootText,
  lastActivityAt: _createdAt,
  mutedUntil: mutedUntil,
  mutedForever: mutedForever,
  pinnedAt: pinnedAt,
);

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
  Future<List<ForwardEdge>> fetchEdges({required String beaconId}) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePostsRepository implements PostsRepositoryPort {
  _FakePostsRepository(this.posts);

  final List<PostSummary> posts;

  @override
  Future<List<PostSummary>> myPosts() async => posts;

  @override
  Future<PostSummary?> postSummary(String id) async =>
      posts.where((p) => p.id == id).firstOrNull;
}

/// Records the mute writes the screen sends, by member.
class _RecordingMuteRepository implements PostMuteRepository {
  final setCalls = <({String beaconId, DateTime? mutedUntil})>[];
  final clearCalls = <String>[];

  @override
  Future<void> setMute({
    required String beaconId,
    DateTime? mutedUntil,
  }) async {
    setCalls.add((beaconId: beaconId, mutedUntil: mutedUntil));
  }

  @override
  Future<void> clearMute(String beaconId) async {
    clearCalls.add(beaconId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Records the two membership writes, named after the `postLeave` /
/// `postReturn` mutations they send. Any other member throws (no stub).
class _RecordingMembershipRepository implements PostMembershipRepository {
  final postLeaveCalls = <String>[];
  final postReturnCalls = <String>[];

  @override
  Future<void> postLeave(String beaconId) async {
    postLeaveCalls.add(beaconId);
  }

  @override
  Future<void> postReturn(String beaconId) async {
    postReturnCalls.add(beaconId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The existing favorites repository, recording pin / unpin.
class _RecordingFavoritesRepository implements FavoritesRemoteRepository {
  final pinCalls = <String>[];
  final unpinCalls = <({String userId, String beaconId})>[];

  @override
  Future<void> pin(Beacon beacon) async {
    pinCalls.add(beacon.id);
  }

  @override
  Future<void> unpin({required String userId, required Beacon beacon}) async {
    unpinCalls.add((userId: userId, beaconId: beacon.id));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ProfileCubit extends Mock implements ProfileCubit {
  _ProfileCubit(this.profile);

  final Profile profile;

  @override
  ProfileState get state => ProfileState(profile: profile);

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

class _Harness {
  _Harness({
    required this.mute,
    required this.membership,
    required this.favorites,
    required this.effects,
  });

  final _RecordingMuteRepository mute;
  final _RecordingMembershipRepository membership;
  final _RecordingFavoritesRepository favorites;
  final FakeUiEffectPort effects;
}

/// Pumps [PostViewScreen] for [viewer] with every write recorded.
Future<_Harness> _pumpPost(
  WidgetTester tester, {
  required Profile viewer,
  PostSummary? summary,
  int viewerRole = BeaconParticipantRoleBits.addressee,
}) async {
  final getIt = GetIt.I;
  await getIt.reset();
  addTearDown(getIt.reset);
  final profileCubit = _ProfileCubit(viewer);
  final mute = _RecordingMuteRepository();
  final membership = _RecordingMembershipRepository();
  final favorites = _RecordingFavoritesRepository();
  getIt
    ..registerSingleton<ProfileCubit>(profileCubit)
    ..registerSingleton<ImageRepository>(ImageRepository())
    ..registerSingleton<ClipboardImageRepository>(ClipboardImageRepository())
    ..registerSingleton<ForwardRepository>(_FakeForwardRepository())
    ..registerSingleton<PostsRepositoryPort>(
      _FakePostsRepository([summary ?? _summary()]),
    )
    ..registerSingleton<PostMuteRepository>(mute)
    ..registerSingleton<PostMembershipRepository>(membership)
    ..registerSingleton<FavoritesRemoteRepository>(favorites);

  final effects = FakeUiEffectPort();
  final cubit = PostViewCubit(
    id: _postId,
    myProfile: viewer,
    beaconRepository: _PostRepository(_post()),
    effects: effects,
    clock: () => _now,
  );
  addTearDown(cubit.close);
  await cubit.fetch();

  final room = _RoomCubit(
    roomBodyState(
      beaconId: _postId,
      myUserId: viewer.id,
      messages: [_rootMessage()],
    ).copyWith(
      participants: [
        roomBodyAdmittedParticipant(
          beaconId: _postId,
          profile: viewer,
          role: viewer.id == _author.id
              ? BeaconParticipantRoleBits.author
              : viewerRole,
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
          required String beaconId,
          String? threadItemId,
          DateTime? initialUnreadAnchorAt,
          RoomCapabilities capabilities = const RoomCapabilities.request(),
        }) => room,
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    // close() needs the fake-async microtask queue pumped to complete;
    // awaiting it bare hangs (it used to be masked by a 5 s timeout per test).
    final closing = threadHost.close();
    await tester.pump();
    await closing;
  });

  final general = RequestThread(
    threadId: RequestThread.generalId,
    kind: RequestThreadKind.general,
    lastSeenAt: _createdAt,
  );

  await tester.binding.setSurfaceSize(const Size(700, 900));
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
          data: const MediaQueryData(size: Size(700, 900)),
          child: TenturaResponsiveScope(
            child: MultiBlocProvider(
              providers: [
                BlocProvider<PostViewCubit>.value(value: cubit),
                BlocProvider<ThreadsCubit>.value(
                  value: _MockThreadsCubit(
                    ThreadsState(
                      threads: [general],
                      myUserId: viewer.id,
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
  await tester.pump(const Duration(milliseconds: 100));
  expect(find.byType(BeaconRoomBody), findsOneWidget);

  return _Harness(
    mute: mute,
    membership: membership,
    favorites: favorites,
    effects: effects,
  );
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _openOverflow(WidgetTester tester) async {
  final button = find.descendant(
    of: find.byType(AppBar),
    matching: find.byIcon(Icons.more_vert),
  );
  expect(button, findsOneWidget);
  await tester.tap(button);
  await _settle(tester);
}

/// Opens ⋮ and taps the item whose copy contains [label].
Future<void> _pickMenuItem(WidgetTester tester, String label) async {
  await _openOverflow(tester);
  final item = find.textContaining(label);
  expect(item, findsOneWidget);
  await tester.tap(item);
  await _settle(tester);
}

Finder _confirmDialog() => find.byType(AlertDialog);

Finder _inDialog(Finder f) =>
    find.descendant(of: _confirmDialog(), matching: f);

// ── «Не интересно» archive ──────────────────────────────────────────────────

const _archivedPostId = 'Barchivedpost1';
const _archivedRequestId = 'Barchivedreq01';

InboxItem _rejectedItem({required String id, required BeaconKind kind}) =>
    InboxItem(
      beaconId: id,
      latestForwardAt: _createdAt,
      status: InboxItemStatus.rejected,
      beacon: Beacon(
        id: id,
        kind: kind,
        title: kind == BeaconKind.request ? 'Нужна помощь с переездом' : '',
        author: _author,
        createdAt: _createdAt,
        updatedAt: _createdAt,
      ),
    );

class _Archive {
  _Archive({required this.inbox, required this.membership});

  final FakeInboxRepository inbox;
  final _RecordingMembershipRepository membership;
}

/// Pumps the declined archive (a real [InboxCubit] over fake repositories)
/// holding one rejected Post and one rejected Request.
Future<_Archive> _pumpArchive(WidgetTester tester) async {
  final getIt = GetIt.I;
  await getIt.reset();
  addTearDown(getIt.reset);
  final membership = _RecordingMembershipRepository();
  getIt.registerSingleton<PostMembershipRepository>(membership);

  final inbox = FakeInboxRepository()
    ..fetchResult = [
      _rejectedItem(id: _archivedPostId, kind: BeaconKind.post),
      _rejectedItem(id: _archivedRequestId, kind: BeaconKind.request),
    ];
  addTearDown(inbox.dispose);
  final cubit = InboxCubit(
    userId: _reader.id,
    inboxCase: buildTestInboxCase(inbox, buildTestBeaconThreadsCase()),
    postMembershipRepository: membership,
    effects: FakeUiEffectPort(),
  );
  addTearDown(cubit.close);
  await cubit.stream.firstWhere((s) => s.isSuccess);

  await tester.binding.setSurfaceSize(const Size(400, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    StackRouterScope(
      controller: BeaconViewHarnessRouter(),
      stateHash: 0,
      child: MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('en'),
        home: MediaQuery(
          data: const MediaQueryData(size: Size(400, 900)),
          child: TenturaResponsiveScope(
            child: MultiBlocProvider(
              providers: [
                BlocProvider<InboxCubit>.value(value: cubit),
                BlocProvider<ProfileCubit>.value(
                  value: _ProfileCubit(_reader),
                ),
                BlocProvider<ScreenCubit>(
                  create: (_) => ScreenCubit.local(),
                ),
              ],
              child: const InboxRejectedScreen(),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  expect(find.byType(Scrollable), findsWidgets);
  return _Archive(inbox: inbox, membership: membership);
}

/// Taps ⋮ on the archive row of [beaconId], then «Move to Activity».
Future<void> _moveRowBack(WidgetTester tester, String beaconId) async {
  final l10n = lookupL10n(const Locale('en'));
  final row = find.byKey(ValueKey(beaconId));
  expect(row, findsOneWidget);
  await tester.tap(
    find.descendant(of: row, matching: find.byIcon(Icons.more_vert)),
  );
  await _settle(tester);
  await tester.tap(find.text(l10n.actionMoveToInbox));
  await _settle(tester);
}

void main() {
  group('Muting a Post from its ⋮ menu', () {
    const durations = <(String, Duration)>[
      ('На 1 час', Duration(hours: 1)),
      ('На 3 часа', Duration(hours: 3)),
      ('На день', Duration(days: 1)),
      ('На 3 дня', Duration(days: 3)),
    ];

    for (final (label, duration) in durations) {
      testWidgets('«$label» mutes until that long after now', (tester) async {
        final h = await _pumpPost(tester, viewer: _reader);

        await _pickMenuItem(tester, 'Заглушить');
        await tester.tap(find.text(label));
        await _settle(tester);

        expect(h.mute.setCalls, hasLength(1));
        expect(h.mute.setCalls.single.beaconId, _postId);
        // Counted from the injected clock, so the instant is exact.
        expect(
          h.mute.setCalls.single.mutedUntil?.isAtSameMomentAs(
            _now.add(duration),
          ),
          isTrue,
          reason: 'expected ${_now.add(duration)}, '
              'got ${h.mute.setCalls.single.mutedUntil}',
        );
        expect(h.mute.clearCalls, isEmpty);
      });
    }

    testWidgets('«Навсегда» mutes with no end time', (tester) async {
      final h = await _pumpPost(tester, viewer: _reader);

      await _pickMenuItem(tester, 'Заглушить');
      await tester.tap(find.text('Навсегда'));
      await _settle(tester);

      expect(h.mute.setCalls, hasLength(1));
      expect(h.mute.setCalls.single.beaconId, _postId);
      expect(h.mute.setCalls.single.mutedUntil, isNull);
    });

    testWidgets('offers all five durations after «Заглушить»', (tester) async {
      await _pumpPost(tester, viewer: _reader);

      await _pickMenuItem(tester, 'Заглушить');

      for (final label in const [
        'На 1 час',
        'На 3 часа',
        'На день',
        'На 3 дня',
        'Навсегда',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
    });

    testWidgets('a muted Post offers «Включить звук» instead and clears the '
        'mute', (tester) async {
      final h = await _pumpPost(
        tester,
        viewer: _reader,
        summary: _summary(mutedUntil: DateTime.utc(2100)),
      );

      await _openOverflow(tester);
      expect(find.textContaining('Заглушить'), findsNothing);
      expect(find.textContaining('Включить звук'), findsOneWidget);

      await tester.tap(find.textContaining('Включить звук'));
      await _settle(tester);

      expect(h.mute.clearCalls, [_postId]);
      expect(h.mute.setCalls, isEmpty);
    });
  });

  group('Mute state in the ⋮ menu', () {
    testWidgets('a Post muted for good says so and can be unmuted', (
      tester,
    ) async {
      final h = await _pumpPost(
        tester,
        viewer: _reader,
        summary: _summary(mutedForever: true),
      );

      await _openOverflow(tester);
      expect(
        find.text('Включить звук · заглушено навсегда'),
        findsOneWidget,
      );
      await tester.tap(find.text('Включить звук · заглушено навсегда'));
      await _settle(tester);

      expect(h.mute.clearCalls, [_postId]);
    });

    testWidgets('a timed mute shows when it ends', (tester) async {
      await _pumpPost(
        tester,
        viewer: _reader,
        summary: _summary(mutedUntil: DateTime.utc(2100, 1, 2, 3, 4)),
      );

      await _openOverflow(tester);

      expect(
        find.textContaining('Включить звук · заглушено до '),
        findsOneWidget,
      );
    });
  });

  group('Pinning a Post in conversations from its ⋮ menu', () {
    testWidgets('«Закрепить в разговорах» pins through favorites', (
      tester,
    ) async {
      final h = await _pumpPost(tester, viewer: _reader);

      await _pickMenuItem(tester, 'Закрепить в разговорах');

      expect(h.favorites.pinCalls, [_postId]);
      expect(h.favorites.unpinCalls, isEmpty);
    });

    testWidgets('a pinned Post offers «Открепить» instead and unpins', (
      tester,
    ) async {
      final h = await _pumpPost(
        tester,
        viewer: _reader,
        summary: _summary(pinnedAt: _createdAt),
      );

      await _openOverflow(tester);
      expect(find.textContaining('Закрепить в разговорах'), findsNothing);
      expect(find.textContaining('Открепить'), findsOneWidget);

      await tester.tap(find.textContaining('Открепить'));
      await _settle(tester);

      expect(h.favorites.unpinCalls, [(userId: _reader.id, beaconId: _postId)]);
      expect(h.favorites.pinCalls, isEmpty);
    });
  });

  group('Leaving a Post from its ⋮ menu', () {
    testWidgets('asks first and leaves only after «Выйти»', (tester) async {
      final h = await _pumpPost(tester, viewer: _reader);

      await _pickMenuItem(tester, 'Выйти из разговора');

      expect(_confirmDialog(), findsOneWidget);
      expect(_inDialog(find.text('Выйти из разговора?')), findsOneWidget);
      expect(h.membership.postLeaveCalls, isEmpty);

      await tester.tap(_inDialog(find.byType(FilledButton)));
      await _settle(tester);

      expect(h.membership.postLeaveCalls, [_postId]);
      expect(h.membership.postReturnCalls, isEmpty);
    });

    testWidgets('after leaving, «Вернуть» brings the member back and reopens '
        'the Post', (tester) async {
      final h = await _pumpPost(tester, viewer: _reader);

      await _pickMenuItem(tester, 'Выйти из разговора');
      await tester.tap(_inDialog(find.byType(FilledButton)));
      await _settle(tester);

      final message = h.effects.emitted
          .whereType<ShowMessage>()
          .map((e) => e.message)
          .whereType<PostLeftMessage>()
          .single;
      expect(message.toRu, 'Вы вышли из разговора');
      expect(message.label.toRu, 'Вернуть');

      message.onPressed();
      await _settle(tester);

      expect(h.membership.postReturnCalls, [_postId]);
      expect(
        h.effects.emitted.whereType<NavigatePush>().map((e) => e.path),
        contains('/beacon/view/$_postId'),
      );
    });

    testWidgets('cancelling the confirm does not leave', (tester) async {
      final h = await _pumpPost(tester, viewer: _reader);

      await _pickMenuItem(tester, 'Выйти из разговора');
      await tester.tap(_inDialog(find.byType(TextButton)));
      await _settle(tester);

      expect(_confirmDialog(), findsNothing);
      expect(h.membership.postLeaveCalls, isEmpty);
    });

    testWidgets('a member who is not an addressee is not offered «Выйти из '
        'разговора»', (tester) async {
      await _pumpPost(
        tester,
        viewer: _reader,
        viewerRole: BeaconParticipantRoleBits.helper,
      );

      await _openOverflow(tester);

      // Positive anchor: the menu is open and has the shared items.
      expect(find.text('О посте'), findsOneWidget);
      expect(find.textContaining('Выйти'), findsNothing);
    });

    testWidgets('the author is not offered «Выйти из разговора»', (
      tester,
    ) async {
      await _pumpPost(tester, viewer: _author);

      await _openOverflow(tester);

      // Positive anchor: the menu is open and has the author's own items.
      expect(find.text('О посте'), findsOneWidget);
      expect(find.textContaining('Выйти'), findsNothing);
    });
  });

  group('Bringing a row back from the «Не интересно» archive', () {
    testWidgets('a Post row returns through postReturn', (tester) async {
      final a = await _pumpArchive(tester);

      await _moveRowBack(tester, _archivedPostId);

      expect(a.membership.postReturnCalls, [_archivedPostId]);
      expect(a.inbox.lastSetStatus, isNull);
    });

    testWidgets('a Request row keeps the plain status change', (tester) async {
      final a = await _pumpArchive(tester);

      await _moveRowBack(tester, _archivedRequestId);

      expect(a.inbox.lastSetStatus?.beaconId, _archivedRequestId);
      // `InboxCubit.unreject`: back to «needs me» with no rejection note.
      expect(a.inbox.lastSetStatus?.status, InboxItemStatus.needsMe);
      expect(a.inbox.lastSetStatus?.rejectionMessage, isEmpty);
      expect(a.membership.postReturnCalls, isEmpty);
    });
  });
}
