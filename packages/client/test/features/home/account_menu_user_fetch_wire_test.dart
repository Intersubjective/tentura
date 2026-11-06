import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/profile/data/repository/profile_repository.dart';

import '../../support/remote_wire_harness.dart';

void main() {
  test(
    'UserFetchById wire → Profile.shownName for account menu header',
    () async {
      const id = 'Umenu00000001';
      late String shownName;
      final sent = <WireSent>[];

      await withRemoteWire(
        {
          'UserFetchById': {
            '__typename': 'query_root',
            'user_by_pk': {
              '__typename': 'user',
              'id': id,
              'created_at': '2026-01-01T12:00:00Z',
              'display_name': 'Wire menu user',
              'handle': 'wiremenu',
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
          final profile = await ProfileRepository(remote).fetchById(id);
          shownName = profile.shownName;
        },
      );

      expect(sent.single.operationName, 'UserFetchById');
      expect(shownName, 'Wire menu user');
    },
  );
}
