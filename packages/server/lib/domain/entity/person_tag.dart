import 'package:meta/meta.dart';

/// One of an owner's private tags over other people (#699).
@immutable
final class PersonTag {
  const PersonTag({
    required this.id,
    required this.name,
    required this.glyph,
    required this.color,
    required this.ord,
    this.count = 0,
    this.countOffField = 0,
  });

  factory PersonTag.fromJson(Map<String, dynamic> json) => PersonTag(
    id: json['id']! as String,
    name: json['name']! as String,
    glyph: json['glyph']! as String,
    color: json['color']! as int,
    ord: json['ord']! as int,
  );

  final String id;
  final String name;
  final String glyph;
  final int color;
  final int ord;

  /// Members not hidden by a block, and of those the ones off the owner's
  /// Field. Derived on read: not part of [toJson] and not compared.
  final int count;
  final int countOffField;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'glyph': glyph,
    'color': color,
    'ord': ord,
  };

  /// The GraphQL `PersonTag` object: [toJson] plus the derived counts.
  Map<String, dynamic> toGraphQL() => {
    ...toJson(),
    'count': count,
    'countOffField': countOffField,
  };

  @override
  bool operator ==(Object other) =>
      other is PersonTag &&
      other.id == id &&
      other.name == name &&
      other.glyph == glyph &&
      other.color == color &&
      other.ord == ord;

  @override
  int get hashCode => Object.hash(id, name, glyph, color, ord);
}

/// What a delete removed, enough to restore it: the tag and its members
/// (`memberIds[i]` was added with `sources[i]`).
final class PersonTagSnapshot {
  const PersonTagSnapshot({
    required this.tag,
    required this.memberIds,
    required this.sources,
  });

  factory PersonTagSnapshot.fromJson(Map<String, dynamic> json) =>
      PersonTagSnapshot(
        tag: PersonTag.fromJson(
          Map<String, dynamic>.from(json['tag']! as Map),
        ),
        memberIds: List<String>.from(json['memberIds']! as List),
        sources: List<int>.from(json['sources']! as List),
      );

  final PersonTag tag;
  final List<String> memberIds;
  final List<int> sources;

  Map<String, dynamic> toJson() => {
    'tag': tag.toJson(),
    'memberIds': memberIds,
    'sources': sources,
  };
}

/// The people in one of the owner's tags, blocked people left out.
final class PersonTagMembers {
  const PersonTagMembers({required this.tagId, required this.personIds});

  final String tagId;
  final List<String> personIds;

  Map<String, dynamic> toJson() => {'tagId': tagId, 'personIds': personIds};
}

/// One add or remove of a person in a tag, with the add's `source`.
final class PersonTagMemberOp {
  const PersonTagMemberOp({
    required this.tagId,
    required this.personId,
    required this.add,
    required this.source,
  });

  final String tagId;
  final String personId;
  final bool add;
  final int source;
}
