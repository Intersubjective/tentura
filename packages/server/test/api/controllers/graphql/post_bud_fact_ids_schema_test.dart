@Tags(['repo-files'])
library;

import 'dart:io';
import 'dart:isolate';

import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/gql_nodel_base.dart';
import 'package:tentura_server/api/controllers/graphql/mutation/mutation_post_bud.dart';
import 'package:tentura_server/domain/use_case/post_bud_case.dart';

class _PostBudCase extends Fake implements PostBudCase {}

Future<String> _clientSchema() async {
  final lib = await Isolate.resolvePackageUri(
    Uri.parse('package:tentura_server/'),
  );
  return File.fromUri(
    lib!.resolve('../../client/lib/data/gql/schema.graphql'),
  ).readAsStringSync();
}

/// `name: Type` pairs of an SDL argument list (a default value stays part
/// of the type text).
Map<String, String> _args(String list) => {
  for (final part in list.split(','))
    if (part.trim().isNotEmpty)
      part.split(':').first.trim(): part
          .substring(part.indexOf(':') + 1)
          .trim(),
};

void main() {
  final mutation = MutationPostBud(postBudCase: _PostBudCase());

  group('Budding a Request with ticked Post facts over GraphQL', () {
    GraphQLObjectField<dynamic, dynamic> budField() =>
        mutation.all.singleWhere((f) => f.name == 'beaconBudFromPost');

    test('the server beaconBudFromPost accepts an optional factIds list of '
        'ids and still answers a PostBudResult', () {
      final field = budField();
      final inputs = {for (final a in field.inputs) a.name: '${a.type}'};
      expect(inputs, containsPair('factIds', '[String!]'));
      expect(inputs, containsPair('postId', 'String!'));
      expect(inputs, containsPair('clientCommandId', 'String!'));
      expect(inputs.keys, containsAll(['title', 'invitees', 'closePost']));
      // The server prints its type without the client's `v2_` prefix.
      expect('${field.type}', 'PostBudResult!');
    });

    test('the client schema copy of beaconBudFromPost declares factIds next '
        'to its other arguments, with the return type unchanged', () async {
      final schema = await _clientSchema();
      expect(
        schema,
        contains('beaconBudFromPost('),
        reason: 'client schema lacks beaconBudFromPost',
      );
      // `[^)]*` spans newlines, so wrapped argument lists match too.
      final line = RegExp(
        r'^\s*beaconBudFromPost\(([^)]*)\)\s*:\s*(\S+)\s*$',
        multiLine: true,
      ).firstMatch(schema);
      expect(
        line,
        isNotNull,
        reason:
            'beaconBudFromPost is in the client schema but its argument '
            'list and return type could not be read',
      );
      final args = _args(line!.group(1)!);
      expect(args, containsPair('factIds', '[String!]'));
      expect(args, containsPair('postId', 'String!'));
      expect(args, containsPair('clientCommandId', 'String!'));
      expect(args, containsPair('title', 'String!'));
      expect(args, containsPair('invitees', '[v2_PostBudInviteeInput!]'));
      expect(line.group(2), 'v2_PostBudResult!');
    });
  });
}
