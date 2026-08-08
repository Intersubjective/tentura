import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/mappers/gql_public_user_maps.dart';
import 'package:tentura_server/domain/entity/gql_public/user_public_record.dart';

void main() {
  test(
    'userPublicToGqlMap maps trusts_viewer from subjectExplicitlyTrustsViewer',
    () {
      const user = UserPublicRecord(
        id: 'U1',
        displayName: 'Alice',
        description: 'bio',
        subjectExplicitlyTrustsViewer: true,
      );
      final map = userPublicToGqlMap(user);
      expect(map['trusts_viewer'], isTrue);
    },
  );

  test('userPublicToGqlMap defaults trusts_viewer to false', () {
    const user = UserPublicRecord(
      id: 'U1',
      displayName: 'Alice',
      description: 'bio',
    );
    final map = userPublicToGqlMap(user);
    expect(map['trusts_viewer'], isFalse);
  });

  test('userPublicToGqlMap always includes non-null trusts_viewer', () {
    const user = UserPublicRecord(
      id: 'U1',
      displayName: 'Alice',
      description: 'bio',
      isMutualFriend: true,
    );
    final map = userPublicToGqlMap(user);
    expect(map.containsKey('trusts_viewer'), isTrue);
    expect(map['trusts_viewer'], isA<bool>());
  });
}
