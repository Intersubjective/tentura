@Tags(['repo-files'])
library;

import 'dart:io';

import 'package:test/test.dart';

// The client generates its GraphQL types from this copy of the schema, so
// the picker can only explain a suggestion if the reach object is in it.
void main() {
  test(
    'client codegen can select why a suggested recipient is listed on every user row',
    () {
      final schema = File(
        '../client/lib/data/gql/schema.graphql',
      ).readAsStringSync();

      String body(String keyword, String name) {
        final declaration = schema.split(RegExp('$keyword $name\\s*\\{'));
        expect(
          declaration,
          hasLength(2),
          reason: '$keyword $name must be declared once for client codegen',
        );
        return declaration.last.split('\n}').first;
      }

      String fieldType(String typeBody, String field) {
        final lines = typeBody
            .split('\n')
            .where((line) => line.trimLeft().startsWith('$field:'))
            .toList();
        expect(lines, hasLength(1), reason: '$field must be selectable');
        return lines.single.split(':').last.trim();
      }

      String named(String type) =>
          type.replaceAll(RegExp(r'[\[\]!]'), '').trim();

      final reachType = fieldType(body('type', 'v2_user'), 'forward_reach');
      expect(
        reachType,
        isNot(endsWith('!')),
        reason: 'Only forwardCandidates rows carry a reach; others are null',
      );
      final reach = body('type', named(reachType));

      final kind = body('enum', named(fieldType(reach, 'kind')));
      final kindValues = kind
          .split('\n')
          .map((line) => line.trim())
          .where((line) => RegExp(r'^[a-z_]+$').hasMatch(line))
          .toSet();
      expect(kindValues, {
        'direct',
        'via_connection',
        'shared_request',
        'wider',
      });

      final via = fieldType(reach, 'via');
      expect(via, startsWith('['), reason: 'via lists up to two vouchers');
      final voucher = body('type', named(via));
      for (final field in ['id', 'displayName', 'image']) {
        fieldType(voucher, field);
      }
      expect(named(fieldType(voucher, 'image')), 'v2_image');

      expect(named(fieldType(reach, 'via_count')), 'Int');
      expect(fieldType(reach, 'shared_request_id'), 'String');
      expect(fieldType(reach, 'shared_request_title'), 'String');
    },
  );
}
