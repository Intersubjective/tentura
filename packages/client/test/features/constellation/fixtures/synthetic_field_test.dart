import 'package:flutter_test/flutter_test.dart';

import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import 'synthetic_field.dart';

void main() {
  group('synthetic constellation field generator', () {
    for (final size in const [100, 300, 600]) {
      test('yields $size people and $size requests', () {
        final field = syntheticConstellationField(size: size);

        expect(field.peers, hasLength(size));
        expect(field.requests, hasLength(size));
      });
    }

    test('is deterministic for a fixed seed', () {
      for (final size in const [100, 300, 600]) {
        final first = syntheticConstellationField(size: size, seed: 7);
        final second = syntheticConstellationField(size: size, seed: 7);

        expect(second, equals(first), reason: 'size $size');
      }
    });

    test('default seed is fixed, so repeated default calls are identical', () {
      expect(
        syntheticConstellationField(size: 100),
        equals(syntheticConstellationField(size: 100)),
      );
    });

    test('different seeds produce different fields', () {
      final a = syntheticConstellationField(size: 100, seed: 1);
      final b = syntheticConstellationField(size: 100, seed: 2);

      expect(b, isNot(equals(a)));
    });

    test('person and request ids are unique and do not collide', () {
      final field = syntheticConstellationField(size: 300);
      final ids = [
        for (final p in field.peers) p.id,
        for (final r in field.requests) r.id,
      ];

      expect(ids.toSet(), hasLength(ids.length));
    });

    test('every request is authored by a person on the field', () {
      final field = syntheticConstellationField(size: 300);
      final authors = {for (final p in field.peers) p.id};

      for (final request in field.requests) {
        expect(authors, contains(request.authorId), reason: request.id);
      }
    });

    test('trust edges only connect the viewer and people on the field', () {
      final field = syntheticConstellationField(size: 300);
      final known = {'ego', for (final p in field.peers) p.id};

      expect(field.edges, isNotEmpty);
      for (final edge in field.edges) {
        expect(known, contains(edge.src));
        expect(known, contains(edge.dst));
      }
    });

    test('carries valid anchors that point at generated people and requests',
        () {
      for (final size in const [100, 300, 600]) {
        final field = syntheticConstellationField(size: size);
        final projection = field.anchorProjection;

        expect(projection, isNotNull, reason: 'size $size');
        expect(projection!.anchors, isNotEmpty, reason: 'size $size');

        final peerIds = {for (final p in field.peers) p.id};
        final requestIds = {for (final r in field.requests) r.id};
        final targetIds = <String>{};
        for (final anchor in projection.anchors) {
          expect(
            ConstellationAnchorPosition.validate(
              xUnits: anchor.position.xUnits,
              yUnits: anchor.position.yUnits,
              coordinateSpaceVersion: anchor.position.coordinateSpaceVersion,
            ),
            isA<ConstellationAnchorPositionValid>(),
          );
          final id = anchor.target.graphNodeId;
          expect(
            peerIds.contains(id) || requestIds.contains(id),
            isTrue,
            reason: 'anchor target $id is not a generated node',
          );
          expect(targetIds.add(id), isTrue, reason: 'duplicate anchor $id');
        }
      }
    });

    test('anchors cover both people and requests', () {
      final field = syntheticConstellationField(size: 300);
      final peerIds = {for (final p in field.peers) p.id};
      final targets = [
        for (final a in field.anchorProjection!.anchors) a.target.graphNodeId,
      ];

      expect(targets.any(peerIds.contains), isTrue);
      expect(targets.any((id) => !peerIds.contains(id)), isTrue);
    });
  });
}
