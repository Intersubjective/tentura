@Tags(['repo-files'])
library;

import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'client codegen can query a persons Field item buckets search and continuation with tab counts',
    () {
      final schema = File(
        '../client/lib/data/gql/schema.graphql',
      ).readAsStringSync();
      final root = schema.split('type query_root {').last.split('\n}').first;
      final fields = root
          .split('\n')
          .where((line) => line.trimLeft().startsWith('personFieldItems('));
      expect(
        fields,
        hasLength(1),
        reason: 'Client consumers must be able to query personFieldItems',
      );
      final field = fields.single;
      for (final argument in ['personId', 'bucket', 'query', 'cursor']) {
        expect(
          field,
          matches('\\b$argument\\s*:'),
          reason: '$argument must be available to client codegen',
        );
      }
      String typeBody(String name) {
        final declaration = schema.split('type $name {');
        expect(
          declaration,
          hasLength(2),
          reason: '$name must be selectable by client codegen',
        );
        return declaration.last.split('\n}').first;
      }

      String returnType(String declaration) => declaration
          .substring(declaration.lastIndexOf(':') + 1)
          .trim()
          .replaceAll('!', '');
      final result = typeBody(returnType(field));
      final items = result
          .split('\n')
          .where((line) => line.trimLeft().startsWith('items:'));
      expect(items, hasLength(1));
      expect(items.single, matches(r'\bitems\s*:\s*\['));
      final itemType = returnType(
        items.single,
      ).replaceAll('[', '').replaceAll(']', '');
      final itemBody = typeBody(itemType);
      // These are the existing Field wire names: clients need identity and
      // kind, Request titles, Post root excerpts, and lifecycle/activity data.
      for (final (name, type) in [
        ('id', '(?:String|ID)'),
        ('kind', '(?:Int|String|[A-Za-z_][A-Za-z0-9_]*Kind)'),
        ('authorId', '(?:String|ID)'),
        ('title', 'String'),
        ('rootExcerpt', 'String'),
        ('status', 'Int'),
        ('lastActivityAt', 'String'),
      ]) {
        expect(
          itemBody,
          matches(
            '\\b$name\\s*:\\s*$type'
            r'(?:!|\s|$)',
          ),
          reason:
              '$name must be selectable with a usable type to display Requests and Posts',
        );
      }
      expect(result, matches(r'\bnextCursor\s*:\s*String'));
      final counts = result
          .split('\n')
          .where((line) => line.trimLeft().startsWith('counts:'));
      expect(
        counts,
        hasLength(1),
        reason: 'The person panel needs a count for every tab',
      );
      final countsBody = typeBody(returnType(counts.single));
      for (final bucket in ['active', 'closed', 'hidden']) {
        expect(
          countsBody,
          matches('\\b$bucket\\s*:\\s*Int!'),
          reason: '$bucket count must be selectable',
        );
      }
    },
  );
}
