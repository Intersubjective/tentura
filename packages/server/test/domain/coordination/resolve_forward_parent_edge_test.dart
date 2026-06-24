import 'package:test/test.dart';

import 'package:tentura_server/domain/coordination/resolve_forward_parent_edge.dart';
import 'package:tentura_server/domain/entity/forward_edge_entity.dart';
import 'package:tentura_server/domain/exception.dart';

ForwardEdgeEntity _edge({
  required String id,
  required String senderId,
  required String recipientId,
  String? parentEdgeId,
  DateTime? createdAt,
}) =>
    ForwardEdgeEntity(
      id: id,
      beaconId: 'B1',
      senderId: senderId,
      recipientId: recipientId,
      note: '',
      parentEdgeId: parentEdgeId,
      createdAt: createdAt ?? DateTime.utc(2026, 1, 1),
    );

void main() {
  group('resolveForwardParentEdgeId', () {
    test('returns null when sender has no inbound edges', () {
      expect(
        resolveForwardParentEdgeId(
          clientParentEdgeId: null,
          activeInboundEdges: const [],
          senderId: 'Usender',
          authorId: 'Uauthor',
        ),
        isNull,
      );
    });

    test('prefers direct author inbound edge', () {
      final edges = [
        _edge(id: 'Ehop', senderId: 'Uhop', recipientId: 'Usender'),
        _edge(id: 'Eauthor', senderId: 'Uauthor', recipientId: 'Usender'),
      ];
      expect(
        resolveForwardParentEdgeId(
          clientParentEdgeId: null,
          activeInboundEdges: edges,
          senderId: 'Usender',
          authorId: 'Uauthor',
        ),
        'Eauthor',
      );
    });

    test('uses most recent inbound edge when no author hop', () {
      final edges = [
        _edge(
          id: 'Enew',
          senderId: 'Uhop2',
          recipientId: 'Usender',
          createdAt: DateTime.utc(2026, 2, 1),
        ),
        _edge(
          id: 'Eold',
          senderId: 'Uhop1',
          recipientId: 'Usender',
          createdAt: DateTime.utc(2026, 1, 1),
        ),
      ];
      expect(
        resolveForwardParentEdgeId(
          clientParentEdgeId: null,
          activeInboundEdges: edges,
          senderId: 'Usender',
          authorId: 'Uauthor',
        ),
        'Enew',
      );
    });

    test('validates client parent edge belongs to sender', () {
      final edges = [
        _edge(id: 'E1', senderId: 'Uauthor', recipientId: 'Usender'),
      ];
      expect(
        resolveForwardParentEdgeId(
          clientParentEdgeId: 'E1',
          activeInboundEdges: edges,
          senderId: 'Usender',
          authorId: 'Uauthor',
        ),
        'E1',
      );
    });

    test('rejects invalid client parent edge', () {
      expect(
        () => resolveForwardParentEdgeId(
          clientParentEdgeId: 'Enope',
          activeInboundEdges: [
            _edge(id: 'E1', senderId: 'Uauthor', recipientId: 'Uother'),
          ],
          senderId: 'Usender',
          authorId: 'Uauthor',
        ),
        throwsA(isA<UnauthorizedException>()),
      );
    });
  });
}
