import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/data/service/remote_api_client/realtime_socket.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/graph/data/repository/graph_repository.dart';

void main() {
  test(
    'fetchEdgesBetween with fewer than two ids returns empty without requesting',
    () async {
      final remote = RemoteApiService(
        const Env(),
        const WebSocketClientRealtimeSocketFactory(),
      );
      addTearDown(remote.close);
      final repository = GraphRepository(
        remoteApiService: remote,
        log: Logger('GraphRepositoryTest'),
      );

      expect(
        await repository.fetchEdgesBetween(nodeIds: {}),
        isEmpty,
      );
      expect(
        await repository.fetchEdgesBetween(nodeIds: {'only-one'}),
        isEmpty,
      );
    },
  );

  test('pgTextArrayLiteral encodes Hasura _text Postgres array form', () {
    expect(
      GraphRepository.pgTextArrayLiteral(['Ua', 'Ub']),
      '{"Ua","Ub"}',
    );
    expect(
      GraphRepository.pgTextArrayLiteral([r'a"b', r'c\d']),
      r'{"a\"b","c\\d"}',
    );
  });
}
