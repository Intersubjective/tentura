// #1046 real-path: FieldSearch maps HTTP JSON; repository uses firstLinkResponse.

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/constellation/data/repository/constellation_field_search_repository.dart';

import '../../support/remote_wire_harness.dart';

void main() {
  test(
    'FieldSearch repository maps the wire and sends query + context',
    () async {
      final sent = <WireSent>[];
      final paths = <String>[];
      await withRemoteWire(
        {
          'FieldSearch': {
            '__typename': 'query_root',
            'fieldSearch': {
              '__typename': 'v2_FieldSearchResult',
              'people': [
                {
                  '__typename': 'v2_FieldSearchPerson',
                  'id': 'peer-1',
                  'displayName': 'Pat',
                  'handle': '@pat',
                },
              ],
              'requests': <dynamic>[],
              'posts': <dynamic>[],
            },
          },
        },
        sent,
        (remote) async {
          final repo = ConstellationFieldSearchRepository(remote);
          final r = await repo.search(query: 'pa', context: 'ctx-a');
          expect(sent.single.operationName, 'FieldSearch');
          expect(sent.single.variables['query'], 'pa');
          expect(sent.single.variables['context'], 'ctx-a');
          expect(paths.single, endsWith('/api/v2/graphql'));
          expect(r.people.single.id, 'peer-1');
          expect(r.people.single.displayName, 'Pat');
          expect(r.people.single.handle, '@pat');
        },
        requestPaths: paths,
      );
    },
  );
}
