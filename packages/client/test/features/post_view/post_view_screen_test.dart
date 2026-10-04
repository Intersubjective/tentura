// The Post screen is the room under an app bar «<author>: <root excerpt>» over
// «N участников» (🔕 when muted) that opens «О посте» on tap, with ↗ for a
// member who may forward and a short ⋮ menu («О посте», mute, pin, complain /
// delete). «О посте» holds the participants, the forwarding graph, show on
// field, forward, allow forwarding and the author's actions. A pinned strip
// shows the root excerpt (tap scrolls to the root; «‹X› переслал(а) вам:
// «‹note›»» for a forwarded recipient), and a Post-specific «Удалить пост?»
// confirm comes before the root message is deleted. No tabs and no Request
// HUD.
// UI copy is asserted verbatim in Russian (docs/plans/post-ux-mockups.md).

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
import 'package:tentura/domain/entity/beacon_room_state.dart';
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
import 'package:tentura/features/beacon_threads/ui/widget/room_message_text_body.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_now_surface.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_operational_header_card.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_people_tab_body.dart';
import 'package:tentura/features/constellation/ui/util/constellation_focus_request.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/forward_edge.dart';
import 'package:tentura/features/inbox/domain/entity/post_summary.dart';
import 'package:tentura/features/inbox/domain/port/posts_repository_port.dart';
import 'package:tentura/features/post_view/ui/bloc/post_view_cubit.dart';
import 'package:tentura/features/post_view/ui/screen/post_view_screen.dart';
import 'package:tentura/features/post_view/ui/widget/post_info_sheet.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/basic_chat_body.dart';
import 'package:tentura/ui/widget/hud_labeled_multiline.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import '../beacon_threads/support/room_body_harness.dart';
import '../beacon_view/beacon_view_screen_harness.dart'
    show BeaconViewHarnessRouter;

const _postId = 'Bpostscreen001';
const _rootId = 'Mpostroot001';
const _rootText = 'Кто в субботу на велопрогулку?';
const _author = Profile(id: 'Uauthor', displayName: 'Олег');
const _reader = Profile(id: 'Ureader', displayName: 'Мария');
const _other = Profile(id: 'Uother', displayName: 'Дима');

final _createdAt = DateTime.utc(2026, 10, 2, 12);

Beacon _post({
  bool viewerCanForward = false,
  BeaconForwardPolicyValue forwardPolicy = BeaconForwardPolicyValue.open,
}) => Beacon(
  id: _postId,
  kind: BeaconKind.post,
  createdAt: _createdAt,
  updatedAt: _createdAt,
  status: BeaconStatus.open,
  canReadContent: true,
  author: _author,
  postRootMessageId: _rootId,
  viewerCanForward: viewerCanForward,
  forwardPolicy: forwardPolicy,
);

RoomMessage _rootMessage() => RoomMessage(
  id: _rootId,
  beaconId: _postId,
  authorId: _author.id,
  author: _author,
  body: _rootText,
  createdAt: _createdAt,
);

/// [count] short replies after the root, enough to push the root out of view.
List<RoomMessage> _longConversation(int count) => [
  _rootMessage(),
  for (var i = 0; i < count; i++)
    RoomMessage(
      id: 'Mreply$i',
      beaconId: _postId,
      authorId: _other.id,
      author: _other,
      body: 'Ответ номер $i',
      createdAt: _createdAt.add(Duration(minutes: i + 1)),
    ),
];

PostSummary _summary({DateTime? mutedUntil}) => PostSummary(
  id: _postId,
  authorId: _author.id,
  authorName: _author.displayName,
  rootExcerpt: _rootText,
  lastActivityAt: _createdAt,
  mutedUntil: mutedUntil,
);

ForwardEdge _edge({
  required Profile sender,
  required Profile recipient,
  required String note,
}) => ForwardEdge(
  id: 'E-${sender.id}-${recipient.id}',
  beaconId: _postId,
  createdAt: _createdAt,
  note: note,
  sender: sender,
  recipient: recipient,
);

/// Serves the Post and records every other repository call by member name, so
/// the forwarding mutation can be observed without a network.
class _PostRepository implements BeaconRepository {
  _PostRepository(this.beacon);

