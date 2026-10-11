import 'package:test/test.dart';

import 'package:tentura_server/domain/trust/forward/forward_causal_graph_builder.dart';
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
    String authorId = 'A',
    Map<String, List<ForwardRoutingSegment>> extraSegments = const {},
    Set<String> deliveryEdgeIds = const {},
  }) => ForwardRoutingSettlement().settle(
    RoutingInput(
      beaconId: 'Bx',
      epoch: 2,
      authorId: authorId,
      seedOfferAt: seeds,
      edges: edges ?? chain(),
      attributionByBatch: attributions,
      budget: budget,
      extraSegments: extraSegments,
      deliveryEdgeIds: deliveryEdgeIds,
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
    expect(
      attributed.any((e) => e.subjectId == 'A' && e.objectId == 'S'),
      isTrue,
    );
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

  group('Post segments (budding C7)', () {
    // The Post: A→B (p1), B→C (p2), all before the child's published_at.
    final publishedAt = DateTime.utc(2026, 1, 5);
    List<ForwardProvenanceEdge> postChain() => [
      edge(id: 'p1', sender: 'A', recipient: 'B', day: 1),
      edge(id: 'p2', sender: 'B', recipient: 'C', day: 2, parent: 'p1'),
    ];
    ForwardRoutingSegment segment(
      List<ForwardProvenanceEdge> edges, {
      String root = 'A',
    }) => ForwardRoutingSegment(
      edges: edges,
      attributionByBatch: const {},
      rootSenderId: root,
      cutoffAt: publishedAt,
    );
    // The child: the delivery edge child author → C (d1).
    ForwardProvenanceEdge delivery({String sender = 'A'}) =>
        edge(id: 'd1', sender: sender, recipient: 'C', day: 6);

    Set<(String, String)> pairs(List<LedgerEvidence> out) => {
      for (final e in out) (e.subjectId, e.objectId),
    };

    test('an invitee credits only the Post chain; the delivery earns '
        'nothing', () {
      final out = route(
        seeds: {'C': offerAt},
        edges: [delivery()],
        extraSegments: {
          'C': [segment(postChain())],
        },
        deliveryEdgeIds: {'d1'},
      );
      expect(pairs(out), {('A', 'B'), ('B', 'C')});
    });

    test('without the delivery set the delivery edge routes as today', () {
      final out = route(
        seeds: {'C': offerAt},
        edges: [delivery()],
        extraSegments: {
          'C': [segment(postChain())],
        },
      );
      expect(pairs(out), {('A', 'B'), ('B', 'C'), ('A', 'C')});
    });

    test('a Post path rooted elsewhere earns nothing', () {
      final out = route(
        seeds: {'C': offerAt},
        edges: [delivery()],
        extraSegments: {
          'C': [
            segment([edge(id: 'p3', sender: 'D', recipient: 'C', day: 3)]),
          ],
        },
        deliveryEdgeIds: {'d1'},
      );
      expect(out, isEmpty);
    });

    test('a cancelled Post edge drops the segment', () {
      final out = route(
        seeds: {'C': offerAt},
        edges: [delivery()],
        extraSegments: {
          'C': [
            segment([
              postChain().first,
              edge(
                id: 'p2',
                sender: 'B',
                recipient: 'C',
                day: 2,
                parent: 'p1',
                cancelledAt: DateTime.utc(2026, 1, 3),
              ),
            ]),
          ],
        },
        deliveryEdgeIds: {'d1'},
      );
      expect(out, isEmpty);
    });

    test('onward forwards from the invitee route through the delivery '
        'root', () {
      final edges = [
        delivery(),
        edge(id: '7', sender: 'C', recipient: 'E', day: 7, parent: 'd1'),
      ];
      final onwardOnly = route(
        seeds: {'E': offerAt},
        edges: edges,
        extraSegments: {
          'C': [segment(postChain())],
        },
        deliveryEdgeIds: {'d1'},
      );
      expect(pairs(onwardOnly), {('C', 'E')});

      final both = route(
        seeds: {'C': offerAt, 'E': offerAt},
        edges: edges,
        extraSegments: {
          'C': [segment(postChain())],
        },
        deliveryEdgeIds: {'d1'},
      );
      expect(pairs(both), {('A', 'B'), ('B', 'C'), ('C', 'E')});
    });

    test('a budder in the Post chain earns nothing for the delivery', () {
      final out = route(
        authorId: 'B',
        seeds: {'C': offerAt},
        edges: [delivery(sender: 'B')],
        extraSegments: {
          'C': [segment(postChain())],
        },
        deliveryEdgeIds: {'d1'},
      );
      expect(pairs(out), {('A', 'B'), ('B', 'C')});
      final viaPost = out.singleWhere((e) => e.subjectId == 'B');
      expect(viaPost.sourceKey, 'closure:Bx:2:routed:B:C');
    });

    test('a segment does not pull child edges into the Post chain', () {
      // The child author A also forwarded to B on the child; B never
      // forwarded the child to C, so A→B on the child is not on C's path.
      final out = route(
        seeds: {'C': offerAt},
        edges: [
          edge(id: '8', sender: 'A', recipient: 'B', day: 6),
          delivery(),
        ],
        extraSegments: {
          'C': [
            segment([
              edge(id: 'p1', sender: 'P', recipient: 'B', day: 1),
              edge(id: 'p2', sender: 'B', recipient: 'C', day: 2, parent: 'p1'),
            ], root: 'P'),
          ],
        },
        deliveryEdgeIds: {'d1'},
      );
      expect(pairs(out), {('P', 'B'), ('B', 'C')});
    });

    test('the Post segment shares the per-sender rho*B budget', () {
      // B forwarded the child to D (seed D) and, in the Post, to C (seed C).
      final childEdges = [
        edge(id: '1', sender: 'A', recipient: 'B', day: 6),
        edge(id: '2', sender: 'B', recipient: 'D', day: 7, parent: '1'),
        delivery(),
      ];
      final without = route(
        seeds: {'C': offerAt, 'D': offerAt},
        edges: childEdges,
        deliveryEdgeIds: {'d1'},
      );
      final withSegment = route(
        seeds: {'C': offerAt, 'D': offerAt},
        edges: childEdges,
        extraSegments: {
          'C': [segment(postChain())],
        },
        deliveryEdgeIds: {'d1'},
      );
      expect(pairs(withSegment), containsAll([('B', 'C'), ('B', 'D')]));
      expect(totalBySender(without)['B'], closeTo(0.3, 1e-9));
      expect(totalBySender(withSegment)['B'], closeTo(0.3, 1e-9));
      expect(totalBySender(withSegment)['A'], closeTo(0.3, 1e-9));
    });
  });
}
