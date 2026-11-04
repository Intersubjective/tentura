@Tags(['repo-files'])
library;

import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'client codegen can query Field search and select its three result groups',
    () {
      final schema = File(
        '../client/lib/data/gql/schema.graphql',
      ).readAsStringSync();
      // The checked-in SDL uses one field per line, as emitted by codegen.
      final root = schema.split('type query_root {');
      expect(root, hasLength(2));
      final search = root.last
          .split('\n}')
          .first
          .split('\n')
          .where(
            (line) => line.trimLeft().startsWith('fieldSearch('),
          );
      expect(
        search,
        hasLength(1),
        reason: 'The client schema must expose the Field search operation',
      );
      final field = search.single;
      expect(field, matches(r'\bquery\s*:\s*String!'));
      expect(field, matches(r'\bcontext\s*:\s*String!?'));
      final resultName = field
          .substring(field.lastIndexOf(':') + 1)
          .trim()
          .replaceAll('!', '');
      final result = schema.split('type $resultName {');
      expect(
        result,
        hasLength(2),
        reason: 'The search result must be selectable by codegen',
      );
      final resultBody = result.last.split('\n}').first;
      for (final group in ['people', 'requests', 'posts']) {
        expect(
          resultBody,
          matches('\\b$group\\s*:\\s*\\['),
          reason: '$group must be a selectable result list',
        );
      }
    },
  );
}
