// The author of an open Post shortens its lifetime («Сократить срок») or ends
// it at once («Завершить сейчас») from ⋮; a member never sees either, and
// neither does anyone once the Post is archived or the clock has passed
// `expiresAt` (no refetch). The app bar and «О посте» read the remaining time
// off the same clock. UI copy is asserted verbatim in Russian.

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:tentura/features/block/domain/entity/user_block.dart';
import 'package:tentura/features/block/domain/use_case/block_case.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/forward_edge.dart';
import 'package:tentura/features/inbox/domain/entity/post_summary.dart';
import 'package:tentura/features/inbox/domain/port/posts_repository_port.dart';
import 'package:tentura/features/post_view/data/repository/post_membership_repository.dart';
import 'package:tentura/features/post_view/ui/bloc/post_view_cubit.dart';
import 'package:tentura/features/post_view/ui/screen/post_view_screen.dart';
import 'package:tentura/features/post_view/ui/widget/post_info_sheet.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/features/profile_view/domain/use_case/profile_view_case.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/graph_trust_write_fixture.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../beacon_threads/support/room_body_harness.dart';
import '../beacon_view/beacon_view_screen_harness.dart'
    show BeaconViewHarnessRouter;

const _postId = 'Bpostlife001';
const _rootId = 'Mpostroot001';
const _rootText = 'Кто в субботу на велопрогулку?';
const _author = Profile(id: 'Uauthor', displayName: 'Олег');
const _reader = Profile(id: 'Ureader', displayName: 'Мария');

final _createdAt = DateTime.utc(2026, 10, 2, 12);

/// The instant the injected clock starts at.
final _start = DateTime.utc(2026, 10, 3, 12);

Beacon _post({
  required DateTime? expiresAt,
  BeaconStatus status = BeaconStatus.open,
}) => Beacon(
  id: _postId,
  kind: BeaconKind.post,
  createdAt: _createdAt,
  updatedAt: _createdAt,
  status: status,
  author: _author,
  postRootMessageId: _rootId,
  expiresAt: expiresAt,
);

RoomMessage _rootMessage() => RoomMessage(
  id: _rootId,
  beaconId: _postId,
  authorId: _author.id,
  author: _author,
  body: _rootText,
  createdAt: _createdAt,
);

