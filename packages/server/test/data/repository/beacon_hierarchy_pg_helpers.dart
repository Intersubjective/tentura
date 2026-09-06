import 'package:postgres/postgres.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import '../../support/beacon_hierarchy_fixture.dart';

/// Inserts a published child beacon linked to [parentBeaconId].
Future<void> insertPublishedChildBeacon({
  required Connection writer,
  required String childId,
  required String parentId,
  required String ownerId,
  required String title,
  BeaconStatus status = BeaconStatus.open,
  DateTime? publishedAt,
  String? lineageParentBeaconId,
}) async {
  final published = publishedAt ?? DateTime.utc(2026, 1, 10);
  await writer.execute(
    Sql.named(r'''
INSERT INTO public.beacon (
  id, user_id, title, description, status,
  parent_beacon_id, published_at, lineage_parent_beacon_id,
  created_at, updated_at
) VALUES (
  @id, @ownerId, @title, '', @status,
  @parentId, @publishedAt, @lineageParent,
  @publishedAt, @publishedAt
)
ON CONFLICT (id) DO UPDATE
SET published_at = EXCLUDED.published_at,
    status = EXCLUDED.status,
    lineage_parent_beacon_id = EXCLUDED.lineage_parent_beacon_id
'''),
    parameters: {
      'id': childId,
      'ownerId': ownerId,
      'title': title,
      'status': status.smallintValue,
      'parentId': parentId,
      'publishedAt': published,
      'lineageParent': lineageParentBeaconId,
    },
  );
}

/// Seeds A→B→C published nesting on top of [BeaconHierarchyFixture.seedFullTopology].
Future<void> seedPublishedHierarchyTree(Connection writer) async {
  for (final childId in [
    BeaconHierarchyTopology.beaconC,
    BeaconHierarchyTopology.beaconB,
    BeaconHierarchyTopology.beaconD,
  ]) {
    await writer.execute(
      Sql.named('DELETE FROM public.beacon WHERE id = @id'),
      parameters: {'id': childId},
    );
  }
  await insertPublishedChildBeacon(
    writer: writer,
    childId: BeaconHierarchyTopology.beaconB,
    parentId: BeaconHierarchyTopology.beaconA,
    ownerId: BeaconHierarchyTopology.bobId,
    title: 'Request B',
    publishedAt: DateTime.utc(2026, 1, 5),
  );
  await insertPublishedChildBeacon(
    writer: writer,
    childId: BeaconHierarchyTopology.beaconC,
    parentId: BeaconHierarchyTopology.beaconB,
    ownerId: BeaconHierarchyTopology.daveId,
    title: 'Request C',
    publishedAt: DateTime.utc(2026, 1, 6),
  );
  await insertPublishedChildBeacon(
    writer: writer,
    childId: BeaconHierarchyTopology.beaconD,
    parentId: BeaconHierarchyTopology.beaconA,
    ownerId: BeaconHierarchyTopology.eveId,
    title: 'Request D',
    publishedAt: DateTime.utc(2026, 1, 4),
  );
}
