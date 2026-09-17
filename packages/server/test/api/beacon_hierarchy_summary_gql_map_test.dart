import 'dart:convert';

import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_cover_source.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_owner_summary.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_summary.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/api/controllers/graphql/mappers/gql_v2_dto_maps.dart';

void main() {
  group('beaconHierarchySummaryToGqlMap', () {
    test('serialized tombstone GraphQL map nulls identity fields', () {
      final map = beaconHierarchySummaryToGqlMap(
        BeaconHierarchySummary(
          beaconId: 'Bgone',
          status: BeaconStatus.deleted,
          publishedAt: DateTime.utc(2026, 1, 2),
          isTombstone: true,
        ),
      );
      expect(map['beaconId'], 'Bgone');
      expect(map['isTombstone'], isTrue);
      expect(map['title'], isNull);
      expect(map['description'], isNull);
      expect(map['owner'], isNull);
      expect(map['coverImageId'], isNull);
      expect(map['coverThumbImageId'], isNull);
      expect(map['primaryNeedSlug'], isNull);
      expect(map['admittedHelperPreviews'], isEmpty);
      expect(map['admittedHelperCount'], 0);
      expect(jsonEncode(map), isNot(contains('Alice')));
    });

    test('active summary keeps owner separate from helper previews', () {
      final map = beaconHierarchySummaryToGqlMap(
        BeaconHierarchySummary(
          beaconId: 'Bchild',
          title: 'Need a ladder',
          description: 'Please help',
          owner: const BeaconHierarchyOwnerSummary(
            id: 'Uauthor',
            displayName: 'Alice',
          ),
          status: BeaconStatus.open,
          publishedAt: DateTime.utc(2026, 1, 1),
          isTombstone: false,
          coverSource: BeaconCoverSource.photo,
          admittedHelperPreviews: const [
            BeaconHierarchyOwnerSummary(
              id: 'Uhelper',
              displayName: 'Bob',
            ),
          ],
          admittedHelperCount: 3,
        ),
      );
      expect(map['owner'], isA<Map<String, dynamic>>());
      expect((map['owner'] as Map)['displayName'], 'Alice');
      final helpers = map['admittedHelperPreviews'] as List;
      expect(helpers, hasLength(1));
      expect((helpers.single as Map)['displayName'], 'Bob');
      expect(map['admittedHelperCount'], 3);
      expect(helpers.any((h) => (h as Map)['id'] == 'Uauthor'), isFalse);
    });
  });
}
