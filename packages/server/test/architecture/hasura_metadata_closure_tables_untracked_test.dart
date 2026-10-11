import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// Server-only tables (closure, post-bud observers and author invites):
/// Hasura must never track them.
void main() {
  group('Hasura metadata', () {
    late List<Map<String, dynamic>> tableEntries;

    setUp(() {
      final metadataFile = File(
        '${Directory.current.path}/../../hasura/metadata.json',
      );
      final metadata =
          jsonDecode(metadataFile.readAsStringSync()) as Map<String, dynamic>;
      final tables =
          (metadata['metadata'] as Map<String, dynamic>)['sources'][0]['tables']
              as List<dynamic>;
      tableEntries = tables.cast<Map<String, dynamic>>();
    });

    test('does not track any beacon_closure* table', () {
      final closureTracked = tableEntries.where((entry) {
        final name = (entry['table'] as Map<String, dynamic>)['name'] as String;
        return name.startsWith('beacon_closure');
      });
      expect(closureTracked, isEmpty);
    });

    test('does not track the post-bud tables', () {
      const untracked = {'beacon_bud_observer', 'beacon_author_invite'};
      final tracked = tableEntries.where((entry) {
        final name = (entry['table'] as Map<String, dynamic>)['name'] as String;
        return untracked.contains(name);
      });
      expect(tracked, isEmpty);
    });
  });
}
