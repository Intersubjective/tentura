@Tags(['repo-files'])
library;

import 'dart:io';

import 'package:graphql_schema2/graphql_schema2.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/custom_types.dart';

const _edgeFields = {
  'createdAt': 'String',
  'forwardedOn': 'Boolean',
  'readAt': 'String',
  'declinedInvite': 'Boolean',
};

const _offerStatuses = [
  'none',
  'offered',
  'accepted',
  'withdrawn',
  'declinedByAuthor',
];

void main() {
  group('Forward tree recipient states on the existing query', () {
    test('served offer status is a non-null string or an enum declaring '
        'exactly the five public status values', () {
      final type = _servedOfferStatusType();
      if (type is GraphQLEnumType) {
        expect(
          type.values.map((value) => value.name),
          unorderedEquals(_offerStatuses),
        );
      } else {
        // The PG GraphQL tests assert all five string values on actual
        // recipient offers. Int, Boolean, JSON and arbitrary named types
        // cannot stand in for this public string representation.
        expect(type, same(graphQLString));
      }
    });

    test('client offer status uses the served string or enum contract and '
        'declares the same five enum values', () {
      final schema = File(
        '../client/lib/data/gql/schema.graphql',
      ).readAsStringSync();
      final edgeBody = _body(schema, 'type', 'v2_ForwardGraphEdge');
      final matches = RegExp(
        r'\bofferStatus\s*:\s*([\w!\[\]]+)',
      ).allMatches(edgeBody).toList();
      expect(matches, hasLength(1), reason: 'offerStatus must be selectable');
      final declaredType = matches.single.group(1)!;
      final servedType = _servedOfferStatusType();
      if (servedType is GraphQLEnumType) {
        expect(declaredType, 'v2_${servedType.name}');
        final enumBody = _body(schema, 'enum', 'v2_${servedType.name}');
        final values = enumBody
            .replaceAll(RegExp('""".*?"""', dotAll: true), '')
            .replaceAll(RegExp(r'#[^\n]*'), '')
            .split(RegExp(r'\s+'))
            .where((value) => value.isNotEmpty);
        expect(values, unorderedEquals(_offerStatuses));
        expect(
          servedType.values.map((value) => value.name),
          unorderedEquals(_offerStatuses),
        );
      } else {
        expect(servedType, same(graphQLString));
        expect(declaredType, 'String');
      }
    });

    test('the served edge exposes replay time and recipient states with '
        'nullable private signals', () {
      final fields = {
        for (final field in gqlTypeForwardGraphEdge.fields)
          field.name: field.type.toString(),
      };
      for (final entry in _edgeFields.entries) {
        expect(
          fields,
          containsPair(entry.key, entry.value),
          reason:
              'clients must select ${entry.key} on beaconForwardGraph.edges',
        );
      }
    });

    test('each served edge names its sender and recipient as person nodes '
        'that can be anonymous', () {
      final fields = {
        for (final field in gqlTypeForwardGraphEdge.fields) field.name: field,
      };
      for (final side in ['sender', 'recipient']) {
        expect(fields, contains(side), reason: 'edges must expose $side');
        final type = fields[side]!.type;
        // Nullable: beaconHelpOffererForwardPath shares this type and does
        // not supply them.
        expect(
          type,
          same(gqlTypeHelpPathNode),
          reason: '$side is a named or anonymous person node',
        );
      }
    });

    test(
      'client codegen can select edge sender and recipient person nodes',
      () {
        final schema = File(
          '../client/lib/data/gql/schema.graphql',
        ).readAsStringSync();
        final edgeBody = _body(schema, 'type', 'v2_ForwardGraphEdge');
        for (final side in ['sender', 'recipient']) {
          expect(
            RegExp(
              '\\b$side\\s*:\\s*v2_HelpPathNode\\b(?!!)',
            ).hasMatch(edgeBody),
            isTrue,
            reason: '$side must reach generated client operations',
          );
        }
      },
    );

    test('client codegen can select the same replay time and recipient states '
        'with nullable private signals', () {
      final schema = File(
        '../client/lib/data/gql/schema.graphql',
      ).readAsStringSync();
      final declaration = schema.split(
        RegExp(r'type v2_ForwardGraphEdge\s*\{'),
      );
      expect(declaration, hasLength(2));
      final body = declaration.last.split('\n}').first;
      final fields = <String, String>{};
      for (final match in RegExp(
        r'(\w+)\s*:\s*([\w!\[\]]+)',
      ).allMatches(body)) {
        fields[match.group(1)!] = match.group(2)!;
      }
      for (final entry in _edgeFields.entries) {
        expect(
          fields,
          containsPair(entry.key, entry.value),
          reason: '${entry.key} must reach generated client operations',
        );
      }
    });
  });
}

GraphQLType<dynamic, dynamic> _servedOfferStatusType() {
  final fields = {
    for (final field in gqlTypeForwardGraphEdge.fields) field.name: field,
  };
  expect(fields, contains('offerStatus'));
  final declaredType = fields['offerStatus']!.type;
  return declaredType;
}

String _body(String schema, String kind, String name) {
  final declarations = RegExp(
    '\\b$kind\\s+${RegExp.escape(name)}\\s*\\{([^}]*)\\}',
    dotAll: true,
  ).allMatches(schema).toList();
  expect(
    declarations,
    hasLength(1),
    reason: '$kind $name must be declared once',
  );
  return declarations.single.group(1)!;
}
