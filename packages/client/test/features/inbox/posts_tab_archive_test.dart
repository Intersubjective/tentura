// The «Разговоры» tab splits Posts into pinned / «Сейчас» / «Архив» by the
// Post's own lifetime (closed or past `expiresAt`), not by how long the room
// has been silent. Time passing alone must move a Post with no network event,
// and rows show the time that is left (or that the Post is archived). These
// tests pin that against an injectable clock that the test moves.

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/inbox/domain/entity/post_summary.dart';
import 'package:tentura/features/inbox/domain/port/posts_repository_port.dart';
import 'package:tentura/features/inbox/domain/use_case/posts_case.dart';
import 'package:tentura/features/inbox/ui/bloc/posts_cubit.dart';
import 'package:tentura/features/inbox/ui/widget/post_conversation_row.dart';
import 'package:tentura/features/inbox/ui/widget/posts_tab_view.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/test_realtime_sync.dart';

final _start = DateTime.utc(2026, 10, 26, 12);

PostSummary _post(
  String id, {
  DateTime? expiresAt,
  Duration lastActivityAgo = const Duration(minutes: 5),
  DateTime? pinnedAt,
  BeaconStatus status = BeaconStatus.open,
}) => PostSummary(
  id: id,
  authorId: 'U$id',
  authorName: 'Анна',
  rootExcerpt: 'Корень $id',
  lastActivityAt: _start.subtract(lastActivityAgo),
  pinnedAt: pinnedAt,
  status: status,
  expiresAt: expiresAt,
);

DateTime _in(Duration d) => _start.add(d);

final class _FakePostsRepository implements PostsRepositoryPort {
  List<PostSummary> posts = const [];
  int myPostsCalls = 0;

  @override
  Future<List<PostSummary>> myPosts() async {
    myPostsCalls++;
    return posts;
  }

  @override
  Future<PostSummary?> postSummary(String id) async =>
      posts.where((p) => p.id == id).firstOrNull;
}

List<String> _ids(List<PostSummary> posts) => [for (final p in posts) p.id];

RealtimeEntityChange _beaconChange(String id) => RealtimeEntityChange(
  kind: RealtimeEntityKind.beacon,
  aggregateId: id,
  operation: RealtimeOperation.update,
  source: RealtimeChangeSource.serverInvalidation,
);

