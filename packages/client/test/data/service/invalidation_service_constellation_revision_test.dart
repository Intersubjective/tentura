// Realtime decode for the constellation hints: the `constellation_field` kind,
// and the commit `revision` extra on `constellation_anchor` frames. A valid
// decimal revision is kept as a BigInt; a malformed one is ignored without
// losing the invalidation itself.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/data/service/invalidation_service.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';

Map<String, dynamic> _frame({
  required String entity,
  String id = 'Uviewer000001',
  Object? revision,
  bool omitRevision = false,
}) => {
  'type': 'subscription',
  'path': 'entity_changes',
  'payload': {
    'entity': entity,
    'id': id,
    'event': 'update',
    if (!omitRevision) 'revision': revision,
  },
};

Future<List<RealtimeEntityChange>> _deliver(
  List<Map<String, dynamic>> frames,
) async {
  final wsMessages = StreamController<Map<String, dynamic>>.broadcast();
  final service = InvalidationService.forTesting(wsMessages.stream);
  final received = service.entityChanges.toList();

  frames.forEach(wsMessages.add);
  await wsMessages.close();
  // Closing the service flushes pending batches and completes the event stream.
  await service.dispose();
  return received;
}

void main() {
  group('constellation_field realtime kind', () {
    test('constellation_field is a known wire kind', () {
      expect(
        RealtimeEntityKind.fromWire('constellation_field'),
        RealtimeEntityKind.constellationField,
      );
    });

    test(
      'a payload-free global hint is delivered without a revision',
      () async {
        final received = await _deliver([
          _frame(
            entity: 'constellation_field',
            id: 'global',
            omitRevision: true,
          ),
        ]);

        expect(received, hasLength(1));
        expect(received.single.kind, RealtimeEntityKind.constellationField);
        expect(received.single.aggregateId, 'global');
        expect(received.single.revision, isNull);
      },
    );
  });

  group('constellation_anchor revision extra', () {
    test('a valid decimal revision is kept at full BigInt precision', () async {
      final received = await _deliver([
        _frame(entity: 'constellation_anchor', revision: '9007199254740993'),
      ]);

      expect(received, hasLength(1));
      expect(received.single.kind, RealtimeEntityKind.constellationAnchor);
      expect(received.single.revision, BigInt.parse('9007199254740993'));
    });

    test('zero is a valid revision', () async {
      final received = await _deliver([
        _frame(entity: 'constellation_anchor', revision: '0'),
      ]);

      expect(received.single.revision, BigInt.zero);
    });

    for (final malformed in <Object?>[
      '12abc',
      '-1',
      '',
      '1.5',
      ' 7',
      42,
      true,
      null,
    ]) {
      test('a malformed revision ($malformed) is ignored while the hint '
          'is still delivered', () async {
        final received = await _deliver([
          _frame(entity: 'constellation_anchor', revision: malformed),
        ]);

        expect(received, hasLength(1));
        expect(received.single.kind, RealtimeEntityKind.constellationAnchor);
        expect(received.single.aggregateId, 'Uviewer000001');
        expect(received.single.revision, isNull);
      });
    }

    test(
      'a frame without a revision key is delivered with a null revision',
      () async {
        final received = await _deliver([
          _frame(entity: 'constellation_anchor', omitRevision: true),
        ]);

        expect(received, hasLength(1));
        expect(received.single.revision, isNull);
      },
    );
  });

  group('revision extra on other kinds', () {
    test('an unrelated kind never carries a revision', () async {
      final received = await _deliver([
        _frame(entity: 'beacon', id: 'Bbeacon000001', revision: '7'),
      ]);

      expect(received, hasLength(1));
      expect(received.single.kind, RealtimeEntityKind.beacon);
      expect(received.single.revision, isNull);
    });
  });
}
