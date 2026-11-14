@Tags(['repo-files'])
library;

import 'dart:io';
import 'dart:isolate';

import 'package:graphql_schema2/graphql_schema2.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/custom_types.dart';
import 'package:tentura_server/domain/exception_codes.dart';

Future<Uri> _serverLib() async => (await Isolate.resolvePackageUri(
  Uri.parse('package:tentura_server/'),
))!;

Future<String> _clientSchema() async => File.fromUri(
  (await _serverLib()).resolve('../../client/lib/data/gql/schema.graphql'),
).readAsStringSync();

String _bare(String sdl) => sdl.replaceAll(RegExp(r'[\[\]!]'), '').trim();

/// The arguments of root field [name] in [sdl], whatever the line wrapping:
/// `{argName: 'Type!'}` with all whitespace removed from the type.
Map<String, String>? _sdlArgs(String sdl, String name) {
  final match = RegExp(
    '(?:^|\\s)${RegExp.escape(name)}\\s*\\(([^)]*)\\)\\s*:',
  ).firstMatch(sdl);
  if (match == null) return null;
  return {
    for (final part in match.group(1)!.split(RegExp(r'[,\n]')))
      if (part.trim().isNotEmpty)
        part.split(':').first.trim(): part
            .split(':')
            .last
            .replaceAll(RegExp(r'\s'), ''),
  };
}

/// Saved facts on the wire: the fact row says whether the viewer saved it,
/// the client's schema copy carries the Save / Unsave mutations, and the
/// over-the-cap error has its own code.
void main() {
  group('saved facts in the GraphQL schema', () {
    test('a fact row carries a non-null Boolean savedByMe flag', () {
      final saved = gqlTypeBeaconFactCardRow.fields
          .where((f) => f.name == 'savedByMe')
          .toList();
      expect(saved, hasLength(1), reason: 'BeaconFactCardRow.savedByMe');
      final type = saved.single.type;
      expect(type, isA<GraphQLNonNullableType<dynamic, dynamic>>());
      final inner = (type as GraphQLNonNullableType<dynamic, dynamic>).ofType;
      expect(inner, isA<GraphQLScalarType<dynamic, dynamic>>());
      expect(inner.name, graphQLBoolean.name);
    });

    test('the client schema copy declares Save, Unsave and the savedByMe '
        'row field', () async {
      final schema = await _clientSchema();

      expect(
        _sdlArgs(schema, 'BeaconFactCardSave'),
        {'beaconId': 'String!', 'factCardId': 'String!'},
        reason: 'client schema BeaconFactCardSave(beaconId, factCardId)',
      );
      expect(
        _sdlArgs(schema, 'BeaconFactCardUnsave'),
        {'factCardId': 'String!'},
        reason: 'client schema BeaconFactCardUnsave(factCardId)',
      );

      final listType = RegExp(
        r'BeaconFactCardList\s*\([^)]*\)\s*:\s*([\[\]\w!]+)',
      ).firstMatch(schema);
      expect(listType, isNotNull, reason: 'client schema lacks the list query');
      final rowType = _bare(listType!.group(1)!);
      final row = RegExp(
        'type ${RegExp.escape(rowType)}\\s*\\{([^}]*)\\}',
      ).firstMatch(schema);
      expect(row, isNotNull, reason: 'client schema lacks $rowType');
      expect(row!.group(1), matches(RegExp(r'savedByMe\s*:\s*Boolean\s*!')));
    });
  });

  group('the saved-fact limit error', () {
    test('has its own Beacon code, appended right after '
        'factCopySourceUnavailable as 1353', () {
      const previous = BeaconExceptionCode.factCopySourceUnavailable;
      expect(const BeaconExceptionCodes(previous).codeNumber, 1352);
      final next = BeaconExceptionCode.values
          .where((c) => c.index == previous.index + 1)
          .toList();
      expect(next, hasLength(1), reason: 'a code after 1352');
      expect(BeaconExceptionCodes(next.single).codeNumber, 1353);
    });
  });
}