/// By default the last activity is a day before [_start]: a 72 h «quiet»
/// countdown counted from it would read two days, nowhere near the deadline.
PostSummary _summary({DateTime? lastActivityAt}) => PostSummary(
  id: _postId,
  authorId: _author.id,
  authorName: _author.displayName,
  rootExcerpt: _rootText,
  lastActivityAt: lastActivityAt ?? _createdAt,
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
  Future<List<ForwardEdge>> fetchEdges({required String beaconId}) async =>
      const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePostsRepository implements PostsRepositoryPort {
  _FakePostsRepository(this.lastActivityAt);

  final DateTime? lastActivityAt;

  @override
  Future<List<PostSummary>> myPosts() async => [
    _summary(lastActivityAt: lastActivityAt),
  ];

  @override
  Future<PostSummary?> postSummary(String id) async =>
      _summary(lastActivityAt: lastActivityAt);
}

/// Records the author's lifetime writes.
class _RecordingMembershipRepository implements PostMembershipRepository {
  final shortenCalls = <({String beaconId, DateTime expiresAt})>[];
  final closeCalls = <String>[];

  @override
  Future<void> postShorten(
    String beaconId, {
    required DateTime expiresAt,
  }) async {
    shortenCalls.add((beaconId: beaconId, expiresAt: expiresAt));
  }

  @override
  Future<void> postClose(String beaconId) async {
    closeCalls.add(beaconId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _IdleBlockCase extends Mock implements BlockCase {
  @override
  Stream<RepositoryEvent<BlockIntent>> get changes => const Stream.empty();
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

/// The injected clock the test moves, and the writes the screen sent.
class _Harness {
  DateTime now = _start;
  final membership = _RecordingMembershipRepository();
}

/// Pumps [PostViewScreen] for [viewer] on a Post that ends [endsIn] after the
/// harness clock starts (null: no deadline recorded).
Future<_Harness> _pumpPost(
  WidgetTester tester, {
  required Profile viewer,
  Duration? endsIn = const Duration(hours: 5),
  BeaconStatus status = BeaconStatus.open,
  DateTime? lastActivityAt,
}) async {
  final harness = _Harness();
  final getIt = GetIt.I;
  await getIt.reset();
  addTearDown(getIt.reset);
  final profileCubit = _ProfileCubit(viewer);
  // The participants list in «О посте» builds profile cubits from DI.
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
    ..registerSingleton<PostsRepositoryPort>(
      _FakePostsRepository(lastActivityAt),
    )
    ..registerSingleton<PostMembershipRepository>(harness.membership);

  final effects = FakeUiEffectPort();
  final cubit = PostViewCubit(
    id: _postId,
    myProfile: viewer,
    beaconRepository: _PostRepository(
      _post(
        expiresAt: endsIn == null ? null : _start.add(endsIn),
        status: status,
      ),
    ),
    effects: effects,
    clock: () => harness.now,
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
  return harness;
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _openOverflow(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byType(AppBar),
      matching: find.byIcon(Icons.more_vert),
    ),
  );
  await _settle(tester);
}

/// Moves the injected clock and the pumped time together, as a real session.
Future<void> _elapse(
  WidgetTester tester,
  _Harness harness,
  Duration by,
) async {
  harness.now = harness.now.add(by);
  await tester.pump(by);
  await tester.pump();
}

final _shortenAction = find.text('Сократить срок');
final _closeNowAction = find.text('Завершить сейчас');
final _inAppBar = find.byType(AppBar);

Future<void> _openShortenSheet(WidgetTester tester) async {
  await _openOverflow(tester);
  await tester.tap(_shortenAction);
  await _settle(tester);
}

void main() {
  group('lifetime actions in ⋮', () {
    testWidgets('the author of an open Post sees «Сократить срок» and '
        '«Завершить сейчас»', (tester) async {
      await _pumpPost(tester, viewer: _author);
      await _openOverflow(tester);

      expect(_shortenAction, findsOneWidget);
      expect(_closeNowAction, findsOneWidget);
    });

    testWidgets('a member sees neither', (tester) async {
      await _pumpPost(tester, viewer: _reader);
      await _openOverflow(tester);

      // The menu is open: a known entry proves it, then the absences count.
      expect(find.text('Заглушить ›'), findsOneWidget);
      expect(_shortenAction, findsNothing);
      expect(_closeNowAction, findsNothing);
    });

    testWidgets('nobody sees them on a closed (archived) Post', (tester) async {
      await _pumpPost(tester, viewer: _author, status: BeaconStatus.closed);
      await _openOverflow(tester);

      expect(find.text('Заглушить ›'), findsOneWidget);
      expect(_shortenAction, findsNothing);
      expect(_closeNowAction, findsNothing);
    });

    testWidgets('nobody sees them on a Post whose deadline already passed', (
      tester,
    ) async {
      await _pumpPost(
        tester,
        viewer: _author,
        endsIn: const Duration(hours: -1),
      );
      await _openOverflow(tester);

      expect(find.text('Заглушить ›'), findsOneWidget);
      expect(_shortenAction, findsNothing);
      expect(_closeNowAction, findsNothing);
    });

    testWidgets('they vanish from ⋮ when the clock passes the deadline, with '
        'no refetch', (tester) async {
      final harness = await _pumpPost(
        tester,
        viewer: _author,
        endsIn: const Duration(hours: 2),
      );
      await _openOverflow(tester);
      expect(_shortenAction, findsOneWidget);
      await tester.tapAt(const Offset(5, 5));
      await _settle(tester);

      await _elapse(tester, harness, const Duration(hours: 2, minutes: 1));
      await _openOverflow(tester);

      expect(find.text('Заглушить ›'), findsOneWidget);
      expect(_shortenAction, findsNothing);
      expect(_closeNowAction, findsNothing);
    });
  });

  group('remaining time in the app bar', () {
    testWidgets('an open Post with 5 h left reads «осталось 5 ч»', (
      tester,
    ) async {
      await _pumpPost(tester, viewer: _reader);

      expect(
        find.descendant(
          of: _inAppBar,
          matching: find.textContaining('осталось 5 ч'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _inAppBar,
          matching: find.textContaining('в архиве'),
        ),
        findsNothing,
      );
    });

    testWidgets('the countdown refreshes as the clock moves', (tester) async {
      final harness = await _pumpPost(tester, viewer: _reader);

      await _elapse(tester, harness, const Duration(hours: 4));

      expect(
        find.descendant(
          of: _inAppBar,
          matching: find.textContaining('осталось 1 ч'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('осталось 5 ч'), findsNothing);
    });

    testWidgets('the header flips to «в архиве» at the deadline, with no '
        'refetch', (tester) async {
      final harness = await _pumpPost(
        tester,
        viewer: _reader,
        endsIn: const Duration(hours: 2),
      );

      await _elapse(tester, harness, const Duration(hours: 2, minutes: 1));

      expect(
        find.descendant(
          of: _inAppBar,
          matching: find.textContaining('в архиве'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('осталось'), findsNothing);
    });
  });

  group('«О посте» lifetime line', () {
    Future<void> openInfo(WidgetTester tester) async {
      await tester.tap(
        find.descendant(of: _inAppBar, matching: find.text(_rootText)),
      );
      await _settle(tester);
      expect(find.byType(PostInfoSheet), findsOneWidget);
    }

    testWidgets('shows the time left to the deadline, not the time to '
        'quietness after the last activity', (tester) async {
      await _pumpPost(tester, viewer: _reader);
      await openInfo(tester);

      final inSheet = find.descendant(
        of: find.byType(PostInfoSheet),
        matching: find.textContaining('осталось 5 ч'),
      );
      expect(inSheet, findsOneWidget);
      // Activity a day ago would have read «Активен ещё 2 дня» (72 h quiet
      // window): that countdown is gone.
      expect(find.textContaining('Активен ещё'), findsNothing);
    });

    testWidgets('follows the deadline when recent activity puts quietness '
        'far later', (tester) async {
      // A quiet window would end in 72 h; the Post ends in 5 h.
      await _pumpPost(tester, viewer: _reader, lastActivityAt: _start);
      await openInfo(tester);

      expect(
        find.descendant(
          of: find.byType(PostInfoSheet),
          matching: find.textContaining('осталось 5 ч'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Активен ещё'), findsNothing);
    });

    testWidgets('does not call an open Post quiet when its last activity '
        'is older than the old quiet window', (tester) async {
      // 10 days since the last message: the quiet window long ended, the
      // deadline has not.
      await _pumpPost(
        tester,
        viewer: _reader,
        lastActivityAt: _start.subtract(const Duration(days: 10)),
      );
      await openInfo(tester);

      expect(
        find.descendant(
          of: find.byType(PostInfoSheet),
          matching: find.textContaining('осталось 5 ч'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Затих'), findsNothing);
    });

    testWidgets('says the Post is archived once the deadline has passed', (
      tester,
    ) async {
      await _pumpPost(
        tester,
        viewer: _reader,
        endsIn: const Duration(hours: -1),
      );
      await openInfo(tester);

      expect(
        find.descendant(
          of: find.byType(PostInfoSheet),
          matching: find.textContaining('в архиве'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(PostInfoSheet),
          matching: find.textContaining('осталось'),
        ),
        findsNothing,
      );
    });
  });

  group('«Сократить срок» sheet', () {
    final inOneHour = find.text('Через час');
    final inSixHours = find.text('Через 6 часов');
    final inDay = find.text('Через 24 часа');

    Future<void> openSheetWith(WidgetTester tester, Duration endsIn) async {
      await _pumpPost(tester, viewer: _author, endsIn: endsIn);
      await _openShortenSheet(tester);
    }

    testWidgets('with 5 h left offers «Через час» only, plus «Завершить '
        'сейчас»', (tester) async {
      await openSheetWith(tester, const Duration(hours: 5));

      expect(find.text('Когда закрыть пост?'), findsOneWidget);
      expect(inOneHour, findsOneWidget);
      expect(inSixHours, findsNothing);
      expect(inDay, findsNothing);
      expect(_closeNowAction, findsOneWidget);
    });

    testWidgets('with 30 h left offers all three ends', (tester) async {
      await openSheetWith(tester, const Duration(hours: 30));

      expect(inOneHour, findsOneWidget);
      expect(inSixHours, findsOneWidget);
      expect(inDay, findsOneWidget);
    });

    testWidgets('an end exactly 6 h away does not offer «Через 6 часов»', (
      tester,
    ) async {
      await openSheetWith(tester, const Duration(hours: 6));

      expect(inOneHour, findsOneWidget);
      expect(inSixHours, findsNothing);
      expect(inDay, findsNothing);
    });

    testWidgets('an end just over 6 h away offers «Через 6 часов»', (
      tester,
    ) async {
      await openSheetWith(tester, const Duration(hours: 6, minutes: 1));

      expect(inOneHour, findsOneWidget);
      expect(inSixHours, findsOneWidget);
      expect(inDay, findsNothing);
    });

    testWidgets('an end exactly 24 h away offers up to «Через 6 часов»', (
      tester,
    ) async {
      await openSheetWith(tester, const Duration(hours: 24));

      expect(inOneHour, findsOneWidget);
      expect(inSixHours, findsOneWidget);
      expect(inDay, findsNothing);
    });

    testWidgets('an end exactly 1 h away offers no new end, only «Завершить '
        'сейчас»', (tester) async {
      await openSheetWith(tester, const Duration(hours: 1));

      expect(inOneHour, findsNothing);
      expect(inSixHours, findsNothing);
      expect(inDay, findsNothing);
      expect(_closeNowAction, findsOneWidget);
    });

    testWidgets('with 30 min left offers no new end, only «Завершить '
        'сейчас»', (tester) async {
      await openSheetWith(tester, const Duration(minutes: 30));

      expect(inOneHour, findsNothing);
      expect(inSixHours, findsNothing);
      expect(inDay, findsNothing);
      expect(_closeNowAction, findsOneWidget);
    });

    testWidgets('picking «Через час» sends postShorten an hour after the '
        'clock', (tester) async {
      final harness = await _pumpPost(tester, viewer: _author);
      await _openShortenSheet(tester);
      await tester.tap(find.text('Через час'));
      await _settle(tester);

      expect(harness.membership.shortenCalls, hasLength(1));
      expect(harness.membership.shortenCalls.single.beaconId, _postId);
      expect(
        harness.membership.shortenCalls.single.expiresAt.toUtc(),
        _start.add(const Duration(hours: 1)),
      );
      expect(harness.membership.closeCalls, isEmpty);
    });
  });

  group('«Завершить сейчас»', () {
    Finder dialogButton<T extends Widget>() =>
        find.descendant(of: find.byType(AlertDialog), matching: find.byType(T));

    testWidgets('asks first and sends nothing until confirmed', (
      tester,
    ) async {
      final harness = await _pumpPost(tester, viewer: _author);
      await _openOverflow(tester);
      await tester.tap(_closeNowAction);
      await _settle(tester);

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Завершить пост?'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(
            'Пост уйдёт в архив, писать в него будет нельзя. '
            'Отменить это нельзя.',
          ),
        ),
        findsOneWidget,
      );
      expect(harness.membership.closeCalls, isEmpty);

      await tester.tap(dialogButton<TextButton>());
      await _settle(tester);

      expect(find.byType(AlertDialog), findsNothing);
      expect(harness.membership.closeCalls, isEmpty);
    });

    testWidgets('confirming calls postClose for the Post', (tester) async {
      final harness = await _pumpPost(tester, viewer: _author);
      await _openOverflow(tester);
      await tester.tap(_closeNowAction);
      await _settle(tester);
      await tester.tap(dialogButton<FilledButton>());
      await _settle(tester);

      expect(harness.membership.closeCalls, [_postId]);
      expect(harness.membership.shortenCalls, isEmpty);
    });
  });
}
