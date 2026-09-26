import 'package:graphql_schema2/graphql_schema2.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/custom_types.dart';

GraphQLObjectType _customObject(String name) => customTypes
    .whereType<GraphQLObjectType>()
    .singleWhere((t) => t.name == name);

/// tentura-617.17 (issue #181 plan §8.11): `RoomMessageList` rows expose the
/// quoted revision snapshot as a nullable nested `quotedFact` object.
void main() {
  group('RoomMessageRow.quotedFact', () {
    test('RoomMessageRow has a nullable object field quotedFact', () {
      final field = _customObject(
        'RoomMessageRow',
      ).fields.singleWhere((f) => f.name == 'quotedFact');
      expect(
        field.type,
        isNot(isA<GraphQLNonNullableType<dynamic, dynamic>>()),
      );
      expect(field.type, isA<GraphQLObjectType>());
    });

    test('the quotedFact type is registered and carries the snapshot', () {
      final field = _customObject(
        'RoomMessageRow',
      ).fields.singleWhere((f) => f.name == 'quotedFact');
      final type = field.type as GraphQLObjectType;
      expect(
        customTypes.whereType<GraphQLObjectType>().map((t) => t.name),
        contains(type.name),
        reason: 'nested type must be in the schema export list',
      );

      final byName = {for (final f in type.fields) f.name: f.type};
      const nonNull = [
        'factCardId',
        'seq',
        'text',
        'pinnedByTitle',
        'visibility',
        'status',
        'currentSeq',
      ];
      expect(byName.keys, containsAll([...nonNull, 'pinnedById']));
      for (final name in nonNull) {
        expect(
          byName[name],
          isA<GraphQLNonNullableType<dynamic, dynamic>>(),
          reason: name,
        );
      }
      expect(
        byName['pinnedById'],
        isNot(isA<GraphQLNonNullableType<dynamic, dynamic>>()),
        reason: 'pinner may be erased',
      );
    });
  });
}