Widget _app(Widget child) => MaterialApp(
  locale: const Locale('ru'),
  theme: TenturaTheme.light(),
  localizationsDelegates: L10n.localizationsDelegates,
  supportedLocales: L10n.supportedLocales,
  home: MediaQuery(
    data: const MediaQueryData(size: Size(800, 1600)),
    child: TenturaResponsiveScope(child: Scaffold(body: child)),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Post lifetime sections against a moving clock', () {
    late _FakePostsRepository repository;
    late ({RealtimeSyncCase case_, TestRealtimeSyncPort port}) sync;

    PostsCubit buildCubit(FakeAsync async) {
      final cubit = PostsCubit(
        postsCase: PostsCase(
          repository,
          sync.case_,
          env: const Env(),
          logger: Logger('posts-archive-test'),
        ),
        clock: () => _start.add(async.elapsed),
      );
      async.flushMicrotasks();
      return cubit;
    }

    void runWith(
      List<PostSummary> posts,
      void Function(FakeAsync async, PostsCubit cubit) body,
    ) {
      repository = _FakePostsRepository()..posts = posts;
      sync = buildTestRealtimeSync();
      fakeAsync((async) {
        final cubit = buildCubit(async);
        body(async, cubit);
        unawaited(cubit.close());
        async.flushMicrotasks();
      });
    }

    test('open, expired, closed and pinned Posts land in their sections', () {
      runWith(
        [
          _post('Popen', expiresAt: _in(const Duration(hours: 5))),
          _post('Pexpired', expiresAt: _in(const Duration(minutes: -1))),
          _post(
            'Pclosed',
            expiresAt: _in(const Duration(hours: 5)),
            status: BeaconStatus.closed,
          ),
          _post(
            'Ppinned_open',
            expiresAt: _in(const Duration(hours: 5)),
            pinnedAt: _in(const Duration(minutes: -30)),
          ),
          _post(
            'Ppinned_closed',
            expiresAt: _in(const Duration(hours: 5)),
            pinnedAt: _in(const Duration(minutes: -20)),
            status: BeaconStatus.closed,
          ),
          _post(
            'Ppinned_expired',
            expiresAt: _in(const Duration(minutes: -1)),
            pinnedAt: _in(const Duration(minutes: -10)),
          ),
        ],
        (async, cubit) {
          expect(_ids(cubit.state.active), ['Popen']);
          expect(_ids(cubit.state.archive).toSet(), {'Pexpired', 'Pclosed'});
          expect(
            _ids(cubit.state.pinned),
            ['Ppinned_expired', 'Ppinned_closed', 'Ppinned_open'],
          );
        },
      );
    });

    test('a long-silent Post stays in «Сейчас» while its lifetime runs', () {
      runWith(
        [
          _post(
            'Psilent',
            expiresAt: _in(const Duration(hours: 5)),
            lastActivityAgo: const Duration(days: 10),
          ),
        ],
        (async, cubit) {
          expect(_ids(cubit.state.active), ['Psilent']);
          expect(cubit.state.archive, isEmpty);
        },
      );
    });

    test('«Сейчас» and «Архив» are ordered by last activity, not expiry', () {
      runWith(
        [
          _post(
            'Pa',
            expiresAt: _in(const Duration(hours: 1)),
            lastActivityAgo: const Duration(hours: 3),
          ),
          _post(
            'Pb',
            expiresAt: _in(const Duration(hours: 9)),
            lastActivityAgo: const Duration(hours: 1),
          ),
          _post(
            'Pc',
            expiresAt: _in(const Duration(hours: 5)),
            lastActivityAgo: const Duration(hours: 2),
          ),
          _post(
            'Pold_closed',
            status: BeaconStatus.closed,
            lastActivityAgo: const Duration(hours: 8),
          ),
          _post(
            'Pnew_closed',
            status: BeaconStatus.closed,
            lastActivityAgo: const Duration(hours: 4),
          ),
          _post(
            'Pexpired_busy',
            expiresAt: _in(const Duration(hours: -5)),
            lastActivityAgo: const Duration(hours: 2),
          ),
          _post(
            'Pexpired_idle',
            expiresAt: _in(const Duration(hours: -1)),
            lastActivityAgo: const Duration(hours: 9),
          ),
        ],
        (async, cubit) {
          expect(_ids(cubit.state.active), ['Pb', 'Pc', 'Pa']);
          expect(_ids(cubit.state.archive), [
            'Pexpired_busy',
            'Pnew_closed',
            'Pold_closed',
            'Pexpired_idle',
          ]);
        },
      );
    });

    test('passing the deadline moves an unpinned Post to «Архив» without '
        'a refetch', () {
      runWith(
        [
          _post('Pending', expiresAt: _in(const Duration(hours: 2))),
          _post('Plater', expiresAt: _in(const Duration(hours: 6))),
        ],
        (async, cubit) {
          final callsBefore = repository.myPostsCalls;
          expect(_ids(cubit.state.active).toSet(), {'Pending', 'Plater'});

          async
            ..elapse(const Duration(hours: 2, minutes: 1))
            ..flushMicrotasks();

          expect(_ids(cubit.state.active), ['Plater']);
          expect(_ids(cubit.state.archive), ['Pending']);
          expect(repository.myPostsCalls, callsBefore);
        },
      );
    });

    test('Posts do not move to «Архив» before their deadline', () {
      runWith(
        [_post('P1', expiresAt: _in(const Duration(hours: 2)))],
        (async, cubit) {
          async
            ..elapse(const Duration(hours: 1, minutes: 59, seconds: 59))
            ..flushMicrotasks();

          expect(_ids(cubit.state.active), ['P1']);
          expect(cubit.state.archive, isEmpty);
        },
      );
    });

    test('a pinned Post stays pinned at its deadline, and the list clock '
        'moves past it so the row reads as archived', () {
      runWith(
        [
          _post(
            'Ppin',
            expiresAt: _in(const Duration(hours: 1)),
            pinnedAt: _in(const Duration(minutes: -5)),
          ),
        ],
        (async, cubit) {
          final before = cubit.state.now!;
          expect(
            cubit.state.pinned.single.isArchivedAt(before),
            isFalse,
          );

          async
            ..elapse(const Duration(hours: 1, minutes: 1))
            ..flushMicrotasks();

          expect(_ids(cubit.state.pinned), ['Ppin']);
          expect(cubit.state.active, isEmpty);
          expect(cubit.state.archive, isEmpty);
          expect(cubit.state.now, isNot(before));
          expect(
            cubit.state.pinned.single.isArchivedAt(cubit.state.now!),
            isTrue,
          );
        },
      );
    });

    test('the list clock advances every minute in the last hour so the '
        'countdown refreshes', () {
      runWith(
        [_post('P1', expiresAt: _in(const Duration(minutes: 90)))],
        (async, cubit) {
          async
            ..elapse(const Duration(minutes: 31))
            ..flushMicrotasks();
          final afterFirst = cubit.state.now!;
          expect(afterFirst.isAfter(_in(const Duration(minutes: 30))), isTrue);

          async
            ..elapse(const Duration(minutes: 1))
            ..flushMicrotasks();

          expect(cubit.state.now!.isAfter(afterFirst), isTrue);
          expect(_ids(cubit.state.active), ['P1']);
        },
      );
    });

    test('the deadline timer is re-armed after every fetch', () {
      runWith(
        [_post('Pold', expiresAt: _in(const Duration(hours: 5)))],
        (async, cubit) {
          repository.posts = [
            _post('Pnew', expiresAt: _in(const Duration(hours: 1))),
          ];
          sync.port.emitChange(_beaconChange('Pnew'));
          async.flushMicrotasks();
          expect(_ids(cubit.state.active), ['Pnew']);

          async
            ..elapse(const Duration(hours: 1, minutes: 1))
            ..flushMicrotasks();

          expect(cubit.state.active, isEmpty);
          expect(_ids(cubit.state.archive), ['Pnew']);
        },
      );
    });

    test('no timer outlives a loaded cubit', () {
      repository = _FakePostsRepository()
        ..posts = [
          _post('P1', expiresAt: _in(const Duration(hours: 5))),
          _post(
            'Ppin',
            expiresAt: _in(const Duration(hours: 9)),
            pinnedAt: _in(const Duration(minutes: -5)),
          ),
        ];
      fakeAsync((async) {
        // Built inside the fake zone so closing the cubit completes there.
        sync = buildTestRealtimeSync();
        final cubit = buildCubit(async);
        expect(cubit.state.loaded, isTrue);
        // The expiry clock is armed on the loaded list.
        expect(async.nonPeriodicTimerCount, greaterThan(0));

        unawaited(cubit.close());
        async.flushMicrotasks();

        expect(async.nonPeriodicTimerCount, 0);
        expect(async.periodicTimerCount, 0);
        async.elapse(const Duration(days: 1));
        expect(async.nonPeriodicTimerCount, 0);
      });
    });

    testWidgets('a pinned Post row reads «в архиве» once the cubit clock '
        'passes its deadline, with no refetch', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      repository = _FakePostsRepository()
        ..posts = [
          _post(
            'Ppin',
            expiresAt: _in(const Duration(hours: 1)),
            pinnedAt: _in(const Duration(minutes: -5)),
          ),
        ];
      sync = buildTestRealtimeSync();
      addTearDown(sync.port.dispose);
      var now = _start;
      final cubit = PostsCubit(
        postsCase: PostsCase(
          repository,
          sync.case_,
          env: const Env(),
          logger: Logger('posts-archive-test'),
        ),
        clock: () => now,
      );
      addTearDown(cubit.close);
      await tester.pumpWidget(
        _app(
          BlocProvider<PostsCubit>.value(
            value: cubit,
            child: const PostsTabView(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final callsBefore = repository.myPostsCalls;
      expect(find.text('осталось 1 ч'), findsOneWidget);
      expect(find.text('в архиве'), findsNothing);

      now = _in(const Duration(hours: 1, minutes: 1));
      await tester.pump(const Duration(hours: 1, minutes: 1));
      await tester.pump();

      expect(repository.myPostsCalls, callsBefore);
      expect(_ids(cubit.state.pinned), ['Ppin']);
      expect(find.text('в архиве'), findsOneWidget);
      expect(find.textContaining('осталось'), findsNothing);
    });
  });

  group('«Разговоры» rows and sections show the Post lifetime', () {
    Widget app(Widget child) => MaterialApp(
      locale: const Locale('ru'),
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: MediaQuery(
        data: const MediaQueryData(size: Size(800, 1600)),
        child: TenturaResponsiveScope(child: Scaffold(body: child)),
      ),
    );

    Future<void> pumpRow(
      WidgetTester tester,
      PostSummary post,
      DateTime now,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        app(PostConversationRow(post: post, now: now, onOpen: () {})),
      );
      await tester.pump();
    }

    testWidgets('an open Post shows the time left', (tester) async {
      await pumpRow(
        tester,
        _post('P1', expiresAt: _in(const Duration(hours: 5, minutes: 10))),
        _start,
      );

      expect(find.text('осталось 5 ч'), findsOneWidget);
      expect(find.text('в архиве'), findsNothing);
    });

    testWidgets('the time left counts down in the last hour', (tester) async {
      await pumpRow(
        tester,
        _post('P1', expiresAt: _in(const Duration(minutes: 59))),
        _start,
      );

      expect(find.text('осталось 59 мин'), findsOneWidget);
    });

    testWidgets('an expired Post shows «в архиве» and no time left', (
      tester,
    ) async {
      await pumpRow(
        tester,
        _post('P1', expiresAt: _in(const Duration(hours: 1))),
        _in(const Duration(hours: 1, minutes: 1)),
      );

      expect(find.text('в архиве'), findsOneWidget);
      expect(find.textContaining('осталось'), findsNothing);
    });

    testWidgets('a pinned row flips from the countdown to «в архиве» when '
        'the clock passes the deadline', (tester) async {
      final pinned = _post(
        'Ppin',
        expiresAt: _in(const Duration(hours: 2)),
        pinnedAt: _in(const Duration(minutes: -5)),
      );
      await pumpRow(tester, pinned, _start);
      expect(find.text('осталось 2 ч'), findsOneWidget);
      expect(find.text('в архиве'), findsNothing);

      await pumpRow(tester, pinned, _in(const Duration(hours: 2, minutes: 1)));

      expect(find.text('в архиве'), findsOneWidget);
      expect(find.textContaining('осталось'), findsNothing);
    });

    testWidgets('an archived pinned row keeps the age of the last activity', (
      tester,
    ) async {
      await pumpRow(
        tester,
        PostSummary(
          id: 'Ppin',
          authorId: 'Uppin',
          authorName: 'Анна',
          rootExcerpt: 'Корень',
          lastMessageExcerpt: 'Мария: до встречи',
          lastActivityAt: _start.subtract(const Duration(hours: 3)),
          pinnedAt: _in(const Duration(minutes: -5)),
          expiresAt: _in(const Duration(hours: 1)),
        ),
        _in(const Duration(hours: 2)),
      );

      expect(find.text('в архиве'), findsOneWidget);
      expect(find.textContaining('Мария: до встречи'), findsOneWidget);
    });

    Finder header(String text) => find.byWidgetPredicate(
      (w) => w is Text && w.data?.toLowerCase() == text.toLowerCase(),
    );
    Finder rowOf(String id) => find.byWidgetPredicate(
      (w) => w is PostConversationRow && w.post.id == id,
    );

    testWidgets('the archive section header reads «Архив», after «Сейчас»', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repository = _FakePostsRepository()
        ..posts = [
          _post('Pnow', expiresAt: _in(const Duration(hours: 5))),
          _post('Pgone', expiresAt: _in(const Duration(minutes: -1))),
        ];
      final sync = buildTestRealtimeSync();
      addTearDown(sync.port.dispose);
      final cubit = (await tester.runAsync(() async {
        final c = PostsCubit(
          postsCase: PostsCase(
            repository,
            sync.case_,
            env: const Env(),
            logger: Logger('posts-archive-test'),
          ),
          clock: () => _start,
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return c;
      }))!;
      addTearDown(cubit.close);

      await tester.pumpWidget(
        app(
          BlocProvider<PostsCubit>.value(
            value: cubit,
            child: const PostsTabView(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      double top(Finder f) => tester.getTopLeft(f.first).dy;

      expect(header('Архив'), findsOneWidget);
      expect(header('Затихли'), findsNothing);
      // Every Post is listed once, in the section of its own lifetime.
      expect(find.byType(PostConversationRow), findsNWidgets(2));
      expect(rowOf('Pnow'), findsOneWidget);
      expect(rowOf('Pgone'), findsOneWidget);
      expect(_ids(cubit.state.active), ['Pnow']);
      expect(_ids(cubit.state.archive), ['Pgone']);
      expect(top(header('Сейчас')), lessThan(top(rowOf('Pnow'))));
      expect(top(rowOf('Pnow')), lessThan(top(header('Архив'))));
      expect(top(header('Архив')), lessThan(top(rowOf('Pgone'))));
    });

    testWidgets('with the list kept open, passing the deadline moves the '
        'unpinned row under «Архив» and flips the pinned row to «в архиве» '
        'without a refetch', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repository = _FakePostsRepository()
        ..posts = [
          _post(
            'Ppin',
            expiresAt: _in(const Duration(hours: 2)),
            pinnedAt: _in(const Duration(minutes: -5)),
          ),
          _post('Pfade', expiresAt: _in(const Duration(hours: 2))),
          _post('Pstay', expiresAt: _in(const Duration(hours: 9))),
        ];
      final sync = buildTestRealtimeSync();
      addTearDown(sync.port.dispose);
      var now = _start;
      // Built in the test's own fake-async zone so the cubit's expiry timer
      // runs on the pumped time.
      final cubit = PostsCubit(
        postsCase: PostsCase(
          repository,
          sync.case_,
          env: const Env(),
          logger: Logger('posts-archive-test'),
        ),
        clock: () => now,
      );
      addTearDown(cubit.close);
      await tester.pumpWidget(
        app(
          BlocProvider<PostsCubit>.value(
            value: cubit,
            child: const PostsTabView(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final callsBefore = repository.myPostsCalls;

      Finder marker(String id, String text) =>
          find.descendant(of: rowOf(id), matching: find.text(text));
      double top(Finder f) => tester.getTopLeft(f.first).dy;

      expect(marker('Ppin', 'осталось 2 ч'), findsOneWidget);
      expect(marker('Pfade', 'осталось 2 ч'), findsOneWidget);
      expect(header('Архив'), findsNothing);

      now = _in(const Duration(hours: 2, minutes: 1));
      await tester.pump(const Duration(hours: 2, minutes: 1));
      await tester.pump();

      expect(repository.myPostsCalls, callsBefore);
      expect(find.byType(PostConversationRow), findsNWidgets(3));
      expect(marker('Ppin', 'в архиве'), findsOneWidget);
      expect(marker('Ppin', 'осталось 2 ч'), findsNothing);
      expect(marker('Pfade', 'в архиве'), findsOneWidget);
      expect(marker('Pstay', 'в архиве'), findsNothing);
      expect(_ids(cubit.state.pinned), ['Ppin']);
      expect(_ids(cubit.state.active), ['Pstay']);
      expect(_ids(cubit.state.archive), ['Pfade']);
      expect(header('Архив'), findsOneWidget);
      expect(top(rowOf('Ppin')), lessThan(top(header('Сейчас'))));
      expect(top(header('Сейчас')), lessThan(top(rowOf('Pstay'))));
      expect(top(rowOf('Pstay')), lessThan(top(header('Архив'))));
      expect(top(header('Архив')), lessThan(top(rowOf('Pfade'))));

      // Disposing the cubit cancels its expiry timer; the test must not end
      // with a pending timer.
      await tester.pumpWidget(const SizedBox());
      unawaited(cubit.close());
    });
  });
}