  Beacon beacon;
  final List<String> fetched = [];
  final List<String> openForwardingCalls = [];

  @override
  Stream<RepositoryEvent<Beacon>> get changes => const Stream.empty();

  @override
  Future<Beacon> fetchBeaconById(String id) async {
    fetched.add(id);
    return beacon;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #openForwarding) {
      openForwardingCalls.add(invocation.positionalArguments.first as String);
      beacon = beacon.copyWith(forwardPolicy: BeaconForwardPolicyValue.open);
      return Future<void>.value();
    }
    return super.noSuchMethod(invocation);
  }
}

/// Forward edges of the Post as the viewer may read them.
class _FakeForwardRepository implements ForwardRepository {
  _FakeForwardRepository(this.edges);

  final List<ForwardEdge> edges;

  @override
  Future<List<ForwardEdge>> fetchEdges({required String beaconId}) async =>
      edges;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The viewer's Posts (carries the mute expiry and root excerpt).
class _FakePostsRepository implements PostsRepositoryPort {
  _FakePostsRepository(this.posts);

  final List<PostSummary> posts;

  @override
  Future<List<PostSummary>> myPosts() async => posts;

  @override
  Future<PostSummary?> postSummary(String id) async =>
      posts.where((p) => p.id == id).firstOrNull;
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

/// Seeded room cubit that records message deletions; no I/O. Scroll requests
/// behave like the real cubit: they publish `scrollToMessageId` in the state.
class _RoomCubit extends RoomBodyHarnessCubit {
  _RoomCubit(super.initial);

  final List<String> deletedMessageIds = [];
  var _closed = false;

  @override
  bool get isClosed => _closed;

  @override
  Future<void> close() async => _closed = true;

  @override
  Future<void> load() async {}

  @override
  void prepareThreadScroll({String? messageId, String? coordinationItemId}) {}

  @override
  void requestScrollToMessage(String messageId) =>
      emitHarnessState(state.copyWith(scrollToMessageId: messageId));

  @override
  Future<void> deleteMessage({required String messageId}) async {
    deletedMessageIds.add(messageId);
  }
}

class _PushObserver extends NavigatorObserver {
  int pushes = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes++;
  }
}

class _Harness {
  _Harness({
    required this.repository,
    required this.cubit,
    required this.room,
    required this.effects,
    required this.router,
    required this.observer,
  });

  final _PostRepository repository;
  final PostViewCubit cubit;
  final _RoomCubit room;
  final FakeUiEffectPort effects;
  final BeaconViewHarnessRouter router;
  final _PushObserver observer;

