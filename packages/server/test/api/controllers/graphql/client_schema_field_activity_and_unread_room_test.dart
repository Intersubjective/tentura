@Tags(['repo-files'])
library;

import 'dart:io';
import 'dart:isolate';

import 'package:graphql_schema2/graphql_schema2.dart';
import 'package:graphql_server2/graphql_server2.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/custom_types.dart';

// The client generates its GraphQL types from its checked-in copy of the merged
// schema (the server's remote schema is exposed there with a `v2_` prefix), so
// a field the server serves but the copy lacks cannot be selected by the app.
// The expectation is derived from the server's own schema through introspection,
// not from a hand-written list, so any drift of these two types fails here.
//
// The checked-in schema is read relative to this package, whatever the working
// directory of the test run is.
Future<File> _clientSchema() async {
  final lib = await Isolate.resolvePackageUri(
    Uri.parse('package:tentura_server/'),
  );
  return File.fromUri(lib!.resolve('../../client/lib/data/gql/schema.graphql'));
}

void main() {
  final graphQL = GraphQL(
    GraphQLSchema(
      queryType: GraphQLObjectType('Query', null)
        ..fields.addAll([
          GraphQLObjectField(
            'constellationRequest',
            gqlTypeConstellationRequest,
            resolve: (_, _) => null,
          ),
          GraphQLObjectField(
            'inboxRoomContextRow',
            gqlTypeInboxRoomContextRow,
            resolve: (_, _) => null,
          ),
        ]),
    ),
    customTypes: customTypes,
  );

  Future<Map<String, String>> serverScalarFields(String type) async {
    final result =
        await graphQL.parseAndExecute('''
query {
  __type(name: "$type") {
    fields {
      name
      type { kind name ofType { kind name ofType { kind name ofType { kind name } } } }
    }
  }
}
''')
            as Map<String, dynamic>;
    final fields = (result['__type'] as Map)['fields'] as List;
    // Nullability is not compared: the merged schema tightens it for some
    // scalar fields, so only the leaf scalar a field resolves to must match.
    String? leaf(Map<String, dynamic>? ref) => switch (ref?['kind']) {
      'SCALAR' => ref!['name'] as String,
      'NON_NULL' || 'LIST' => leaf(ref!['ofType'] as Map<String, dynamic>?),
      // Object-typed fields are renamed with a prefix in the merged schema.
      _ => null,
    };
    return {
      for (final field in fields.cast<Map<String, dynamic>>())
        if (leaf(field['type'] as Map<String, dynamic>) case final String t)
          field['name'] as String: t,
    };
  }

  Future<Map<String, String>> clientFields(String type) async {
    final lines = (await _clientSchema()).readAsLinesSync();
    final start = lines.indexWhere(
      (line) => RegExp('^type v2_$type\\s*\\{').hasMatch(line),
    );
    expect(start, isNot(-1), reason: 'Client schema must contain v2_$type');
    final fields = <String, String>{};
    for (final line in lines.skip(start + 1)) {
      if (line.trim() == '}') break;
      final match = RegExp(r'^\s{2}(\w+)\s*(?:\([^)]*\))?:\s*(\S+)').firstMatch(
        line,
      );
      if (match != null) {
        expect(
          fields.containsKey(match.group(1)),
          isFalse,
          reason: 'v2_$type declares ${match.group(1)} more than once',
        );
        fields[match.group(1)!] = match
            .group(2)!
            .replaceAll(
              RegExp(r'[\[\]!]'),
              '',
            );
      }
    }
    return fields;
  }

  for (final type in ['ConstellationRequest', 'InboxRoomContextRow']) {
    test(
      'client schema copy declares every field the server serves on $type',
      () async {
        final served = await serverScalarFields(type);
        final declared = await clientFields(type);
        expect(served, isNotEmpty, reason: 'server introspection of $type');
        final drift = <String>[
          for (final MapEntry(:key, :value) in served.entries)
            if (declared[key] != value)
              '$key: server $value, client schema ${declared[key] ?? 'missing'}',
        ];
        expect(
          drift,
          isEmpty,
          reason:
              'Regenerate the client schema from the server; drifted fields '
              'of $type cannot be selected by the app',
        );
      },
    );
  }
}
