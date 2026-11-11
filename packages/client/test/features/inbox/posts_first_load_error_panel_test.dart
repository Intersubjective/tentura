// The Posts tab whose first load fails with a server error says so and offers
// a retry, instead of looking like an empty list.
//
// Real path: the Posts list widget (PostsTabView) over PostsCubit, over the
// production PostsCase, PostsRepository, the Ferry link chain and
// RemoteApiService. Only HTTP is substituted: the fake server answers
// `MyPosts` with HTTP 500 while it is "broken", and with one Post otherwise.
// A change event arrives through the real realtime case.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';

import 'package:tentura/data/service/network_reachability.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/port/network_reachability_port.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/inbox/data/repository/posts_repository.dart';
import 'package:tentura/features/inbox/domain/use_case/posts_case.dart';
import 'package:tentura/features/inbox/ui/bloc/posts_cubit.dart';
import 'package:tentura/features/inbox/ui/widget/posts_tab_view.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/screen_load_error_panel.dart';

import '../../support/phone_surface.dart';
import '../../support/test_realtime_sync.dart';

const _viewerId = 'Uviewer000001';
const _myPosts = 'MyPosts';
const _postExcerpt = 'Who has a ladder?';
const _errorTitle = 'Ошибка сервера';
const _retryLabel = 'Повторить';
const _emptyCopy =
    'Здесь будут посты, которые вы начали или в которые вас позвали';

Map<String, Object?> _postRow() => {
  '__typename': 'v2_PostSummary',
  'id': 'Bpost00000001',
  'authorId': _viewerId,
  'authorName': 'Viewer',
  'authorAvatar': '',
  'forwardedByName': null,
  'rootImageUrl': null,
  'rootExcerpt': _postExcerpt,
  'lastMessageExcerpt': null,
  'lastMessageIsRoot': true,
  'lastMessageAt': null,
  'lastActivityAt': '2026-11-09T08:00:00.000Z',
  'pinnedAt': null,
  'mutedUntil': null,
  'mutedForever': false,
  'unreadCount': 0,
  'participantCount': 0,
  'notOpenedCount': 0,
  'myDeclinedForwardCount': 0,
  'previewParticipants': <Object>[],
  'isAuthor': true,
  'status': 0,
  'expiresAt': null,
};

/// A server holding one Post that answers `MyPosts` with HTTP 500 while
/// [broken] is set. Counts every `MyPosts` it receives.
class _Server {
  bool broken = true;
  int myPostsRequests = 0;

  http.Client createClient() => MockClient((request) async {
    if (request.url.path.endsWith('/session/access-token')) {
      return http.Response(
        jsonEncode({
          'subject': _viewerId,
          'access_token': 'test-token',
          'expires_in': 3600,
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    final payload = jsonDecode(request.body) as Map<String, dynamic>;
    final name = payload['operationName'] as String;
    if (name != _myPosts) throw UnsupportedError('Unexpected operation: $name');
    myPostsRequests++;
    if (broken) {
      return http.Response(
        'Internal Server Error',
        500,
        headers: {'content-type': 'text/plain'},
      );
    }
    return http.Response(
      jsonEncode({
        'data': {
          '__typename': 'query_root',
          'myPosts': [_postRow()],
        },
      }),
      200,
      headers: {'content-type': 'application/json'},
    );
  });
}

Future<void> _pumpFor(WidgetTester tester, Duration total) async {
  const step = Duration(milliseconds: 50);
  for (var t = Duration.zero; t < total; t += step) {
    await tester.pump(step);
  }
}

Finder _seededPost() => find.textContaining(_postExcerpt, findRichText: true);

/// Mounts the Posts tab (RU, 375×667) over the production stack and runs
/// [body] with the pieces it drives.
Future<void> _withPostsTab(
  WidgetTester tester,
  _Server server,
  Future<void> Function(TestRealtimeSyncPort realtime) body,
) async {
  await usePhoneSurface(tester);
  await http.runWithClient(() async {
    final reachability = NetworkReachability.forTesting();
    await GetIt.I.reset();
    GetIt.I
      ..registerSingleton<NetworkReachabilityPort>(reachability)
      ..registerSingleton<NetworkReachability>(reachability);
    final remote = RemoteApiService(
      const Env(),
      const WebSocketClientRealtimeSocketFactory(),
      reachability: reachability,
    );
    final realtime = buildTestRealtimeSync();
    PostsCubit? cubit;
    try {
      await tester.runAsync(remote.setSessionAuth);
      final posts = cubit = PostsCubit(
        postsCase: PostsCase(
          PostsRepository(remote),
          realtime.case_,
          env: const Env(),
          logger: Logger('posts-first-load-error'),
        ),
        clock: () => DateTime.utc(2026, 11, 9, 9),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: TenturaTheme.light(),
          locale: const Locale('ru'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: BlocProvider<PostsCubit>.value(
              value: posts,
              child: PostsTabView(canCreatePost: false, onCreatePost: () {}),
            ),
          ),
        ),
      );
      await _pumpFor(tester, const Duration(seconds: 1));
      await body(realtime.port);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      unawaited(cubit?.close());
      unawaited(realtime.port.dispose());
      unawaited(reachability.dispose());
      await tester.pump(const Duration(seconds: 1));
      await tester.runAsync(remote.close);
      await GetIt.I.reset();
    }
  }, server.createClient);
}

void main() {
  group('Posts tab when the list cannot be loaded', () {
    testWidgets('a first load that fails with a server error shows the error '
        'panel with a retry, not the empty list', (tester) async {
      final server = _Server();
      await _withPostsTab(tester, server, (_) async {
        expect(server.myPostsRequests, greaterThan(0));
        expect(find.byType(ScreenLoadErrorPanel), findsOneWidget);
        expect(find.text(_errorTitle), findsOneWidget);
        expect(find.text(_retryLabel), findsOneWidget);
        expect(find.text(_emptyCopy), findsNothing);
      });
    });

    testWidgets('Retry asks the server again and lists the Posts it returns', (
      tester,
    ) async {
      final server = _Server();
      await _withPostsTab(tester, server, (_) async {
        expect(find.text(_retryLabel), findsOneWidget);
        final before = server.myPostsRequests;
        server.broken = false;

        await tester.tap(find.text(_retryLabel));
        await _pumpFor(tester, const Duration(seconds: 1));

        expect(server.myPostsRequests, greaterThan(before));
        expect(find.byType(ScreenLoadErrorPanel), findsNothing);
        expect(_seededPost(), findsWidgets);
      });
    });

    testWidgets('a refetch that fails after a good load keeps the listed '
        'Posts and shows no error panel', (tester) async {
      final server = _Server()..broken = false;
      await _withPostsTab(tester, server, (realtime) async {
        expect(_seededPost(), findsWidgets);
        final before = server.myPostsRequests;
        server.broken = true;

        realtime.emitChange(
          const RealtimeEntityChange(
            kind: RealtimeEntityKind.beacon,
            aggregateId: 'Bpost00000001',
            operation: RealtimeOperation.update,
            source: RealtimeChangeSource.serverInvalidation,
          ),
        );
        await _pumpFor(tester, const Duration(seconds: 1));

        expect(
          server.myPostsRequests,
          greaterThan(before),
          reason: 'the change event refetched the list',
        );
        expect(_seededPost(), findsWidgets);
        expect(find.byType(ScreenLoadErrorPanel), findsNothing);
      });
    });
  });
}
