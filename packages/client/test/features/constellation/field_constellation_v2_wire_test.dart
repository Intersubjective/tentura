// #1046: sibling Field reads use Tentura V2 direct routing (not Hasura proxy).

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/constellation/data/repository/constellation_field_hide_repository.dart';
import 'package:tentura/features/constellation/data/repository/constellation_person_field_items_repository.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_person_field_item.dart';

import '../../support/remote_wire_harness.dart';

void main() {
  test('FieldHiddenItems repository calls V2', () async {
    final sent = <WireSent>[];
    final paths = <String>[];
    await withRemoteWire(
      {
        'FieldHiddenItems': {
          '__typename': 'query_root',
          'fieldHiddenItems': <dynamic>[],
        },
      },
      sent,
      (remote) async {
        final repo = ConstellationFieldHideRepository(remote);
        final rows = await repo.fetchHiddenItems();
        expect(rows, isEmpty);
        expect(sent.single.operationName, 'FieldHiddenItems');
        expect(paths.single, endsWith('/api/v2/graphql'));
      },
      requestPaths: paths,
    );
  });

  test('PersonFieldItems repository calls V2', () async {
    final sent = <WireSent>[];
    final paths = <String>[];
    await withRemoteWire(
      {
        'PersonFieldItems': {
          '__typename': 'query_root',
          'personFieldItems': {
            '__typename': 'v2_PersonFieldItemsPage',
            'items': <dynamic>[],
            'nextCursor': null,
            'counts': {
              '__typename': 'v2_PersonFieldCounts',
              'active': 0,
              'closed': 0,
              'hidden': 0,
            },
          },
        },
      },
      sent,
      (remote) async {
        final repo = ConstellationPersonFieldItemsRepository(remote);
        final page = await repo.fetch(
          personId: 'peer-1',
          bucket: ConstellationPersonFieldBucket.active,
          query: 'move',
        );
        expect(page.items, isEmpty);
        expect(sent.single.operationName, 'PersonFieldItems');
        expect(sent.single.variables['personId'], 'peer-1');
        expect(paths.single, endsWith('/api/v2/graphql'));
      },
      requestPaths: paths,
    );
  });
}
