// Fake transport answer for `UsersFetchByIds` that mimics Hasura's role-user
// select cap: only the requested ids come back, at most [cap] rows.
import 'package:tentura/data/service/remote_api_service.dart';

import 'remote_wire_harness.dart';

/// Hasura `user` select limit simulated by the fake transport.
const kWireUserRowCap = 10;

Map<String, dynamic> wireUserRow(String id) => {
  '__typename': 'user',
  'id': id,
  'created_at': '2020-01-01T00:00:00Z',
  'display_name': 'Name of $id',
  'handle': null,
  'description': '',
  'my_vote': 1,
  'trusts_viewer': true,
  'is_mutual_friend': true,
  'image': null,
  'scores': <Object>[],
  'user_presence': null,
  'user_availability': null,
};

Map<String, dynamic> cappedUsersAnswer(WireSent request) {
  final ids = (request.variables['ids'] as List).cast<String>();
  return {
    '__typename': 'query_root',
    'user': [for (final id in ids.take(kWireUserRowCap)) wireUserRow(id)],
  };
}

Future<void> withCappedUsersWire(
  List<WireSent> sent,
  Future<void> Function(RemoteApiService remote) body, {
  Map<String, Map<String, dynamic>> responses = const {},
  Future<Map<String, dynamic>> Function(WireSent request)? responseFor,
}) => withRemoteWire(
  responses,
  sent,
  body,
  responseFor: (request) async {
    if (request.operationName == 'UsersFetchByIds') {
      if (responseFor != null) return responseFor(request);
      return cappedUsersAnswer(request);
    }
    return responses[request.operationName] ?? const {};
  },
);
