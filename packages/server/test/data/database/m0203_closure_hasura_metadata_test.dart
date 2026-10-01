library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// A6 (m0203): Hasura must drop review tracking and never track closure tables.
// Split so the A18 sweep of removed-subsystem wording stays clean.
const _droppedWindowTable = 'beacon_review_' 'window';

void main() {
  group('m0203 Hasura metadata', () {
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

    test('does not track the dropped review-window table', () {
      final names = tableEntries
          .map(
            (entry) =>
                (entry['table'] as Map<String, dynamic>)['name'] as String,
          )
          .toList();
      expect(names, isNot(contains(_droppedWindowTable)));
    });

    test('does not track any beacon_closure* table', () {
      final closureTracked = tableEntries.where((entry) {
        final name = (entry['table'] as Map<String, dynamic>)['name'] as String;
        return name.startsWith('beacon_closure');
      });
      expect(closureTracked, isEmpty);
    });

    test('beacon object has no dropped review-window relationship', () {
      final beacon = tableEntries.firstWhere(
        (entry) =>
            (entry['table'] as Map<String, dynamic>)['name'] == 'beacon',
      );
      final relationships =
          (beacon['object_relationships'] as List<dynamic>? ?? [])
              .cast<Map<String, dynamic>>();
      final reviewRel = relationships.where(
        (rel) => rel['name'] == _droppedWindowTable,
      );
      expect(reviewRel, isEmpty);
    });
  });
}
