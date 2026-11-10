// The Posts list whose first load failed because the network was down
// reloads on its own once the network is back, without the viewer doing
// anything.
//
// Real path: the Posts list widget (PostsTabView, as ConversationsScreen
// mounts it) over PostsCubit, over the production PostsCase, PostsRepository, the
// Ferry link chain (with the reachability link) and RemoteApiService. Only
// HTTP is substituted: while the network is "down" every GraphQL request
// fails the way a browser fetch does (`ClientException('Failed to fetch')`),
// which the real link reports to NetworkReachability as offline.
//
// Recovery: the fake server answers again and `reachability.reportSuccess()`
// is called. It stands in for a successful reachability probe (the probe has
// its own tests).

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
import 'package:tentura/domain/port/network_reachability_port.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/inbox/data/repository/posts_repository.dart';
import 'package:tentura/features/inbox/domain/use_case/posts_case.dart';
import 'package:tentura/features/inbox/ui/bloc/posts_cubit.dart';
import 'package:tentura/features/inbox/ui/widget/posts_tab_view.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/test_realtime_sync.dart';

const _viewerId = 'Uviewer000001';
const _postId = 'Bpost00000001';
const _myPosts = 'MyPosts';
const _postExcerpt = 'Who has a ladder?';

Map<String, Object?> _postRow() => {
  '__typename': 'v2_PostSummary',
  'id': _postId,
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

/// The network to a server holding one Post: down until [up] is set.
/// Counts every GraphQL operation the client tries to send.
class _Network {
  bool up = false;
  final attempts = <String, int>{};

  int attemptsOf(String operation) => attempts[operation] ?? 0;

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
    attempts[name] = attemptsOf(name) + 1;
    if (!up) throw http.ClientException('Failed to fetch');
    final data = switch (name) {
      _myPosts => <String, Object?>{
        '__typename': 'query_root',
        'myPosts': [_postRow()],
      },
      _ => throw UnsupportedError('Unexpected operation: $name'),
    };
    return http.Response(
      jsonEncode({'data': data}),
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

/// The seeded Post's row text in the list.
Finder _seededPost() => find.textContaining(_postExcerpt, findRichText: true);

void main() {
  group('Posts whose first load failed while offline', () {
    testWidgets('reload once on their own when the network is back', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(800, 1600)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final network = _Network();
      await http.runWithClient(() async {
        final reachability = NetworkReachability.forTesting();
        await GetIt.I.reset();
        GetIt.I
          ..registerSingleton<NetworkReachabilityPort>(reachability)
          ..registerSingleton<NetworkReachability>(reachability);
        final transitions = <bool>[];
        final sub = reachability.onlineChanges.listen(transitions.add);
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
              logger: Logger('posts-load-recovery'),
            ),
            clock: () => DateTime.utc(2026, 11, 9, 9),
          );
          // The list widget ConversationsScreen shows the viewer's Posts in.
          await tester.pumpWidget(
            MaterialApp(
              theme: TenturaTheme.light(),
              locale: const Locale('en'),
              localizationsDelegates: L10n.localizationsDelegates,
              supportedLocales: L10n.supportedLocales,
              home: Scaffold(
                body: BlocProvider<PostsCubit>.value(
                  value: posts,
                  child: PostsTabView(
                    canCreatePost: false,
                    onCreatePost: () {},
                  ),
                ),
              ),
            ),
          );
          await _pumpFor(tester, const Duration(seconds: 1));
          expect(tester.takeException(), isNull);
          expect(posts.state.loaded, isTrue, reason: 'the first load ends');
          expect(reachability.isOnline, isFalse);
          expect(_seededPost(), findsNothing);

          // Still offline: nothing retries behind the failure.
          final before = network.attemptsOf(_myPosts);
          expect(before, greaterThan(0));
          await _pumpFor(tester, const Duration(seconds: 3));
          expect(
            network.attemptsOf(_myPosts),
            before,
            reason: 'no retry reaches the server while offline',
          );

          network.up = true;
          reachability.reportSuccess();
          await _pumpFor(tester, const Duration(seconds: 1));
          expect(transitions, contains(true), reason: 'went back online');
          expect(tester.takeException(), isNull);

          expect(
            _seededPost(),
            findsWidgets,
            reason:
                'the Post appears without any user action once the network '
                'is back ($_myPosts sent ${network.attemptsOf(_myPosts)} '
                'times, $before before going online)',
          );
          expect(
            network.attemptsOf(_myPosts),
            before + 1,
            reason: '$_myPosts is sent again exactly once',
          );
          // Nothing keeps reloading once the list is loaded.
          await _pumpFor(tester, const Duration(seconds: 3));
          expect(
            network.attemptsOf(_myPosts),
            before + 1,
            reason: '$_myPosts is sent again exactly once',
          );
        } finally {
          // Closing awaits work only fake time moves on: start it, then pump.
          await tester.pumpWidget(const SizedBox.shrink());
          unawaited(sub.cancel());
          unawaited(cubit?.close());
          unawaited(realtime.port.dispose());
          unawaited(reachability.dispose());
          await tester.pump(const Duration(seconds: 1));
          await tester.runAsync(remote.close);
          await GetIt.I.reset();
        }
      }, network.createClient);
    });
  });
}
