import '../../domain/entity/people_tags_entities.dart';
import '../gql/_g/person_auto_tag_pref_set.data.gql.dart';
import '../gql/_g/person_auto_tags.data.gql.dart';
import '../gql/_g/person_tag_create.data.gql.dart';
import '../gql/_g/person_tag_delete.data.gql.dart';
import '../gql/_g/person_tag_memberships.data.gql.dart';
import '../gql/_g/person_tag_restore.data.gql.dart';
import '../gql/_g/person_tag_suggestion_record.data.gql.dart';
import '../gql/_g/person_tag_suggestion_state.data.gql.dart';
import '../gql/_g/person_tag_update.data.gql.dart';
import '../gql/_g/person_tags.data.gql.dart';
import '../gql/_g/person_tags_of.data.gql.dart';

/// Typed GraphQL results to entities, and entities back to wire payloads.
///
/// Each operation selects its own generated class (no shared fragment), so
/// the same entity has one small mapper per result type; a schema rename
/// fails to compile here instead of failing a cast at runtime.

extension PersonTagsDataMapper on GPersonTagsData_personTags {
  PersonTag toEntity() => PersonTag(
    id: id,
    name: name,
    glyph: glyph,
    color: color,
    ord: ord,
    count: count,
    countOffField: countOffField,
  );
}

extension PersonTagCreateDataMapper on GPersonTagCreateData_personTagCreate {
  PersonTag toEntity() => PersonTag(
    id: id,
    name: name,
    glyph: glyph,
    color: color,
    ord: ord,
    count: count,
    countOffField: countOffField,
  );
}

extension PersonTagUpdateDataMapper on GPersonTagUpdateData_personTagUpdate {
  PersonTag toEntity() => PersonTag(
    id: id,
    name: name,
    glyph: glyph,
    color: color,
    ord: ord,
    count: count,
    countOffField: countOffField,
  );
}

extension PersonTagRestoreDataMapper on GPersonTagRestoreData_personTagRestore {
  PersonTag toEntity() => PersonTag(
    id: id,
    name: name,
    glyph: glyph,
    color: color,
    ord: ord,
    count: count,
    countOffField: countOffField,
  );
}

extension PersonTagDeleteDataMapper on GPersonTagDeleteData_personTagDelete {
  PersonTagSnapshot toEntity() => PersonTagSnapshot(
    tag: PersonTag(
      id: tag.id,
      name: tag.name,
      glyph: tag.glyph,
      color: tag.color,
      ord: tag.ord,
      count: tag.count,
      countOffField: tag.countOffField,
    ),
    memberIds: memberIds.toList(),
    sources: sources.toList(),
  );
}

extension PersonTagMembershipsDataMapper
    on GPersonTagMembershipsData_personTagMemberships {
  PersonTagMembers toEntity() => PersonTagMembers(
    tagId: tagId,
    personIds: personIds.toList(),
    inherited: [
      for (final i in inherited)
        PersonTagInherited(personId: i.personId, inviterId: i.inviterId),
    ],
  );
}

extension PersonAutoTagsDataMapper on GPersonAutoTagsData_personAutoTags {
  PersonAutoTag toEntity() =>
      PersonAutoTag(kind: kind, count: count, showInFilters: showInFilters);
}

extension PersonAutoTagPrefSetDataMapper
    on GPersonAutoTagPrefSetData_personAutoTagPrefSet {
  PersonAutoTag toEntity() =>
      PersonAutoTag(kind: kind, count: count, showInFilters: showInFilters);
}

extension PersonTagsOfDataMapper on GPersonTagsOfData_personTagsOf {
  PersonTagsOf toEntity() => PersonTagsOf(
    own: own.toList(),
    auto: [
      for (final a in auto)
        PersonAutoTagOf(kind: a.kind, n: a.n, direction: a.direction),
    ],
  );
}

extension PersonTagSuggestionStateDataMapper
    on GPersonTagSuggestionStateData_personTagSuggestionState {
  PersonTagSuggestionState toEntity() => PersonTagSuggestionState(
    canSuggest: canSuggest,
    disabled: disabled,
    silencedUntil: silencedUntil?.toUtc(),
  );
}

extension PersonTagSuggestionRecordDataMapper
    on GPersonTagSuggestionRecordData_personTagSuggestionRecord {
  PersonTagSuggestionState toEntity() => PersonTagSuggestionState(
    canSuggest: canSuggest,
    disabled: disabled,
    silencedUntil: silencedUntil?.toUtc(),
  );
}

Map<String, Object> personTagToWire(PersonTag tag) => {
  'id': tag.id,
  'name': tag.name,
  'glyph': tag.glyph,
  'color': tag.color,
  'ord': tag.ord,
};

Map<String, Object> personTagSnapshotToWire(PersonTagSnapshot snapshot) => {
  'tag': personTagToWire(snapshot.tag),
  'memberIds': snapshot.memberIds,
  'sources': snapshot.sources,
};

Map<String, Object> personTagMemberOpToWire(PersonTagMemberOp op) => {
  'tagId': op.tagId,
  'personId': op.personId,
  'op': op.keep ? 'keep' : (op.add ? 'add' : 'remove'),
  'source': op.source,
};