  /// Anything that takes the user somewhere: a router push, a navigation
  /// effect, or a pushed route (dialog / sheet).
  int get navigations =>
      router.pushCount +
      router.replacedPaths.length +
      effects.emitted.whereType<NavigatePush>().length +
      observer.pushes;
}

/// Pumps [PostViewScreen] for a Post whose room holds [messages].
Future<_Harness> _pumpPost(
  WidgetTester tester, {
  required Beacon beacon,
  required Profile viewer,
  List<RoomMessage>? messages,
  BeaconRoomState? roomState,
  List<ForwardEdge> forwardEdges = const [],
  PostSummary? summary,
  Size surface = const Size(700, 900),
  double textScale = 1,
}) async {
  final getIt = GetIt.I;
  await getIt.reset();
  addTearDown(getIt.reset);
  final profileCubit = _ProfileCubit(viewer);
  getIt
    ..registerSingleton<ProfileCubit>(profileCubit)
    ..registerSingleton<ImageRepository>(ImageRepository())
    ..registerSingleton<ClipboardImageRepository>(ClipboardImageRepository())
    ..registerSingleton<ForwardRepository>(_FakeForwardRepository(forwardEdges))
    ..registerSingleton<PostsRepositoryPort>(
      _FakePostsRepository([summary ?? _summary()]),
    );

  final repository = _PostRepository(beacon);
  final effects = FakeUiEffectPort();
  final cubit = PostViewCubit(
    id: _postId,
    myProfile: viewer,
    beaconRepository: repository,
    effects: effects,
  );
  addTearDown(cubit.close);
  await cubit.fetch();

  final room = _RoomCubit(
    roomBodyState(
      beaconId: _postId,
      myUserId: viewer.id,
      messages: messages ?? [_rootMessage()],
    ).copyWith(
      roomState: roomState,
      participants: [
        roomBodyAdmittedParticipant(
          beaconId: _postId,
          profile: viewer,
          role: viewer.id == _author.id
              ? BeaconParticipantRoleBits.author
              : BeaconParticipantRoleBits.helper,
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
  // Unmount first: disposing the room lease schedules a deferred drop that
  // chains onto the host's internal future (see room_capabilities_widget_test).
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
  final router = BeaconViewHarnessRouter();
  final observer = _PushObserver();

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
        locale: const Locale('ru'),
        navigatorObservers: [observer],
        home: MediaQuery(
          data: MediaQueryData(
            size: surface,
            textScaler: TextScaler.linear(textScale),
          ),
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
    repository: repository,
    cubit: cubit,
    room: room,
    effects: effects,
    router: router,
    observer: observer,
  );
}

Finder _inAppBar(Finder f) =>
    find.descendant(of: find.byType(AppBar), matching: f);

Future<void> _openOverflow(WidgetTester tester) async {
  final button = _inAppBar(find.byIcon(Icons.more_vert));
  expect(button, findsOneWidget);
  await tester.tap(button);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

/// ⋮ → «О посте».
Future<void> _openInfo(WidgetTester tester) async {
  await _openOverflow(tester);
  await tester.tap(find.text('О посте'));
  await _settle(tester);
  expect(find.byType(PostInfoSheet), findsOneWidget);
}

/// Taps [target] inside «О посте», scrolling it into view first.
Future<void> _tapInSheet(WidgetTester tester, Finder target) async {
  final inSheet = find.descendant(
    of: find.byType(PostInfoSheet),
    matching: target,
  );
  await tester.ensureVisible(inSheet);
  await tester.pump();
  await tester.tap(inSheet);
  await _settle(tester);
}

Finder _confirmDialog() => find.byType(AlertDialog);

Finder _inDialog(Finder f) =>
    find.descendant(of: _confirmDialog(), matching: f);

Future<void> _tapDialogConfirm(WidgetTester tester) async {
  await tester.tap(_inDialog(find.byType(FilledButton)));
  await _settle(tester);
}

Future<void> _tapDialogCancel(WidgetTester tester) async {
  await tester.tap(_inDialog(find.byType(TextButton)));
  await _settle(tester);
}

/// 🔕 in the app bar: the emoji itself or a "notifications off" icon.
Finder _mutedIndicator() => _inAppBar(
  find.byWidgetPredicate(
    (w) =>
        (w is Text && (w.data?.contains('🔕') ?? false)) ||
        (w is Icon &&
            const <IconData>[
              Icons.notifications_off,
              Icons.notifications_off_outlined,
              Icons.notifications_off_rounded,
              Icons.notifications_off_sharp,
            ].contains(w.icon)),
  ),
);

Finder _stripExcerptText() => find.descendant(
  of: find.byType(BasicChatBody),
  matching: find.textContaining(_rootText, findRichText: true),
);

Finder _rootBubbleText() => find.descendant(
  of: find.byType(RoomMessageTextBody),
  matching: find.textContaining(_rootText, findRichText: true),
);

void main() {
  final l10n = lookupL10n(const Locale('ru'));

  group('Post app bar', () {
    testWidgets('title is «<author>: <root excerpt>»', (tester) async {
      await _pumpPost(tester, beacon: _post(), viewer: _reader);

      expect(
        _inAppBar(find.textContaining('Олег: $_rootText')),
        findsOneWidget,
      );
    });

    testWidgets('has no tabs and none of the Request HUD', (tester) async {
      await _pumpPost(tester, beacon: _post(), viewer: _reader);

      // Positive anchor: the screen has its Post app bar.
      expect(
        _inAppBar(find.textContaining('Олег: $_rootText')),
        findsOneWidget,
      );
      expect(find.byType(TabBar), findsNothing);
      expect(find.byType(TenturaPrimaryTabBar), findsNothing);
      expect(find.byType(TenturaUnderlineTabs), findsNothing);
      expect(find.byType(BeaconOperationalHeaderCard), findsNothing);
      expect(find.byType(BeaconNowSurface), findsNothing);
      expect(find.byType(BeaconPeopleTabBody), findsNothing);
      expect(find.byType(HudLabeledMultiline), findsNothing);
    });

    testWidgets('does not pin a NOW line even if the room has a plan line', (
      tester,
    ) async {
      await _pumpPost(
        tester,
        beacon: _post(),
        viewer: _reader,
        roomState: BeaconRoomState(
          beaconId: _postId,
          updatedAt: _createdAt,
          currentLine: 'Встречаемся у моста в 10',
        ),
      );

      expect(
        _inAppBar(find.textContaining('Олег: $_rootText')),
        findsOneWidget,
      );
      expect(find.byType(HudLabeledMultiline), findsNothing);
      expect(find.text(l10n.beaconHudNowLabel), findsNothing);
      expect(find.textContaining('Встречаемся у моста в 10'), findsNothing);
    });

    testWidgets('shows 🔕 while the Post is muted', (tester) async {
      await _pumpPost(
        tester,
        beacon: _post(),
        viewer: _reader,
        summary: _summary(mutedUntil: DateTime.utc(2999)),
      );

      expect(
        _inAppBar(find.textContaining('Олег: $_rootText')),
        findsOneWidget,
      );
      expect(_mutedIndicator(), findsOneWidget);
    });

    testWidgets('shows no 🔕 when the Post is not muted', (tester) async {
      await _pumpPost(tester, beacon: _post(), viewer: _reader);

      expect(
        _inAppBar(find.textContaining('Олег: $_rootText')),
        findsOneWidget,
      );
      expect(_mutedIndicator(), findsNothing);
    });

    testWidgets('shows no 🔕 once the mute has expired', (tester) async {
      await _pumpPost(
        tester,
        beacon: _post(),
        viewer: _reader,
        summary: _summary(mutedUntil: DateTime.utc(2000)),
      );

      expect(
        _inAppBar(find.textContaining('Олег: $_rootText')),
        findsOneWidget,
      );
      expect(_mutedIndicator(), findsNothing);
    });
  });

  group('Post app bar actions', () {
    testWidgets('counts the participants under the title', (tester) async {
      await _pumpPost(tester, beacon: _post(), viewer: _reader);

      expect(_inAppBar(find.text('1 участник')), findsOneWidget);
    });

    testWidgets('tapping the title opens «О посте»', (tester) async {
      await _pumpPost(tester, beacon: _post(), viewer: _reader);

      await tester.tap(_inAppBar(find.textContaining('Олег: $_rootText')));
      await _settle(tester);

      expect(find.byType(PostInfoSheet), findsOneWidget);
    });

    testWidgets('↗ forwards when the viewer can forward', (tester) async {
      final h = await _pumpPost(
        tester,
        beacon: _post(viewerCanForward: true),
        viewer: _reader,
      );
      final before = h.navigations;

      await tester.tap(_inAppBar(find.byIcon(Icons.north_east)));
      await _settle(tester);

      expect(h.navigations, greaterThan(before));
    });

    testWidgets('has no ↗ when the viewer cannot forward', (tester) async {
      await _pumpPost(tester, beacon: _post(), viewer: _reader);

      expect(_inAppBar(find.byIcon(Icons.north_east)), findsNothing);
    });
  });

  group('Post overflow menu', () {
    testWidgets('keeps «О посте», mute, pin and «Жалоба» for a member', (
      tester,
    ) async {
      await _pumpPost(tester, beacon: _post(), viewer: _reader);
      await _openOverflow(tester);

      expect(find.text('О посте'), findsOneWidget);
      expect(find.text('Заглушить ›'), findsOneWidget);
      expect(find.text('Закрепить в разговорах'), findsOneWidget);
      expect(find.text('Жалоба'), findsOneWidget);
      for (final moved in [
        'Участники',
        'Граф пересылок',
        'Показать на поле',
        'Переслать',
        'Удалить пост',
      ]) {
        expect(find.text(moved), findsNothing, reason: moved);
      }
    });

    testWidgets('«Жалоба» opens the complaint form for the Post', (
      tester,
    ) async {
      final h = await _pumpPost(tester, beacon: _post(), viewer: _reader);
      await _openOverflow(tester);

      await tester.tap(find.text('Жалоба'));
      await _settle(tester);

      expect(
        h.effects.emitted.whereType<NavigatePush>().map((e) => e.path),
        contains('/complaint/$_postId'),
      );
    });

    testWidgets('author sees «Удалить пост» and no «Жалоба»', (tester) async {
      await _pumpPost(tester, beacon: _post(), viewer: _author);
      await _openOverflow(tester);

      expect(find.text('Удалить пост'), findsOneWidget);
      expect(find.text('Жалоба'), findsNothing);
    });

    testWidgets('«Удалить пост» asks «Удалить пост?» first', (tester) async {
      final h = await _pumpPost(tester, beacon: _post(), viewer: _author);
      await _openOverflow(tester);

      await tester.tap(find.text('Удалить пост'));
      await _settle(tester);

      expect(find.text('Удалить пост?'), findsOneWidget);
      expect(h.room.deletedMessageIds, isEmpty);
    });
  });

  group('«О посте»', () {
    testWidgets('the shortcuts fit a narrow phone with large text', (
      tester,
    ) async {
      await _pumpPost(
        tester,
        beacon: _post(),
        viewer: _reader,
        surface: const Size(320, 700),
        textScale: 1.6,
      );
      // The room behind the sheet is not under test here (its unread divider
      // does not fit this width either).
      tester.takeException();
      await _openInfo(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('На поле'), findsOneWidget);
    });

    testWidgets('lists the participants and links the forwarding graph', (
      tester,
    ) async {
      await _pumpPost(tester, beacon: _post(), viewer: _reader);
      await _openInfo(tester);

      expect(find.text('Участники · 1'), findsOneWidget);
      expect(find.text('Как пост дошёл до людей'), findsOneWidget);
      expect(
        find.text('Можно пересылать: любой участник может позвать других'),
        findsOneWidget,
      );
    });

    testWidgets('«Как пост дошёл до людей» opens the forwarding graph', (
      tester,
    ) async {
      final h = await _pumpPost(tester, beacon: _post(), viewer: _reader);
      await _openInfo(tester);

      await _tapInSheet(tester, find.text('Как пост дошёл до людей'));

      expect(
        h.effects.emitted.whereType<NavigatePush>().map((e) => e.path),
        contains('/graph/forwards/$_postId'),
      );
    });

    testWidgets('«На поле» opens the field focused on the Post', (
      tester,
    ) async {
      final h = await _pumpPost(tester, beacon: _post(), viewer: _reader);
      addTearDown(ConstellationFocusRequest.instance.take);
      await _openInfo(tester);

      await _tapInSheet(tester, find.text('На поле'));

      expect(
        h.effects.emitted.whereType<NavigatePush>().map((e) => e.path),
        contains('/home/constellation'),
      );
      expect(ConstellationFocusRequest.instance.pending.value, _postId);
    });

    testWidgets('offers «Переслать» only when the viewer can forward', (
      tester,
    ) async {
      await _pumpPost(tester, beacon: _post(), viewer: _reader);
      await _openInfo(tester);

      expect(find.text('Переслать'), findsNothing);
      expect(find.textContaining('Позвать'), findsNothing);
    });

    testWidgets('«Переслать» opens the forward flow', (tester) async {
      final h = await _pumpPost(
        tester,
        beacon: _post(viewerCanForward: true),
        viewer: _reader,
      );
      await _openInfo(tester);
      final before = h.navigations;

      await _tapInSheet(tester, find.text('Переслать'));

      expect(h.navigations, greaterThan(before));
    });

    testWidgets('author sees «Превратить в запрос» and «Удалить пост»', (
      tester,
    ) async {
      await _pumpPost(tester, beacon: _post(), viewer: _author);
      await _openInfo(tester);

      expect(find.text('Превратить в запрос'), findsOneWidget);
      expect(find.text('Удалить пост'), findsOneWidget);
      expect(find.text('Жалоба'), findsNothing);
    });
  });

  group('allowing forwarding of a closed Post', () {
    final closed = _post(forwardPolicy: BeaconForwardPolicyValue.closed);

    Future<void> openAllowForwardingConfirm(WidgetTester tester) async {
      await _openInfo(tester);
      await _tapInSheet(tester, find.text('Разрешить пересылку'));
    }

    testWidgets('author of a closed Post sees «Разрешить пересылку»', (
      tester,
    ) async {
      await _pumpPost(tester, beacon: closed, viewer: _author);
      await _openInfo(tester);

      expect(find.text('Пересылать может только автор'), findsOneWidget);
      expect(find.text('Разрешить пересылку'), findsOneWidget);
    });

    testWidgets('a non-author of a closed Post does not', (tester) async {
      await _pumpPost(tester, beacon: closed, viewer: _reader);
      await _openInfo(tester);

      expect(find.text('Пересылать может только автор'), findsOneWidget);
      expect(find.text('Разрешить пересылку'), findsNothing);
    });

    testWidgets('the author of an open Post does not see it', (tester) async {
      await _pumpPost(tester, beacon: _post(), viewer: _author);
      await _openInfo(tester);

      expect(find.text('Как пост дошёл до людей'), findsOneWidget);
      expect(find.text('Разрешить пересылку'), findsNothing);
    });

    testWidgets('the confirm dialog explains that forwarding cannot be '
        'switched off again', (tester) async {
      await _pumpPost(tester, beacon: closed, viewer: _author);
      await openAllowForwardingConfirm(tester);

      expect(_confirmDialog(), findsOneWidget);
      expect(_inDialog(find.text('Разрешить пересылку?')), findsOneWidget);
      expect(
        _inDialog(
          find.text(
            'Любой участник сможет переслать пост людям из своего круга, '
            'и они смогут участвовать. Выключить это будет нельзя.',
          ),
        ),
        findsOneWidget,
      );
      expect(_inDialog(find.text('Разрешить')), findsOneWidget);
      expect(_inDialog(find.text('Отмена')), findsOneWidget);
    });

    testWidgets('opens forwarding only after the author confirms', (
      tester,
    ) async {
      final h = await _pumpPost(tester, beacon: closed, viewer: _author);
      await openAllowForwardingConfirm(tester);

      expect(_inDialog(find.text('Разрешить пересылку?')), findsOneWidget);
      expect(h.repository.openForwardingCalls, isEmpty);

      await _tapDialogConfirm(tester);

      expect(h.repository.openForwardingCalls, [_postId]);
    });

    testWidgets('cancelling the confirm leaves forwarding closed', (
      tester,
    ) async {
      final h = await _pumpPost(tester, beacon: closed, viewer: _author);
      await openAllowForwardingConfirm(tester);
      expect(_inDialog(find.text('Разрешить пересылку?')), findsOneWidget);

      await _tapDialogCancel(tester);

      expect(h.repository.openForwardingCalls, isEmpty);
    });

    testWidgets('once forwarding is open the action goes away (one-way)', (
      tester,
    ) async {
      await _pumpPost(tester, beacon: closed, viewer: _author);
      await openAllowForwardingConfirm(tester);
      expect(_inDialog(find.text('Разрешить пересылку?')), findsOneWidget);
      await _tapDialogConfirm(tester);
      await tester.pump(const Duration(milliseconds: 500));

      await _openInfo(tester);

      expect(find.text('Как пост дошёл до людей'), findsOneWidget);
      expect(find.text('Разрешить пересылку'), findsNothing);
    });
  });

  group('pinned root strip', () {
    testWidgets('shows the root excerpt above the messages', (tester) async {
      await _pumpPost(tester, beacon: _post(), viewer: _reader);

      // One match is the root bubble itself; the second is the pinned strip.
      expect(_stripExcerptText(), findsNWidgets(2));
    });

    testWidgets('tapping it scrolls the root message into view', (
      tester,
    ) async {
      await _pumpPost(
        tester,
        beacon: _post(),
        viewer: _reader,
        messages: _longConversation(40),
      );

      final messageList = find
          .descendant(
            of: find.byType(BasicChatBody),
            matching: find.byType(ListView),
          )
          .first;
      for (var i = 0; i < 4; i++) {
        await tester.fling(messageList, const Offset(0, -3000), 8000);
        await tester.pump(const Duration(seconds: 2));
      }

      // The root is far above the visible tail, so the only excerpt on screen
      // is the pinned strip.
      expect(_rootBubbleText(), findsNothing);
      expect(_stripExcerptText(), findsOneWidget);

      await tester.tap(_stripExcerptText());
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(_rootBubbleText(), findsOneWidget);
      final viewport = tester.getRect(find.byType(BasicChatBody));
      final bubble = tester.getRect(_rootBubbleText());
      expect(viewport.overlaps(bubble), isTrue);
    });

    testWidgets('names who forwarded the Post to the viewer and their note', (
      tester,
    ) async {
      await _pumpPost(
        tester,
        beacon: _post(),
        viewer: _reader,
        forwardEdges: [
          _edge(sender: _other, recipient: _author, note: 'совсем другое'),
          _edge(
            sender: const Profile(id: 'Umaria', displayName: 'Мария'),
            recipient: _reader,
            note: 'ты же хотел',
          ),
        ],
      );

      expect(
        find.descendant(
          of: find.byType(BasicChatBody),
          matching: find.textContaining(
            'Мария переслал(а) вам: «ты же хотел»',
            findRichText: true,
          ),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('совсем другое'), findsNothing);
    });

    testWidgets('has no forwarded line when nobody forwarded it to the '
        'viewer', (tester) async {
      await _pumpPost(
        tester,
        beacon: _post(),
        viewer: _reader,
        forwardEdges: [
          _edge(sender: _reader, recipient: _other, note: 'посмотри'),
        ],
      );

      expect(_stripExcerptText(), findsNWidgets(2));
      expect(find.textContaining('переслал(а) вам'), findsNothing);
    });

    testWidgets('has no forwarded line for the author', (tester) async {
      await _pumpPost(
        tester,
        beacon: _post(),
        viewer: _author,
        forwardEdges: [
          _edge(sender: _author, recipient: _reader, note: 'ты же хотел'),
        ],
      );

      expect(_stripExcerptText(), findsNWidgets(2));
      expect(find.textContaining('переслал(а) вам'), findsNothing);
    });
  });

  group('deleting the root message', () {
    Future<void> openRootActions(WidgetTester tester) async {
      final body = find.byType(RoomMessageTextBody);
      await tester.longPressAt(
        tester.getTopLeft(body.first) + const Offset(8, 8),
      );
      await _settle(tester);
      expect(find.byType(BottomSheet), findsOneWidget);
    }

    Finder deleteAction() => find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byIcon(Icons.delete_outline),
    );

    testWidgets('asks «Удалить пост?» before the Post root is deleted', (
      tester,
    ) async {
      final h = await _pumpPost(tester, beacon: _post(), viewer: _author);
      await openRootActions(tester);

      expect(deleteAction(), findsOneWidget);
      await tester.tap(deleteAction());
      await _settle(tester);

      expect(find.text('Удалить пост?'), findsOneWidget);
      expect(h.room.deletedMessageIds, isEmpty);
    });

    testWidgets('deletes the root only after the author confirms', (
      tester,
    ) async {
      final h = await _pumpPost(tester, beacon: _post(), viewer: _author);
      await openRootActions(tester);
      await tester.tap(deleteAction());
      await _settle(tester);
      expect(find.text('Удалить пост?'), findsOneWidget);

      await _tapDialogConfirm(tester);

      expect(h.room.deletedMessageIds, [_rootId]);
    });

    testWidgets('cancelling keeps the Post', (tester) async {
      final h = await _pumpPost(tester, beacon: _post(), viewer: _author);
      await openRootActions(tester);
      await tester.tap(deleteAction());
      await _settle(tester);
      expect(find.text('Удалить пост?'), findsOneWidget);

      await _tapDialogCancel(tester);

      expect(h.room.deletedMessageIds, isEmpty);
    });
  });
}
