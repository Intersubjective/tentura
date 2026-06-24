import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/domain/beacon_lineage_visibility.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/exception.dart';

BeaconEntity _beacon({
  required BeaconStatus status,
  String authorId = 'Uauth',
}) {
  final now = DateTime.utc(2026, 6, 1);
  return BeaconEntity(
    id: 'B1',
    title: 't',
    author: UserEntity(id: authorId),
    createdAt: now,
    updatedAt: now,
    status: status,
  );
}

void main() {
  group('assertBeaconLineageSourceVisible', () {
    test('passes for open beacon owned by viewer', () {
      expect(
        () => assertBeaconLineageSourceVisible(
          beacon: _beacon(status: BeaconStatus.open),
          userId: 'Uauth',
        ),
        returnsNormally,
      );
    });

    test('throws for deleted beacon', () {
      expect(
        () => assertBeaconLineageSourceVisible(
          beacon: _beacon(status: BeaconStatus.deleted),
          userId: 'Uauth',
        ),
        throwsA(isA<BeaconCreateException>()),
      );
    });

    test('throws when another users draft is used as source', () {
      expect(
        () => assertBeaconLineageSourceVisible(
          beacon: _beacon(status: BeaconStatus.draft, authorId: 'Uother'),
          userId: 'Uauth',
        ),
        throwsA(isA<BeaconCreateException>()),
      );
    });

    test('allows viewer to use own draft', () {
      expect(
        () => assertBeaconLineageSourceVisible(
          beacon: _beacon(status: BeaconStatus.draft, authorId: 'Uauth'),
          userId: 'Uauth',
        ),
        returnsNormally,
      );
    });
  });
}
