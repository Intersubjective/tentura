// The Conversations navigation dot must follow what the viewer has seen, not
// only what the «Разговоры» list last fetched: the list is not mounted on most
// routes, so a read or a removed Post has to clear the dot on its own.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';

import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/inbox/domain/entity/post_summary.dart';
import 'package:tentura/features/inbox/domain/port/posts_repository_port.dart';
import 'package:tentura/features/home/ui/widget/conversations_navbar_item.dart';
import 'package:tentura/features/inbox/domain/use_case/posts_case.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/test_realtime_sync.dart';

final class _Posts implements PostsRepositoryPort {
  List<PostSummary> posts = const [];
  int loads = 0;

  @override
  Future<List<PostSummary>> myPosts() async {
    loads++;
    return posts;
  }

  @override
  Future<PostSummary?> postSummary(String id) async => null;
}

PostSummary _post(String id, {int unread = 0}) => PostSummary(
  id: id,
  authorId: 'Uauthor',
  authorName: 'Author',
  lastActivityAt: DateTime.utc(2026, 10, 2),
  unreadCount: unread,
);

RealtimeEntityChange _change(RealtimeEntityKind kind, String id) =>
    RealtimeEntityChange(
      kind: kind,
      aggregateId: id,
      operation: RealtimeOperation.update,
      source: RealtimeChangeSource.serverInvalidation,
    );

Future<void> _settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late _Posts repository;
  late TestRealtimeSyncPort port;
  late PostsCase postsCase;

  setUp(() {
    repository = _Posts();
    final sync = buildTestRealtimeSync();
    port = sync.port;
    postsCase = PostsCase(
      repository,
      sync.case_,
      env: const Env(),
      logger: Logger('posts-dot-test'),
    );
  });

  tearDown(() => port.dispose());

  test('dot shows while a Post has unread messages', () async {
    repository.posts = [_post('B1', unread: 2)];
    await postsCase.myPosts();
    expect(postsCase.hasUnread, isTrue);
  });

  test('dot clears when the Post is read, without reloading the list', () async {
    repository.posts = [_post('B1', unread: 2)];
    await postsCase.myPosts();
    expect(postsCase.hasUnread, isTrue);

    repository.posts = [_post('B1')];
    port.emitChange(_change(RealtimeEntityKind.roomSeen, 'B1'));
    await _settle();

    expect(postsCase.hasUnread, isFalse);
  });

  test('dot clears when the unread Post is removed from the viewer', () async {
    repository.posts = [_post('B1', unread: 2)];
    await postsCase.myPosts();
    expect(postsCase.hasUnread, isTrue);

    repository.posts = const [];
    port.emitChange(_change(RealtimeEntityKind.beacon, 'B1'));
    await _settle();

    expect(postsCase.hasUnread, isFalse);
  });

  test('dot change is announced on the stream when it clears', () async {
    repository.posts = [_post('B1', unread: 1)];
    await postsCase.myPosts();
    final next = postsCase.hasUnreadChanges.first;

    repository.posts = [_post('B1')];
    port.emitChange(_change(RealtimeEntityKind.roomSeen, 'B1'));

    expect(await next.timeout(const Duration(seconds: 2)), isFalse);
  });

  test('a read clears the dot from the repository state, not by assumption',
      () async {
    repository.posts = [_post('B1', unread: 2), _post('B2', unread: 3)];
    await postsCase.myPosts();
    final loadsBefore = repository.loads;

    repository.posts = [_post('B1'), _post('B2', unread: 3)];
    port.emitChange(_change(RealtimeEntityKind.roomSeen, 'B1'));
    await _settle();

    expect(repository.loads, greaterThan(loadsBefore));
    expect(postsCase.hasUnread, isTrue, reason: 'B2 is still unread');
  });

  test('a read the repository does not yet confirm keeps the dot', () async {
    repository.posts = [_post('B1', unread: 2)];
    await postsCase.myPosts();

    port.emitChange(_change(RealtimeEntityKind.roomSeen, 'B1'));
    await _settle();

    expect(postsCase.hasUnread, isTrue);
  });

  test('a row left behind with a stale count does not hold the dot once '
      'access is lost', () async {
    repository.posts = [_post('B1', unread: 2)];
    await postsCase.myPosts();
    expect(postsCase.hasUnread, isTrue);

    // Access removed: the repository drops the Post from the viewer's list.
    repository.posts = const [];
    port.emitChange(_change(RealtimeEntityKind.roomSeen, 'B1'));
    await _settle();

    expect(postsCase.hasUnread, isFalse);
  });

  group('navigation icon', () {
    setUp(() {
      GetIt.I.registerSingleton<PostsCase>(postsCase);
    });

    tearDown(() => GetIt.I.reset());

    Future<void> pumpIcon(WidgetTester tester) => tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(body: ConversationsNavbarItem()),
      ),
    );

    testWidgets('shows the dot while a Post is unread, drops it once read',
        (tester) async {
      await tester.runAsync(() async {
        repository.posts = [_post('B1', unread: 2)];
        await postsCase.myPosts();
      });
      await pumpIcon(tester);
      expect(
        find.bySemanticsIdentifier('conversations-unread-dot'),
        findsOneWidget,
      );

      await tester.runAsync(() async {
        repository.posts = [_post('B1')];
        port.emitChange(_change(RealtimeEntityKind.roomSeen, 'B1'));
        await _settle();
      });
      await tester.pump();

      expect(
        find.bySemanticsIdentifier('conversations-unread-dot'),
        findsNothing,
      );
    });

    testWidgets('drops the dot when the unread Post is removed',
        (tester) async {
      await tester.runAsync(() async {
        repository.posts = [_post('B1', unread: 2)];
        await postsCase.myPosts();
      });
      await pumpIcon(tester);
      expect(
        find.bySemanticsIdentifier('conversations-unread-dot'),
        findsOneWidget,
      );

      await tester.runAsync(() async {
        repository.posts = const [];
        port.emitChange(_change(RealtimeEntityKind.beacon, 'B1'));
        await _settle();
      });
      await tester.pump();

      expect(
        find.bySemanticsIdentifier('conversations-unread-dot'),
        findsNothing,
      );
    });
  });
}
