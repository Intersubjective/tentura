// The «Разговоры» tab of Activity lists every Post the viewer is in. These
// tests pin the three things the tab owns on the client: the order of the
// list (pinned first, then by last activity), the 72 h split into «Сейчас» /
// «Затихли» against an injected clock, and the refetch after the server says
// a Post changed. The server's `myPosts` query only filters and counts; the
// ordering and the split are decided here.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/consts.dart';
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

final _now = DateTime.utc(2026, 10, 3, 12);

PostSummary _post(
  String id, {
  String authorName = 'Анна',
  String? rootExcerpt,
  String? lastMessageExcerpt,
  DateTime? lastActivityAt,
  DateTime? pinnedAt,
  DateTime? mutedUntil,
  int unreadCount = 0,
  bool isAuthor = false,
}) => PostSummary(
  id: id,
  authorId: 'U$id',
  authorName: authorName,
  rootExcerpt: rootExcerpt ?? 'Корень $id',
  lastMessageExcerpt: lastMessageExcerpt,
  lastActivityAt: lastActivityAt ?? _now,
  pinnedAt: pinnedAt,
  mutedUntil: mutedUntil,
  unreadCount: unreadCount,
  isAuthor: isAuthor,
);

DateTime _ago(Duration d) => _now.subtract(d);

final class _FakePostsRepository implements PostsRepositoryPort {
  List<PostSummary> posts = const [];
  int myPostsCalls = 0;
  bool fail = false;

  @override
  Future<List<PostSummary>> myPosts() async {
    myPostsCalls++;
    if (fail) throw StateError('myPosts offline');
    return posts;
  }

  @override
  Future<PostSummary?> postSummary(String id) async =>
      posts.where((p) => p.id == id).firstOrNull;
}

Future<void> _settle() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.microtask(() {});
  }
  await Future<void>.delayed(const Duration(milliseconds: 20));
}

RealtimeEntityChange _beaconChange(
  String id, {
  RealtimeOperation operation = RealtimeOperation.update,
}) => RealtimeEntityChange(
  kind: RealtimeEntityKind.beacon,
  aggregateId: id,
  operation: operation,
  source: RealtimeChangeSource.serverInvalidation,
);

List<String> _ids(List<PostSummary> posts) => [for (final p in posts) p.id];

PostsCubit? cubitOrNull;

PostsCubit get cubit => cubitOrNull!;

