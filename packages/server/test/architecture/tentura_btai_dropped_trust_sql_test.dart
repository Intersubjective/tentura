// tentura-btai: production code must not call SQL objects m0202 dropped.

import 'dart:io';

import 'package:test/test.dart';

/// m0202 (steps 11) drops `trust_rebuild_effective_edge(text,text,double
/// precision)` and the `user_trust_source_edge` table. Historical migrations
/// (m0193, m0201) legitimately mention them; everything else under `lib/`
/// runs against the migrated schema and must not.
const _droppedObjects = [
  'trust_rebuild_effective_edge',
  'user_trust_source_edge',
];

const _migrationDir = 'lib/data/database/migration/';

void main() {
  group('tentura-btai: no references to objects dropped by m0202', () {
    test('m0202 still drops both objects (premise of this guard)', () {
      final migration = File(
        'lib/data/database/migration/m0202.dart',
      ).readAsStringSync();
      expect(
        migration,
        contains(
          'DROP FUNCTION IF EXISTS public.trust_rebuild_effective_edge('
          'text, text, double precision)',
        ),
      );
      expect(
        migration,
        contains('DROP TABLE IF EXISTS public.user_trust_source_edge'),
      );
    });

    for (final object in _droppedObjects) {
      test('lib/ outside migrations does not reference $object', () {
        final offenders = <String>[];
        for (final entity in Directory('lib').listSync(recursive: true)) {
          if (entity is! File || !entity.path.endsWith('.dart')) continue;
          if (entity.path.contains(_migrationDir)) continue;
          final lines = entity.readAsLinesSync();
          for (var i = 0; i < lines.length; i++) {
            if (lines[i].contains(object)) {
              offenders.add('${entity.path}:${i + 1}');
            }
          }
        }
        expect(
          offenders,
          isEmpty,
          reason:
              '$object was dropped by m0202; these call sites fail at '
              'runtime on a migrated DB',
        );
      });
    }

    test('TrustEvidenceRepository.record does not call the dropped rebuild RPC',
        () {
      final source = File(
        'lib/data/repository/trust_evidence_repository.dart',
      ).readAsStringSync();
      expect(
        source,
        isNot(contains(r'SELECT trust_rebuild_effective_edge($1, $2)')),
      );
    });

    test('cutoverBackfillIfNeeded does not count user_trust_source_edge', () {
      final source = File(
        'lib/data/repository/user_trust_edge_repository.dart',
      ).readAsStringSync();
      expect(
        source,
        isNot(
          contains(
            'SELECT count(*)::int AS c FROM user_trust_source_edge',
          ),
        ),
      );
    });
  });
}
