import 'package:test/test.dart';

import 'package:tentura_server/domain/trust/forward/forward_provenance.dart';
import 'package:tentura_server/domain/trust/forward/forward_routing_settlement.dart';
import 'package:tentura_server/domain/trust/ledger_evidence.dart';
import 'package:tentura_server/domain/trust/trust_evidence_kind.dart';

void main() {
  ForwardProvenanceEdge edge({
    required String id,
    required String sender,
    required String recipient,
    required int day,
    String? parent,
    DateTime? cancelledAt,
  }) => ForwardProvenanceEdge(
    id: id,
    senderId: sender,
    recipientId: recipient,
    createdAt: DateTime.utc(2026, 1, day),
    parentEdgeId: parent,
    batchId: 'B$id',
    cancelledAt: cancelledAt,
  );

  final offerAt = DateTime.utc(2026, 1, 10);

  List<ForwardProvenanceEdge> chain() => [
    edge(id: '1', sender: 'A', recipient: 'B', day: 1),
    edge(id: '2', sender: 'B', recipient: 'C', day: 2, parent: '1'),
  ];

  List<LedgerEvidence> route({
    required Map<String, DateTime> seeds,
    List<ForwardProvenanceEdge>? edges,
    Map<String, List<ForwardAttributionInput>> attributions = const {},
    double budget = 0.3,
  }) => ForwardRoutingSettlement().settle(
    RoutingInput(
      beaconId: 'Bx',
      epoch: 2,
      authorId: 'A',
      seedOfferAt: seeds,
      edges: edges ?? chain(),
      attributionByBatch: attributions,
      budget: budget,
    ),
  );

  Map<String, double> totalBySender(List<LedgerEvidence> out) {
    final m = <String, double>{};
    for (final e in out) {
      m[e.subjectId] = (m[e.subjectId] ?? 0) + e.count;
    }
    return m;
  }

  test('chain A->B->C with seed C: one consolidated routed row per pair', () {
    final out = route(seeds: {'C': offerAt});
    expect(out, hasLength(2));
    expect(
      out.map((e) => (e.subjectId, e.objectId)).toList()..sort(
        (x, y) => x.$1.compareTo(y.$1),
      ),
      [('A', 'B'), ('B', 'C')],
    );
    for (final e in out) {
      expect(e.kind, TrustEvidenceKind.routed);
      expect(e.beaconId, 'Bx');
      expect(e.epoch, 2);
      expect(e.sourceKey, 'closure:Bx:2:routed:${e.subjectId}:${e.objectId}');
      expect(e.count, greaterThan(0));
      expect(e.count, lessThanOrEqualTo(0.3 + 1e-9));
    }
    for (final t in totalBySender(out).values) {
      expect(t, lessThanOrEqualTo(0.3 + 1e-9));
    }
  });

  test('voluntary leaver in the request but not in seeds gets no mass', () {
    // L was offered/forwarded to (B->L, L->E) but left: not a seed.
    final edges = [
      ...chain(),
      edge(id: '3', sender: 'B', recipient: 'L', day: 3, parent: '1'),
      edge(id: '4', sender: 'L', recipient: 'E', day: 4, parent: '3'),
    ];
    final out = route(seeds: {'C': offerAt}, edges: edges);
    expect(out, isNotEmpty);
    expect(out.any((e) => e.subjectId == 'L' || e.objectId == 'L'), isFalse);
    expect(out.any((e) => e.objectId == 'E'), isFalse);
    expect(out.any((e) => e.objectId == 'C'), isTrue);
    expect(route(seeds: const {}, edges: edges), isEmpty);
  });

  test('every seed gets mass 1.0 regardless of outcome (notDone included)', () {
    // RoutingInput carries no outcome: a notDone member is a plain seed, so
    // both seeds (think: done C, notDone D) must each route.
    final edges = [
      ...chain(),
      edge(id: '3', sender: 'B', recipient: 'D', day: 3, parent: '1'),
    ];
    final out = route(seeds: {'C': offerAt, 'D': offerAt}, edges: edges);
    final toC = out.where((e) => e.subjectId == 'B' && e.objectId == 'C');
    final toD = out.where((e) => e.subjectId == 'B' && e.objectId == 'D');
    expect(toC, hasLength(1));
    expect(toD, hasLength(1));
    expect(toC.single.count, closeTo(toD.single.count, 1e-9));
    expect(totalBySender(out)['B'], lessThanOrEqualTo(0.3 + 1e-9));
  });

  test('explicit attribution is honoured by the propagator', () {
    // S received from A (edge 1) and T (edge 3); S forwarded to D (edge 4).
    final edges = [
      edge(id: '1', sender: 'A', recipient: 'S', day: 1),
      edge(id: '2', sender: 'A', recipient: 'T', day: 2),
      edge(id: '3', sender: 'T', recipient: 'S', day: 3, parent: '2'),
      edge(id: '4', sender: 'S', recipient: 'D', day: 4, parent: '1'),
    ];
    final plain = route(seeds: {'D': offerAt}, edges: edges);
    expect(plain.any((e) => e.subjectId == 'T'), isTrue);

    final attributed = route(
      seeds: {'D': offerAt},
      edges: edges,
      attributions: {
        'B4': [
          const ForwardAttributionInput(
            batchId: 'B4',
            parentForwardEdgeId: '1',
            weight: 1,
          ),
        ],
      },
    );
    expect(attributed.any((e) => e.subjectId == 'A' && e.objectId == 'S'),
        isTrue);
    expect(attributed.any((e) => e.subjectId == 'T'), isFalse);
  });

  test('edge created after the offer gives no credit', () {
    final edges = [
      edge(id: '1', sender: 'A', recipient: 'B', day: 1),
      edge(id: '2', sender: 'B', recipient: 'C', day: 12, parent: '1'),
    ];
    expect(route(seeds: {'C': offerAt}, edges: edges), isEmpty);
  });

  test('edge cancelled before the offer gives no credit', () {
    final edges = [
      edge(id: '1', sender: 'A', recipient: 'B', day: 1),
      edge(
        id: '2',
        sender: 'B',
        recipient: 'C',
        day: 2,
        parent: '1',
        cancelledAt: DateTime.utc(2026, 1, 5),
      ),
    ];
    expect(route(seeds: {'C': offerAt}, edges: edges), isEmpty);
  });

  test('self pairs and non-positive counts are dropped', () {
    expect(route(seeds: {'C': offerAt}, budget: 0), isEmpty);
    expect(route(seeds: {'C': offerAt}, budget: -1), isEmpty);
    for (final e in route(seeds: {'C': offerAt})) {
      expect(e.subjectId, isNot(e.objectId));
      expect(e.count, greaterThan(0));
    }
  });
}
