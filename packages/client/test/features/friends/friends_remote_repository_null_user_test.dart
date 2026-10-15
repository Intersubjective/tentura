// Sentry TENTURA-CLIENT-3X: a vote_user row whose user Hasura hides must not
// crash the friends list. The query asks Hasura to drop such rows.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';

import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/friends/data/repository/friends_remote_repository.dart';

Map<String, dynamic> _row(String id) => {
  '__typename': 'vote_user',
  'user': {
    '__typename': 'user',
    'id': id,
    'display_name': 'Name $id',
    'handle': id.toLowerCase(),
    'description': '',
    'my_vote': 1,
    'trusts_viewer': false,
    'is_mutual_friend': false,
    'image': null,
    'scores': null,
    'user_presence': null,
    'user_availability': null,
  },
};

void main() {
  test(
    'friends fetch skips vote_user rows with a hidden (null) user',
    () async {
      String? sentQuery;
      await http.runWithClient(
        () async {
          final remote = RemoteApiService(
            const Env(),
            const WebSocketClientRealtimeSocketFactory(),
          );
          final repo = FriendsRemoteRepository(
            remoteApiService: remote,
            log: Logger('test'),
          );
          try {
            await remote.setSessionAuth();
            final friends = (await repo.fetch()).toList();
            expect(friends.map((e) => e.id), [
              'Ufriend000001',
              'Ufriend000002',
            ]);
          } finally {
            await remote.close();
          }
        },
        () => MockClient((request) async {
          if (request.url.path.endsWith('/session/access-token')) {
            return http.Response(
              jsonEncode({
                'subject': 'Uauthor000001',
                'access_token': 'test-token',
                'expires_in': 3600,
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          sentQuery = body['query'] as String?;
          // Hasura applies the where clause: with the null-user filter the
          // hidden row never reaches the client.
          final filtered = sentQuery!.contains('_is_null');
          final rows = [
            _row('Ufriend000001'),
            if (!filtered) {'__typename': 'vote_user', 'user': null},
            _row('Ufriend000002'),
          ];
          return http.Response(
            jsonEncode({
              'data': {'vote_user': rows},
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      expect(sentQuery, contains('_is_null'));
    },
  );
}
