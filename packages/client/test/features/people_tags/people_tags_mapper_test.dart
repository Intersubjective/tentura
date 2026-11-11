import 'package:built_collection/built_collection.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/people_tags/data/gql/_g/person_auto_tags.data.gql.dart';
import 'package:tentura/features/people_tags/data/gql/_g/person_tag_delete.data.gql.dart';
import 'package:tentura/features/people_tags/data/gql/_g/person_tag_memberships.data.gql.dart';
import 'package:tentura/features/people_tags/data/gql/_g/person_tag_suggestion_state.data.gql.dart';
import 'package:tentura/features/people_tags/data/gql/_g/person_tags.data.gql.dart';
import 'package:tentura/features/people_tags/data/gql/_g/person_tags_of.data.gql.dart';
import 'package:tentura/features/people_tags/data/model/people_tags_mapper.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';

void main() {
  group('people tags wire mapping', () {
    test('a tag maps to an entity with its derived counts', () {
      final tag = GPersonTagsData_personTags(
        (b) => b
          ..id = 'T1'
          ..name = 'Neighbours'
          ..glyph = 'N'
          ..color = 3
          ..ord = 2
          ..count = 5
          ..countOffField = 1,
      ).toEntity();

      expect(
        tag,
        const PersonTag(
          id: 'T1',
          name: 'Neighbours',
          glyph: 'N',
          color: 3,
          ord: 2,
          count: 5,
          countOffField: 1,
        ),
      );
    });

    test('memberships map to one entry per tag in order', () {
      final members = [
        for (final m in [
          GPersonTagMembershipsData_personTagMemberships(
            (b) => b
              ..tagId = 'T1'
              ..personIds = ListBuilder(['Ua', 'Ub']),
          ),
          GPersonTagMembershipsData_personTagMemberships(
            (b) => b..tagId = 'T2',
          ),
        ])
          m.toEntity(),
      ];

      expect(members.map((m) => m.tagId), ['T1', 'T2']);
      expect(members.first.personIds, ['Ua', 'Ub']);
      expect(members.last.personIds, isEmpty);
    });

    test('memberships carry inherited members with their inviter', () {
      final members = GPersonTagMembershipsData_personTagMemberships(
        (b) => b
          ..tagId = 'Ta'
          ..personIds = ListBuilder(['Ucarol', 'Ubob'])
          ..inherited.add(
            GPersonTagMembershipsData_personTagMemberships_inherited(
              (i) => i
                ..personId = 'Ucarol'
                ..inviterId = 'Ubob',
            ),
          ),
      ).toEntity();

      expect(
        members.inherited,
        [const PersonTagInherited(personId: 'Ucarol', inviterId: 'Ubob')],
      );
    });

    test('an automatic tag keeps its count and filter switch', () {
      expect(
        GPersonAutoTagsData_personAutoTags(
          (b) => b
            ..kind = 2
            ..count = 7
            ..showInFilters = true,
        ).toEntity(),
        const PersonAutoTag(kind: 2, count: 7, showInFilters: true),
      );
    });

    test('suggestion state keeps the silence deadline in UTC', () {
      final state = GPersonTagSuggestionStateData_personTagSuggestionState(
        (b) => b
          ..canSuggest = false
          ..disabled = false
          ..silencedUntil = DateTime.parse('2026-11-01T13:00:00+03:00'),
      ).toEntity();

      expect(state.canSuggest, isFalse);
      expect(state.silencedUntil, DateTime.utc(2026, 11, 1, 10));
      expect(state.silencedUntil!.isUtc, isTrue);
    });

    test('suggestion state without a silence deadline has none', () {
      final state = GPersonTagSuggestionStateData_personTagSuggestionState(
        (b) => b
          ..canSuggest = true
          ..disabled = false,
      ).toEntity();

      expect(state.silencedUntil, isNull);
      expect(state.canSuggest, isTrue);
    });

    test('personTagsOf maps own tag ids and automatic tags of the person', () {
      final of = GPersonTagsOfData_personTagsOf(
        (b) => b
          ..own = ListBuilder(['Ta', 'Tb'])
          ..auto.add(
            GPersonTagsOfData_personTagsOf_auto(
              (a) => a
                ..kind = 1
                ..n = 3
                ..direction = -1,
            ),
          ),
      ).toEntity();

      expect(of.own, ['Ta', 'Tb']);
      expect(of.auto, [const PersonAutoTagOf(kind: 1, n: 3, direction: -1)]);
    });

    test('personTagsOf with nothing maps to empty lists', () {
      final of = GPersonTagsOfData_personTagsOf((b) => b).toEntity();

      expect(of.own, isEmpty);
      expect(of.auto, isEmpty);
    });

    test(
      'a deleted tag snapshot keeps the tag and its members with sources',
      () {
        final snapshot = GPersonTagDeleteData_personTagDelete(
          (b) => b
            ..tag.id = 'T1'
            ..tag.name = 'Neighbours'
            ..tag.glyph = 'N'
            ..tag.color = 3
            ..tag.ord = 2
            ..tag.count = 0
            ..tag.countOffField = 0
            ..memberIds = ListBuilder(['Ua', 'Ub'])
            ..sources = ListBuilder([0, 1]),
        ).toEntity();

        expect(snapshot.tag.id, 'T1');
        expect(snapshot.memberIds, ['Ua', 'Ub']);
        expect(snapshot.sources, [0, 1]);
      },
    );

    test('a snapshot converts back to the restore wire input', () {
      const snapshot = PersonTagSnapshot(
        tag: PersonTag(id: 'T1', name: 'N', glyph: 'N', color: 3, ord: 2),
        memberIds: ['Ua'],
        sources: [0],
      );

      final wire = personTagSnapshotToWire(snapshot);

      expect(wire['memberIds'], ['Ua']);
      expect(wire['sources'], [0]);
      expect((wire['tag']! as Map)['id'], 'T1');
    });

    test('a membership op converts to the apply wire input', () {
      const op = PersonTagMemberOp(tagId: 'Ta', personId: 'Ub', add: false);

      expect(personTagMemberOpToWire(op), {
        'tagId': 'Ta',
        'personId': 'Ub',
        'op': 'remove',
        'source': 0,
      });
    });

    test('a keep membership op converts to the keep wire input', () {
      const op = PersonTagMemberOp(
        tagId: 'Ta',
        personId: 'Ub',
        add: false,
        keep: true,
      );

      expect(personTagMemberOpToWire(op)['op'], 'keep');
    });
  });
}
