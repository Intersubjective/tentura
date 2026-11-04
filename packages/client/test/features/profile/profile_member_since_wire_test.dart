import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/profile/data/repository/profile_repository.dart';

import '../../support/remote_wire_harness.dart';

void main() {
  test('UserFetchById maps created_at to Profile.joinedAt', () async {
    const id = 'Ujoined0000001';
    const createdAt = '2026-03-12T09:30:00Z';
    late Profile profile;
    final sent = <WireSent>[];

    await withRemoteWire(
      {
        'UserFetchById': {
          '__typename': 'query_root',
          'user_by_pk': {
            '__typename': 'user',
            'id': id,
            'created_at': createdAt,
            'display_name': 'Alex',
            'handle': 'alex',
            'description': '',
            'my_vote': 0,
            'trusts_viewer': false,
            'is_mutual_friend': false,
            'image': null,
            'scores': <Object>[],
            'user_presence': null,
            'user_availability': null,
          },
        },
      },
      sent,
      (remote) async {
        profile = await ProfileRepository(remote).fetchById(id);
      },
    );

    expect(sent.single.operationName, 'UserFetchById');
    expect(profile.id, id);
    expect(profile.joinedAt, DateTime.utc(2026, 3, 12, 9, 30));
  });
}