void main() {
  test('unread marker includes pinned, active and quiet conversations', () {
    final unread = _post('unread', unreadCount: 1);
    final read = _post('read');
    expect(const PostsState().hasUnread, isFalse);
    expect(
      PostsState(pinned: [read], active: [read], quiet: [read]).hasUnread,
      isFalse,
    );
    expect(PostsState(pinned: [unread]).hasUnread, isTrue);
    expect(PostsState(active: [unread]).hasUnread, isTrue);
    expect(PostsState(quiet: [unread]).hasUnread, isTrue);
  });
  late _FakePostsRepository repository;
  late ({RealtimeSyncCase case_, TestRealtimeSyncPort port}) sync;

  Future<PostsCubit> buildCubit() async {
    final postsCase = PostsCase(
      repository,
      sync.case_,
      env: const Env(),
      logger: Logger('posts-tab-test'),
    );
    cubitOrNull = PostsCubit(postsCase: postsCase, clock: () => _now);
    await _settle();
    return cubit;
  }

  setUp(() {
    repository = _FakePostsRepository();
    sync = buildTestRealtimeSync();
  });

  tearDown(() async {
    await cubitOrNull?.close();
    cubitOrNull = null;
    await sync.port.dispose();
  });

  group('conversation ordering', () {
    test('pinned Posts come first, the most recently pinned on top', () async {
      repository.posts = [
        _post('Pquiet', lastActivityAt: _ago(const Duration(hours: 1))),
        _post(
          'Ppin_old',
          lastActivityAt: _ago(const Duration(hours: 5)),
          pinnedAt: _ago(const Duration(days: 3)),
        ),
        _post(
          'Ppin_new',
          lastActivityAt: _ago(const Duration(hours: 9)),
          pinnedAt: _ago(const Duration(hours: 2)),
        ),
      ];
      await buildCubit();

      expect(_ids(cubit.state.pinned), ['Ppin_new', 'Ppin_old']);
      expect(_ids(cubit.state.active), ['Pquiet']);
    });

    test('unpinned Posts are ordered by last activity, newest first', () async {
      repository.posts = [
        _post('Pb', lastActivityAt: _ago(const Duration(hours: 5))),
        _post('Pc', lastActivityAt: _ago(const Duration(minutes: 3))),
        _post('Pa', lastActivityAt: _ago(const Duration(hours: 1))),
      ];
      await buildCubit();

      expect(_ids(cubit.state.active), ['Pc', 'Pa', 'Pb']);
      expect(cubit.state.pinned, isEmpty);
    });

    test('a pinned Post never fades into «Затихли», however old', () async {
      repository.posts = [
        _post(
          'Pold_pin',
          lastActivityAt: _ago(const Duration(days: 30)),
          pinnedAt: _ago(const Duration(days: 29)),
        ),
      ];
      await buildCubit();

      expect(_ids(cubit.state.pinned), ['Pold_pin']);
      expect(cubit.state.active, isEmpty);
      expect(cubit.state.quiet, isEmpty);
    });
  });

  group('the 72 h split against the injected clock', () {
    test('«Сейчас» and «Затихли» are split at the window', () async {
      repository.posts = [
        _post(
          'Pjust_in',
          lastActivityAt: _ago(const Duration(hours: 71, minutes: 59)),
        ),
        _post(
          'Pjust_out',
          lastActivityAt: _ago(const Duration(hours: 72, minutes: 1)),
        ),
        _post('Pfresh', lastActivityAt: _ago(const Duration(minutes: 1))),
        _post('Pweek', lastActivityAt: _ago(const Duration(days: 7))),
      ];
      await buildCubit();

      expect(_ids(cubit.state.active), ['Pfresh', 'Pjust_in']);
      expect(_ids(cubit.state.quiet), ['Pjust_out', 'Pweek']);
    });

    test('a Post silent for exactly 72 hours is already «Затихли»', () async {
      repository.posts = [
        _post('Pedge', lastActivityAt: _ago(const Duration(hours: 72))),
        _post(
          'Pnearly',
          lastActivityAt: _ago(
            const Duration(hours: 71, minutes: 59, seconds: 59),
          ),
        ),
      ];
      await buildCubit();

      expect(_ids(cubit.state.active), ['Pnearly']);
      expect(_ids(cubit.state.quiet), ['Pedge']);
    });

    test('the split follows the clock, not the wall time', () async {
      repository.posts = [
        _post('P1', lastActivityAt: _now.subtract(const Duration(hours: 10))),
      ];
      final postsCase = PostsCase(
        repository,
        sync.case_,
        env: const Env(),
        logger: Logger('posts-tab-test'),
      );
      cubitOrNull = PostsCubit(
        postsCase: postsCase,
        clock: () => _now.add(const Duration(days: 4)),
      );
      await _settle();

      expect(cubit.state.active, isEmpty);
      expect(_ids(cubit.state.quiet), ['P1']);
    });

    test(
      'writing in a quiet Post moves it back to «Сейчас» on refetch',
      () async {
        repository.posts = [
          _post('P1', lastActivityAt: _ago(const Duration(days: 5))),
        ];
        await buildCubit();
        expect(_ids(cubit.state.quiet), ['P1']);

        repository.posts = [
          _post('P1', lastActivityAt: _ago(const Duration(minutes: 1))),
        ];
        sync.port.emitChange(_beaconChange('P1'));
        await _settle();

        expect(_ids(cubit.state.active), ['P1']);
        expect(cubit.state.quiet, isEmpty);
      },
    );
  });

  group('refetch on a server change', () {
    test(
      'a pin event refetches and the pinned Post jumps to the top',
      () async {
        repository.posts = [
          _post('Pa', lastActivityAt: _ago(const Duration(hours: 1))),
          _post('Pb', lastActivityAt: _ago(const Duration(hours: 2))),
        ];
        await buildCubit();
        expect(cubit.state.pinned, isEmpty);
        final callsBefore = repository.myPostsCalls;

        repository.posts = [
          _post('Pa', lastActivityAt: _ago(const Duration(hours: 1))),
          _post(
            'Pb',
            lastActivityAt: _ago(const Duration(hours: 2)),
            pinnedAt: _ago(const Duration(seconds: 5)),
          ),
        ];
        sync.port.emitChange(_beaconChange('Pb'));
        await _settle();

        expect(repository.myPostsCalls, callsBefore + 1);
        expect(_ids(cubit.state.pinned), ['Pb']);
        expect(_ids(cubit.state.active), ['Pa']);
      },
    );

    test(
      'a reply refetches and the Post moves up with its unread count',
      () async {
        repository.posts = [
          _post('Pa', lastActivityAt: _ago(const Duration(hours: 1))),
          _post('Pb', lastActivityAt: _ago(const Duration(hours: 2))),
        ];
        await buildCubit();
        final callsBefore = repository.myPostsCalls;

        repository.posts = [
          _post('Pa', lastActivityAt: _ago(const Duration(hours: 1))),
          _post(
            'Pb',
            lastActivityAt: _ago(const Duration(seconds: 3)),
            lastMessageExcerpt: 'Мария: я за, во сколько?',
            unreadCount: 2,
          ),
        ];
        sync.port.emitChange(_beaconChange('Pb'));
        await _settle();

        expect(repository.myPostsCalls, callsBefore + 1);
        expect(_ids(cubit.state.active), ['Pb', 'Pa']);
        expect(cubit.state.active.first.unreadCount, 2);
        expect(
          cubit.state.active.first.lastMessageExcerpt,
          'Мария: я за, во сколько?',
        );
      },
    );

    test('a mute refetches and the Post shows its mute expiry', () async {
      repository.posts = [_post('Pa')];
      await buildCubit();
      expect(cubit.state.active.single.mutedUntil, isNull);
      final callsBefore = repository.myPostsCalls;

      final until = _now.add(const Duration(hours: 3));
      repository.posts = [_post('Pa', mutedUntil: until)];
      sync.port.emitChange(_beaconChange('Pa'));
      await _settle();

      expect(repository.myPostsCalls, callsBefore + 1);
      expect(cubit.state.active.single.mutedUntil, until);
    });

    test(
      'leaving refetches and the Post disappears from every section',
      () async {
        repository.posts = [
          _post('Pa'),
          _post('Pquiet', lastActivityAt: _ago(const Duration(days: 5))),
          _post('Ppinned', pinnedAt: _ago(const Duration(hours: 1))),
        ];
        await buildCubit();
        final callsBefore = repository.myPostsCalls;

        repository.posts = [_post('Pa')];
        sync.port.emitChange(_beaconChange('Pquiet'));
        await _settle();
        sync.port.emitChange(_beaconChange('Ppinned'));
        await _settle();

        expect(repository.myPostsCalls, greaterThanOrEqualTo(callsBefore + 2));
        expect(_ids(cubit.state.active), ['Pa']);
        expect(cubit.state.quiet, isEmpty);
        expect(cubit.state.pinned, isEmpty);
      },
    );

    test('every beacon operation refetches, including a delete', () async {
      repository.posts = [_post('Pa')];
      await buildCubit();

      for (final operation in RealtimeOperation.values) {
        final before = repository.myPostsCalls;
        sync.port.emitChange(_beaconChange('Pa', operation: operation));
        await _settle();
        expect(
          repository.myPostsCalls,
          before + 1,
          reason: 'beacon ${operation.name} must refetch',
        );
      }
    });

    test('a beacon change for a Post not in the list still refetches, so a '
        'newly addressed Post appears', () async {
      repository.posts = [_post('Pa')];
      await buildCubit();
      final callsBefore = repository.myPostsCalls;

      repository.posts = [
        _post('Pa'),
        _post('Pnew', unreadCount: 1),
      ];
      sync.port.emitChange(_beaconChange('Pnew'));
      await _settle();

      expect(repository.myPostsCalls, callsBefore + 1);
      expect(_ids(cubit.state.active).toSet(), {'Pa', 'Pnew'});
    });

    test('a change of another kind does not refetch', () async {
      repository.posts = [_post('Pa')];
      await buildCubit();
      final callsBefore = repository.myPostsCalls;

      sync.port.emitChange(
        RealtimeEntityChange(
          kind: RealtimeEntityKind.contact,
          aggregateId: 'Pa',
          operation: RealtimeOperation.update,
          source: RealtimeChangeSource.serverInvalidation,
        ),
      );
      await _settle();

      expect(repository.myPostsCalls, callsBefore);
    });

    test('a failed refetch keeps the list that was already shown', () async {
      repository.posts = [_post('Pa')];
      await buildCubit();

      repository.fail = true;
      sync.port.emitChange(_beaconChange('Pa'));
      await _settle();

      expect(_ids(cubit.state.active), ['Pa']);
    });
  });

  group('«Разговоры» list on screen', () {
    Future<void> pumpTab(
      WidgetTester tester, {
      PostsTabView view = const PostsTabView(),
    }) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.runAsync(buildCubit);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ru'),
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: MediaQuery(
            data: const MediaQueryData(size: Size(800, 1600)),
            child: TenturaResponsiveScope(
              child: Scaffold(
                body: BlocProvider<PostsCubit>.value(
                  value: cubit,
                  child: view,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Finder rowOf(String id) => find.byWidgetPredicate(
      (w) => w is PostConversationRow && w.post.id == id,
    );

    Finder header(String text) => find.byWidgetPredicate(
      (w) => w is Text && w.data?.toLowerCase() == text.toLowerCase(),
    );

    testWidgets('shows pinned rows, then «Сейчас», then «Затихли» in order', (
      tester,
    ) async {
      repository.posts = [
        _post('Pquiet', lastActivityAt: _ago(const Duration(days: 6))),
        _post('Pnow_old', lastActivityAt: _ago(const Duration(hours: 4))),
        _post('Pnow_new', lastActivityAt: _ago(const Duration(minutes: 9))),
        _post(
          'Ppinned',
          lastActivityAt: _ago(const Duration(days: 9)),
          pinnedAt: _ago(const Duration(hours: 1)),
        ),
      ];
      await pumpTab(tester);

      double top(Finder f) => tester.getTopLeft(f.first).dy;
      expect(find.byType(PostConversationRow), findsNWidgets(4));
      expect(top(rowOf('Ppinned')), lessThan(top(header('Сейчас'))));
      expect(top(header('Сейчас')), lessThan(top(rowOf('Pnow_new'))));
      expect(top(rowOf('Pnow_new')), lessThan(top(rowOf('Pnow_old'))));
      expect(top(rowOf('Pnow_old')), lessThan(top(header('Затихли'))));
      expect(top(header('Затихли')), lessThan(top(rowOf('Pquiet'))));
    });

    testWidgets('omits «Сейчас» when nothing is recent', (tester) async {
      repository.posts = [
        _post('Pquiet', lastActivityAt: _ago(const Duration(days: 6))),
      ];
      await pumpTab(tester);

      expect(header('Сейчас'), findsNothing);
      expect(header('Затихли'), findsOneWidget);
      expect(rowOf('Pquiet'), findsOneWidget);
    });

    testWidgets('a row names the author, the root and the last message', (
      tester,
    ) async {
      repository.posts = [
        _post(
          'Pa',
          authorName: 'Олег',
          rootExcerpt: 'Кто в субботу на велопрогулку?',
          lastMessageExcerpt: 'Мария: я за, во сколько?',
        ),
      ];
      await pumpTab(tester);

      final row = rowOf('Pa');
      expect(
        find.descendant(of: row, matching: find.textContaining('Олег')),
        findsWidgets,
      );
      expect(
        find.descendant(
          of: row,
          matching: find.textContaining('Кто в субботу на велопрогулку?'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: row,
          matching: find.textContaining('Мария: я за, во сколько?'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a muted Post carries the muted icon, others do not', (
      tester,
    ) async {
      repository.posts = [
        _post(
          'Pmuted',
          mutedUntil: _now.add(const Duration(hours: 3)),
        ),
        _post('Ploud'),
      ];
      await pumpTab(tester);

      final mutedIcon = find.byWidgetPredicate(
        (w) =>
            w is Icon &&
            (w.icon == Icons.notifications_off_outlined ||
                w.icon == Icons.notifications_off ||
                w.icon == Icons.notifications_off_rounded),
      );
      expect(
        find.descendant(of: rowOf('Pmuted'), matching: mutedIcon),
        findsOneWidget,
      );
      expect(
        find.descendant(of: rowOf('Ploud'), matching: mutedIcon),
        findsNothing,
      );
    });

    testWidgets('a row with unread messages shows the count, a read one none', (
      tester,
    ) async {
      repository.posts = [
        _post('Punread', unreadCount: 7),
        _post('Pread'),
      ];
      await pumpTab(tester);

      expect(
        find.descendant(of: rowOf('Punread'), matching: find.text('7')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: rowOf('Pread'), matching: find.text('0')),
        findsNothing,
      );
    });

    testWidgets('with no Posts it explains what will appear here', (
      tester,
    ) async {
      repository.posts = const [];
      await pumpTab(tester);

      expect(find.byType(PostConversationRow), findsNothing);
      expect(
        find.textContaining(
          'Здесь будут посты, которые вы начали или в которые вас позвали',
        ),
        findsOneWidget,
      );
      expect(header('Сейчас'), findsNothing);
      expect(header('Затихли'), findsNothing);
    });

    testWidgets(
      'the empty state offers «Новый пост» when creating is allowed',
      (tester) async {
        repository.posts = const [];
        var created = 0;
        await pumpTab(
          tester,
          view: PostsTabView(
            canCreatePost: true,
            onCreatePost: () => created++,
          ),
        );

        final action = find.text('Новый пост');
        expect(action, findsOneWidget);

        await tester.tap(action);
        await tester.pump();

        expect(created, 1);
      },
    );

    testWidgets('the empty state has no «Новый пост» when creating is not '
        'allowed', (tester) async {
      repository.posts = const [];
      await pumpTab(
        tester,
        view: PostsTabView(canCreatePost: false, onCreatePost: () {}),
      );

      expect(find.textContaining('Здесь будут посты'), findsOneWidget);
      expect(find.text('Новый пост'), findsNothing);
    });

    testWidgets('by default the empty-state action follows the Post gate', (
      tester,
    ) async {
      repository.posts = const [];
      await pumpTab(tester, view: PostsTabView(onCreatePost: () {}));

      expect(
        find.text('Новый пост'),
        kPostsEnabled ? findsOneWidget : findsNothing,
      );
    });

    testWidgets('a list with Posts does not show «Новый пост»', (tester) async {
      repository.posts = [_post('Pa')];
      await pumpTab(
        tester,
        view: PostsTabView(canCreatePost: true, onCreatePost: () {}),
      );

      expect(find.text('Новый пост'), findsNothing);
    });

    testWidgets('with Posts the empty-state line is not shown', (tester) async {
      repository.posts = [_post('Pa')];
      await pumpTab(tester);

      expect(
        find.textContaining('Здесь будут посты'),
        findsNothing,
      );
    });
  });
}
