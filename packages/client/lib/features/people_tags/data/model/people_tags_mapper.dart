import '../../domain/entity/people_tags_entities.dart';

/// Wire payloads (GraphQL JSON) to entities and back.

PersonTag mapPersonTag(Map<String, dynamic> json) => PersonTag(
  id: json['id']! as String,
  name: json['name']! as String,
  glyph: json['glyph']! as String,
  color: json['color']! as int,
  ord: json['ord']! as int,
  count: json['count'] as int? ?? 0,
  countOffField: json['countOffField'] as int? ?? 0,
);

List<PersonTag> mapPersonTags(Iterable<Map<String, dynamic>> json) => [
  for (final t in json) mapPersonTag(t),
];

List<PersonTagMembers> mapPersonTagMembers(
  Iterable<Map<String, dynamic>> json,
) => [
  for (final m in json)
    PersonTagMembers(
      tagId: m['tagId']! as String,
      personIds: List<String>.from(m['personIds']! as List),
    ),
];

PersonAutoTag mapPersonAutoTag(Map<String, dynamic> json) => PersonAutoTag(
  kind: json['kind']! as int,
  count: json['count']! as int,
  showInFilters: json['showInFilters']! as bool,
);

PersonAutoTagOf mapPersonAutoTagOf(Map<String, dynamic> json) =>
    PersonAutoTagOf(
      kind: json['kind']! as int,
      n: json['n']! as int,
      direction: json['direction']! as int,
    );

PersonTagsOf mapPersonTagsOf(Map<String, dynamic> json) => PersonTagsOf(
  own: List<String>.from(json['own']! as List),
  auto: [
    for (final a in json['auto']! as List)
      mapPersonAutoTagOf(Map<String, dynamic>.from(a as Map)),
  ],
);

List<String> mapPersonAutoTagMembers(Iterable<Object?> json) =>
    List<String>.from(json);

PersonTagSuggestionState mapPersonTagSuggestionState(
  Map<String, dynamic> json,
) {
  final until = json['silencedUntil'];
  return PersonTagSuggestionState(
    canSuggest: json['canSuggest']! as bool,
    disabled: json['disabled']! as bool,
    silencedUntil: switch (until) {
      final DateTime d => d.toUtc(),
      final String s => DateTime.parse(s).toUtc(),
      _ => null,
    },
  );
}

PersonTagSnapshot mapPersonTagSnapshot(Map<String, dynamic> json) =>
    PersonTagSnapshot(
      tag: mapPersonTag(Map<String, dynamic>.from(json['tag']! as Map)),
      memberIds: List<String>.from(json['memberIds']! as List),
      sources: List<int>.from(json['sources']! as List),
    );

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
  'add': op.add,
  'source': op.source,
};
