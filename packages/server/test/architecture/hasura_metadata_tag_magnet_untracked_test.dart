@Tags(['repo-files'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// Tag magnets are private to their viewer and only reachable through the V2
/// API: Hasura must never track the table, and the migration set must actually
/// create it (so the check cannot pass on a table that never existed).
void main() {
  group('Tag magnets', () {
    test('the table is created by a migration', () {
      final migrations = Directory(
        '${Directory.current.path}/lib/data/database/migration',
      ).listSync().whereType<File>();
      expect(
        migrations.any(
          (f) => f.readAsStringSync().contains('constellation_tag_magnet'),
        ),
        isTrue,
      );
    });

    test('Hasura does not track the tag magnet table', () {
      final metadata =
          jsonDecode(
                File(
                  '${Directory.current.path}/../../hasura/metadata.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final sources =
          (metadata['metadata'] as Map<String, dynamic>)['sources']
              as List<dynamic>;
      final tables =
          (sources.first as Map<String, dynamic>)['tables'] as List<dynamic>;
      final tracked = tables
          .cast<Map<String, dynamic>>()
          .map((e) => (e['table'] as Map<String, dynamic>)['name'] as String)
          .toSet();
      expect(tracked, isNot(contains('constellation_tag_magnet')));
    });
  });
}
