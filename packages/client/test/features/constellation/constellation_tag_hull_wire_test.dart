import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/env.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';
import 'package:tentura/features/people_tags/data/repository/people_tags_repository.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';

import '../../support/constellation_tag_lens_body_harness.dart';
import '../../support/remote_wire_harness.dart';
import '../../support/test_realtime_sync.dart';

Map<String, dynamic> _tagWire(PersonTag tag) => {
  '__typename': 'PersonTag',
  'id': tag.id,
  'name': tag.name,
  'glyph': tag.glyph,
  'color': tag.color,
  'ord': tag.ord,
  'count': 0,
  'countOffField': 0,
};

void main() {
  group('tag hull memberships on the wire', () {
    test(
      'PersonTags and PersonTagMemberships map to the field hull tag ids',
      () async {
        const tags = [
          tagLensNeighbour,
          tagLensWorkshop,
          tagLensGarden,
          tagLensEmpty,
        ];
        final sent = <WireSent>[];
        await withRemoteWire(
          {
            'PersonTags': {
              '__typename': 'query_root',
              'personTags': [for (final tag in tags) _tagWire(tag)],
            },
            'PersonTagMemberships': {
              '__typename': 'query_root',
              'personTagMemberships': [
                for (final m in tagLensMemberships)
                  {
                    '__typename': 'PersonTagMembership',
                    'tagId': m.tagId,
                    'personIds': m.personIds,
                    'inherited': <Map<String, dynamic>>[],
                  },
              ],
            },
          },
          sent,
          (remote) async {
            final sync = buildTestRealtimeSync();
            addTearDown(() async => sync.port.dispose());
            final repository = PeopleTagsRepository(remote);
            final peopleTags = PeopleTagsCase(
              repository,
              sync.case_,
              env: const Env(),
              logger: Logger('ConstellationTagHullWireTest'),
            );
            addTearDown(() async => peopleTags.dispose());
            await peopleTags.load();

            expect(
              peopleTags.tags.map((t) => t.id),
              containsAll([
                tagLensNeighbour.id,
                tagLensWorkshop.id,
                tagLensGarden.id,
                tagLensEmpty.id,
              ]),
            );
            expect(peopleTags.peopleInTag(tagLensGarden.id), {
              'ann',
              'bob',
              'cid',
            });
            expect(peopleTags.peopleInTag(tagLensEmpty.id), isEmpty);
          },
        );
        expect(
          sent.map((s) => s.operationName),
          containsAll(['PersonTags', 'PersonTagMemberships']),
        );
      },
    );
  });
}
