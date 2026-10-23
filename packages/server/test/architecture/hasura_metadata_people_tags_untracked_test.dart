@Tags(['repo-files'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// People tags are private to their owner and only reachable through the V2
/// API: Hasura must never track any of their tables.
void main() {
  group('Hasura metadata', () {
    late Set<String> trackedTables;

    setUp(() {
      final metadataFile = File(
        '${Directory.current.path}/../../hasura/metadata.json',
      );
      final metadata =
          jsonDecode(metadataFile.readAsStringSync()) as Map<String, dynamic>;
      final sources =
          (metadata['metadata'] as Map<String, dynamic>)['sources']
              as List<dynamic>;
      final tables =
          (sources.first as Map<String, dynamic>)['tables'] as List<dynamic>;
      trackedTables = tables
          .cast<Map<String, dynamic>>()
          .map((e) => (e['table'] as Map<String, dynamic>)['name'] as String)
          .toSet();
    });

    test('does not track any people-tags table', () {
      const untracked = {
        'person_tag',
        'person_tag_member',
        'person_auto_tag_pref',
        'person_field_first_seen',
        'person_tag_suggestion_state',
        'person_tag_op_log',
        'person_tag_revision',
      };
      expect(trackedTables.intersection(untracked), isEmpty);
    });

    test('does not track any table whose name starts with person_tag', () {
      expect(
        trackedTables.where((name) => name.startsWith('person_tag')),
        isEmpty,
      );
    });
  });
}
