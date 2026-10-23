import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/constellation/domain/constellation_trust_badge.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_node_ring_layer.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import 'fixtures/constellation_reference_fixture.dart';

// #643: the viewer's trust relation on every person node.
ConstellationField _field({
  List<ConstellationPerson> peers = const [],
  List<ConstellationTrustEdgeEntity> edges = const [],
  List<String> directContactIds = const [],
  List<ConstellationRequest> requests = const [],
  ConstellationAnchorProjection? anchorProjection,
}) => ConstellationField(
  loadedAt: DateTime.utc(2026, 10, 22),
  context: '',
  peers: peers,
  edges: edges,
  directContactIds: directContactIds,
  requests: requests,
  anchorProjection: anchorProjection,
);

ConstellationTrustEdgeEntity _edge(String src, String dst, {int tier = 1}) =>
    ConstellationTrustEdgeEntity(src: src, dst: dst, tier: tier);

/// One person in each state, plus an indirect peer with no relation.
ConstellationField _everyState() => _field(
  peers: const [
    ConstellationPerson(id: 'm', displayName: 'Maria'),
    ConstellationPerson(id: 'y', displayName: 'Yuri'),
    ConstellationPerson(id: 't', displayName: 'Tanya'),
    ConstellationPerson(id: 'c', displayName: 'Clara', contactOnly: true),
    ConstellationPerson(id: 'i', displayName: 'Igor'),
  ],
  edges: [
    _edge('ego', 'm'),
    _edge('m', 'ego'),
    _edge('ego', 'y'),
    _edge('t', 'ego'),
    // The contact node's only edge: the viewer's own.
    _edge('ego', 'c'),
    _edge('m', 'i'),
  ],
  // A Request makes Tanya a holder, so the map draws her.
  requests: const [
    ConstellationRequest(id: 'req-t', authorId: 't', title: 'Help', status: 0),
  ],
  directContactIds: const ['c', 'm', 'y'],
);

void main() {
  group('constellationTrustBadges', () {
    test('mutual, one-way each way, contact node, and none', () {
      final badges = constellationTrustBadges(
        field: _everyState(),
        viewerId: 'ego',
      );
      expect(badges, {
        'm': ConstellationTrustBadge.mutual,
        'y': ConstellationTrustBadge.youTrust,
        't': ConstellationTrustBadge.theyTrust,
        'c': ConstellationTrustBadge.contactOnly,
      });
      expect(badges.containsKey('i'), isFalse);
      expect(badges.containsKey('ego'), isFalse);
    });

    test('a contact node is contactOnly even if an edge back were present', () {
      final badges = constellationTrustBadges(
        field: _field(
          peers: const [ConstellationPerson(id: 'c', contactOnly: true)],
          edges: [_edge('ego', 'c'), _edge('c', 'ego')],
        ),
        viewerId: 'ego',
      );
      expect(badges['c'], ConstellationTrustBadge.contactOnly);
    });

    test('derived tier-2 links are not a trust mark', () {
      final badges = constellationTrustBadges(
        field: _field(
          peers: const [ConstellationPerson(id: 'd')],
          edges: [_edge('ego', 'd', tier: 2), _edge('d', 'ego', tier: 2)],
        ),
        viewerId: 'ego',
      );
      expect(badges, isEmpty);
    });

    test('pinned and support-path people are read from the projection', () {
      final badges = constellationTrustBadges(
        field: _field(
          anchorProjection: ConstellationAnchorProjection(
            revision: ConstellationAnchorRevision.zero,
            anchors: const [],
            pinnedPeers: const [
              ConstellationPerson(id: 'pc', contactOnly: true),
            ],
            pinnedRequests: const [],
            supportPeers: const [ConstellationPerson(id: 's')],
            supportEdges: [_edge('s', 'ego')],
            serverFilteredBeaconIds: const [],
            serverFilteredBeaconCount: 0,
          ),
        ),
        viewerId: 'ego',
      );
      expect(badges, {
        'pc': ConstellationTrustBadge.contactOnly,
        's': ConstellationTrustBadge.theyTrust,
      });
    });

    test('is cached per field and recomputed for another viewer', () {
      final field = _everyState();
      final first = constellationTrustBadges(field: field, viewerId: 'ego');
      expect(
        identical(
          constellationTrustBadges(field: field, viewerId: 'ego'),
          first,
        ),
        isTrue,
      );
      final asMaria = constellationTrustBadges(field: field, viewerId: 'm');
      expect(asMaria['ego'], ConstellationTrustBadge.mutual);
      expect(asMaria['i'], ConstellationTrustBadge.youTrust);
    });
  });

  group('trust badge styles', () {
    test('each state differs by more than colour', () {
      final scheme = ColorScheme.fromSeed(seedColor: Colors.teal);
      final styles = {
        for (final b in ConstellationTrustBadge.values)
          b: constellationTrustBadgeStyle(b, scheme, rtl: false),
      };
      final icons = styles.values.map((s) => s.icon).toSet();
      expect(icons, hasLength(ConstellationTrustBadge.values.length));
      // Direction glyphs mirror in RTL.
      expect(
        constellationTrustBadgeStyle(
          ConstellationTrustBadge.youTrust,
          scheme,
          rtl: true,
        ).icon,
        styles[ConstellationTrustBadge.theyTrust]!.icon,
      );
    });
  });

  group('on the field', () {
    testWidgets('every person node carries its trust disc and label', (
      tester,
    ) async {
      final cubit = await loadReferenceCubit(field: _everyState());
      addTearDown(cubit.close);
      await pumpConstellationBody(
        tester,
        cubit,
        size: const Size(1200, 900),
        locale: const Locale('en'),
      );

      final painter =
          tester
                  .widget<CustomPaint>(
                    find.byKey(const ValueKey('constellation.nodeRings')),
                  )
                  .painter!
              as ConstellationNodeRingPainter;
      expect(painter.trustByGraphId.values.toSet(), {
        ConstellationTrustBadge.mutual,
        ConstellationTrustBadge.youTrust,
        ConstellationTrustBadge.theyTrust,
        ConstellationTrustBadge.contactOnly,
      });
      expect(painter.trustByGraphId, hasLength(4));

      for (final (id, name, label) in const [
        ('m', 'Maria', 'Mutual trust'),
        ('y', 'Yuri', 'You trust them'),
        ('t', 'Tanya', 'They trust you'),
        ('c', 'Clara', 'Contact without content'),
      ]) {
        final node = find.byKey(TestIds.key(TestIds.graphNode(id)));
        expect(node, findsOneWidget, reason: id);
        expect(
          tester.getSemantics(node).label,
          allOf(contains(name), contains(label)),
          reason: id,
        );
      }
      final igor = find.byKey(TestIds.key(TestIds.graphNode('i')));
      if (igor.evaluate().isNotEmpty) {
        expect(tester.getSemantics(igor).label, isNot(contains('trust')));
      }
    });
  });
}
