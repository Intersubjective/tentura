import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('availability read parity — V2 Profile adapters', () {
    const adapterPaths = [
      'lib/data/model/user_public_model.dart',
      'lib/features/profile_view/data/repository/mutual_friends_repository.dart',
      'lib/features/beacon_view/data/repository/coordination_repository.dart',
    ];

    for (final relativePath in adapterPaths) {
      test('$relativePath maps user_availability into Profile', () {
        final source = File(relativePath).readAsStringSync();
        expect(source, contains('user_availability'));
        expect(source, contains('availability:'));
        expect(source, contains('Availability.open()'));
      });
    }

    test('Hasura UserModel adapter maps user_availability into Profile', () {
      final source = File('lib/data/model/user_model.dart').readAsStringSync();
      expect(source, contains('availabilityFromHasuraRelationship'));
      expect(source, contains('user_availability'));
    });

    test('calendar mapper files never call toLocal()', () {
      for (final relativePath in [
        'lib/data/gql/calendar_date_serializer.dart',
        'lib/data/model/user_model.dart',
        'lib/data/model/user_public_model.dart',
      ]) {
        final source = File(relativePath).readAsStringSync();
        expect(source.contains('toLocal('), isFalse, reason: relativePath);
      }
    });
  });
}
