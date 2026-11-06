import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/people_tags/data/repository/people_tags_repository.dart';

import '../../support/remote_wire_harness.dart';

void main() {
  test('PersonTagMemberships maps inherited members from the wire', () async {
    const tagId = 'Ta';
    const carol = 'Ucarol00000001';
    const bob = 'Ubob0000000001';
    final sent = <WireSent>[];
    await withRemoteWire(
      {
        'PersonTagMemberships': {
          '__typename': 'query_root',
          'personTagMemberships': [
            {
              '__typename': 'PersonTagMembers',
              'tagId': tagId,
              'personIds': [carol, bob],
              'inherited': [
                {
                  '__typename': 'PersonTagInherited',
                  'personId': carol,
                  'inviterId': bob,
                },
              ],
            },
          ],
        },
      },
      sent,
      (remote) async {
        final repository = PeopleTagsRepository(remote);
        final memberships = await repository.personTagMemberships();

        expect(sent.single.operationName, 'PersonTagMemberships');
        expect(memberships.single.tagId, tagId);
        expect(memberships.single.personIds, [carol, bob]);
        expect(memberships.single.inherited.single.personId, carol);
        expect(memberships.single.inherited.single.inviterId, bob);
      },
    );
  });
}
