import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';

/// Maps an untyped person tag JSON fixture (e.g. a server fixture's stdout)
/// to its entity. Production code maps the typed GraphQL classes instead.
PersonTag personTagFromJsonFixture(Map<String, dynamic> json) => PersonTag(
  id: json['id']! as String,
  name: json['name']! as String,
  glyph: json['glyph']! as String,
  color: json['color']! as int,
  ord: json['ord']! as int,
  count: json['count'] as int? ?? 0,
  countOffField: json['countOffField'] as int? ?? 0,
);
