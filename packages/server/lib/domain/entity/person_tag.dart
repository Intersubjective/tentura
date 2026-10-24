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

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'glyph': glyph,
    'color': color,
    'ord': ord,
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
