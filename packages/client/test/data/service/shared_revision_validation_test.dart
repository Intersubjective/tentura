@Tags(['repo-files'])
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/data/service/invalidation_service.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';

import '../../../../../test/support/shared_revision_pattern_guard.dart';

void main() {
  test(
    'incoming revision hints preserve decimal precision using the shared pattern',
    () async {
      const revisions = <Object?>[
        '0',
        '007',
        '9007199254740993',
        '',
        '12abc',
        '-1',
        '+1',
        '1.5',
        ' 7',
        42,
        true,
        null,
      ];
      for (final entity in ['constellation_anchor', 'person_tag']) {
        for (final revision in revisions) {
          final messages = StreamController<Map<String, dynamic>>.broadcast();
          final service = InvalidationService.forTesting(messages.stream);
          final received = service.entityChanges.toList();
          messages.add({
            'type': 'subscription',
            'path': 'entity_changes',
            'payload': {
              'entity': entity,
              'id': 'Uviewer000001',
              'event': 'update',
              'revision': revision,
            },
          });
          await messages.close();
          await service.dispose();
          final events = await received.timeout(const Duration(seconds: 5));
          expect(events, hasLength(1), reason: '$entity revision $revision');
          expect(events.single.kind, RealtimeEntityKind.fromWire(entity));
          expect(events.single.aggregateId, 'Uviewer000001');
          expect(
            events.single.revision,
            revision is String &&
                    const ['0', '007', '9007199254740993'].contains(revision)
                ? BigInt.parse(revision)
                : null,
            reason: '$entity revision $revision',
          );
        }
      }
      // Consolidation must preserve the wire behavior above and remove the local
      // regexp. Both clauses belong to this refactor's acceptance contract.
      expect(
        decimalRevisionValidationViolations(
          File('lib/data/service/invalidation_service.dart').readAsStringSync(),
        ),
        isEmpty,
      );
    },
  );
}
