import 'package:test/test.dart';

import 'package:tentura_server/domain/beacon_lineage_visibility.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/exception.dart';

BeaconEntity _beacon({
  required int state,
  String authorId = 'Uauth',
}) {
  final now = DateTime.utc(2026, 6, 1);
  return BeaconEntity(
    id: 'B1',
    title: 't',
    author: UserEntity(id: authorId),
    createdAt: now,
    updatedAt: now,
    state: state,
  );
}

void main() {
  group('assertBeaconLineageSourceVisible', () {
    test('passes for open beacon owned by viewer', () {
      expect(
        () => assertBeaconLineageSourceVisible(
          beacon: _beacon(state: 0),
          userId: 'Uauth',
        ),
        returnsNormally,
      );
    });

    test('throws for deleted beacon', () {
      expect(
        () => assertBeaconLineageSourceVisible(
          beacon: _beacon(state: kBeaconStateDeleted),
          userId: 'Uauth',
        ),
        throwsA(isA<BeaconCreateException>()),
      );
    });

    test('throws when another users draft is used as source', () {
      expect(
        () => assertBeaconLineageSourceVisible(
          beacon: _beacon(state: kBeaconStateDraft, authorId: 'Uother'),
          userId: 'Uauth',
        ),
        throwsA(isA<BeaconCreateException>()),
      );
    });

    test('allows viewer to use own draft', () {
      expect(
        () => assertBeaconLineageSourceVisible(
          beacon: _beacon(state: kBeaconStateDraft, authorId: 'Uauth'),
          userId: 'Uauth',
        ),
        returnsNormally,
      );
    });
  });
}
