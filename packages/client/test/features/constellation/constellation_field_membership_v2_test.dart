import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/features/constellation/domain/constellation_anchor_composition.dart';
import 'package:tentura/features/constellation/domain/constellation_cap_policy.dart';
import 'package:tentura/features/constellation/domain/constellation_field_patches.dart';
import 'package:tentura/features/constellation/domain/constellation_consts.dart';
import 'package:tentura/features/constellation/domain/constellation_filters.dart';
import 'package:tentura/features/constellation/domain/constellation_layout.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura_root/domain/constellation/constellation_path_resolution.dart';

const _ego = 'ego';

ConstellationEdgeRef _ref(String dst, int tier) =>
    (src: _ego, dst: dst, tier: tier);

String _id(String prefix, int i) => '$prefix${i.toString().padLeft(3, '0')}';

ConstellationComposedPresentation _compose(
  ConstellationField field, {
  required bool gate,
}) => composeConstellationPresentation(
  viewerId: _ego,
  field: field,
  localFilters: const (
    capabilitySlugs: {},
    location: LocationFilter.any,
    timing: TimingFilterAny(),
    includeUnspecified: true,
  ),
  asOfUtc: DateTime.utc(2026, 10, 24),
  labelBudget: (perPerson: 3, total: 150),
  fieldMembershipV2Enabled: gate,
);

void main() {
  test('field membership ships enabled for phase 1', () {
    expect(kFieldMembershipV2Enabled, isTrue);
  });

  group('ConstellationPerson field tag data', () {
    test('defaults carry no membership detail', () {
      const person = ConstellationPerson(id: 'p');
      expect(person.fieldMembership, ConstellationFieldMembership.visible);
      expect(person.ownTagIds, isEmpty);
      expect(person.autoTagKinds, isEmpty);
      expect(person.firstSeenAt, isNull);
      expect(person.temporaryBeaconId, isNull);
      expect(person.bondContexts, isEmpty);
    });

    test('keeps the contexts a bond peer works with the viewer on', () {
      const person = ConstellationPerson(
        id: 'p',
        fieldMembership: ConstellationFieldMembership.bond,
        bondContexts: [
          ConstellationBondContext(beaconId: 'B7', title: 'Fix the roof'),
        ],
      );
      expect(person.bondContexts.single.beaconId, 'B7');
      expect(person.bondContexts.single.title, 'Fix the roof');
    });

    test('keeps temporary-person detail', () {
      final person = ConstellationPerson(
        id: 'p',
        fieldMembership: ConstellationFieldMembership.temporary,
        temporaryBeaconId: 'B1',
        ownTagIds: const ['t1'],
        firstSeenAt: DateTime.utc(2026, 10),
      );
      expect(person.fieldMembership, ConstellationFieldMembership.temporary);
      expect(person.temporaryBeaconId, 'B1');
      expect(person.ownTagIds, ['t1']);
      expect(person.firstSeenAt, DateTime.utc(2026, 10));
    });
  });

  group('field membership without Requests', () {
    ConstellationField field(ConstellationFieldMembership membership) =>
        ConstellationField(
          loadedAt: DateTime.utc(2026, 10, 24),
          context: '',
          peers: [ConstellationPerson(id: 'v', fieldMembership: membership)],
          edges: const [
            ConstellationTrustEdgeEntity(src: _ego, dst: 'v', tier: 1),
          ],
        );

    for (final membership in [
      ConstellationFieldMembership.visible,
      ConstellationFieldMembership.bond,
      ConstellationFieldMembership.temporary,
    ]) {
      test('gate on: a ${membership.name} person with no Requests is kept '
          'and has a path', () {
        final composed = _compose(field(membership), gate: true);
        expect(composed.keptPeerIds, contains('v'));
        expect(composed.paths.attributed, contains('v'));
        expect(composed.eligiblePersonIds, contains('v'));
      });

      test('gate off: a ${membership.name} person with no Requests is not '
          'kept', () {
        final composed = _compose(field(membership), gate: false);
        expect(composed.keptPeerIds, isNot(contains('v')));
      });
    }

    test('gate on: a contact-only node alone does not become a holder', () {
      final composed = _compose(
        field(ConstellationFieldMembership.contactOnly),
        gate: true,
      );
      expect(composed.paths.attributed, isNot(contains('v')));
    });
  });

  group('cap policy with the gate off keeps the id-ordered rule', () {
    test('two-node chain with budget 1 keeps nothing and drops the holder', () {
      final result = resolveAndCapConstellation(
        egoId: _ego,
        visiblePeerIds: const {'a', 'h'},
        holderIds: const {'h'},
        edges: const [
          (src: _ego, dst: 'a', tier: 1),
          (src: 'a', dst: 'h', tier: 1),
        ],
        cap: 1,
      );
      expect(result.keptPeerIds, isEmpty);
      expect(result.droppedHolderIds, {'h'});
      expect(result.capped, isTrue);
    });
  });

  group('pinned and contact exemptions in the composed field', () {
    test('gate on: pinned and contact peers do not use the cap, own-tagged '
        'peers come first, then lowest ids', () {
      final pinned = [for (var i = 0; i < 5; i++) _id('p', i)];
      final contacts = [for (var i = 0; i < 10; i++) _id('c', i)];
      final tagged = [for (var i = 0; i < 20; i++) _id('z', i)];
      final others = [for (var i = 0; i < 270; i++) _id('a', i)];
      final everyone = [...pinned, ...contacts, ...tagged, ...others];
      final field = ConstellationField(
        loadedAt: DateTime.utc(2026, 10, 24),
        context: '',
        peers: [
          for (final id in everyone)
            ConstellationPerson(
              id: id,
              ownTagIds: tagged.contains(id) ? const ['t1'] : const [],
            ),
        ],
        edges: [
          for (final id in everyone)
            ConstellationTrustEdgeEntity(src: _ego, dst: id, tier: 1),
        ],
        requests: [
          for (final id in everyone)
            ConstellationRequest(
              id: 'R$id',
              authorId: id,
              title: 'Request $id',
              status: 0,
            ),
        ],
        directContactIds: contacts,
        anchorProjection: ConstellationAnchorProjection(
          revision: ConstellationAnchorRevision.zero,
          anchors: const [],
          pinnedPeers: [for (final id in pinned) ConstellationPerson(id: id)],
          pinnedRequests: const [],
          supportPeers: const [],
          supportEdges: const [],
          serverFilteredBeaconIds: const [],
          serverFilteredBeaconCount: 0,
        ),
      );
      final kept = _compose(field, gate: true).keptPeerIds;
      final exempt = {...pinned, ...contacts};
      expect(kept, containsAll(exempt));
      expect(kept.difference(exempt), {
        ...tagged,
        ...others.take(constellationRenderPeerCap() - tagged.length),
      });
    });
  });

  group('cap priority', () {
    // 300 charged candidates (plus 5 exempt) compete for a budget of 120.
    final exempt = {for (var i = 0; i < 5; i++) _id('e', i)};
    final ownTagged = {for (var i = 0; i < 20; i++) _id('z', i)};
    final direct = {for (var i = 0; i < 40; i++) _id('y', i)};
    final bondOrTemporary = {for (var i = 0; i < 10; i++) _id('x', i)};
    // Depth 1, ids sorting after the deeper ones.
    final shallow = [for (var i = 0; i < 30; i++) _id('q', i)];
    // Depth 2 behind one shared non-holder parent, ids sorting first.
    const parent = 'pp';
    final deep = [for (var i = 0; i < 200; i++) _id('a', i)];

    ConstellationResolvedField run({required bool gate}) {
      final holders = {
        ...exempt,
        ...ownTagged,
        ...direct,
        ...bondOrTemporary,
        ...shallow,
        ...deep,
      };
      return resolveAndCapConstellation(
        egoId: _ego,
        visiblePeerIds: {...holders, parent},
        holderIds: holders,
        edges: [
          for (final id in {
            ...exempt,
            ...ownTagged,
            ...direct,
            ...bondOrTemporary,
            ...shallow,
            parent,
          })
            _ref(id, 1),
          for (final id in deep) (src: parent, dst: id, tier: 1),
        ],
        cap: 120,
        budgetExemptPeerIds: exempt,
        fieldMembershipV2Enabled: gate,
        ownTaggedPeerIds: ownTagged,
        directContactPeerIds: direct,
        bondOrTemporaryPeerIds: bondOrTemporary,
      );
    }

    test('gate on: exempt peers are free, then own-tagged, direct, '
        'bond/temporary, shallower depth, then id order', () {
      final kept = run(gate: true).keptPeerIds;
      expect(
        kept,
        {
          ...exempt,
          ...ownTagged,
          ...direct,
          ...bondOrTemporary,
          ...shallow,
          // 20 left: the shared parent, then the first 19 deep ids.
          parent,
          ...deep.take(19),
        },
      );
      expect(kept.difference(exempt).length, 120);
    });

    test('gate off: selection stays id order', () {
      final kept = run(gate: false).keptPeerIds;
      expect(kept, isNot(contains('z000')));
      expect(kept, contains('a000'));
    });
  });

  group('node positions stay put when a field-membership person joins', () {
    ConstellationField field({
      ConstellationFieldMembership? newcomer,
      Set<String> without = const {},
    }) => ConstellationField(
      loadedAt: DateTime.utc(2026, 10, 24),
      context: '',
      peers: [
        for (var i = 0; i < 6; i++)
          if (!without.contains(_id('m', i)))
            ConstellationPerson(id: _id('m', i)),
        if (newcomer != null)
          ConstellationPerson(id: 'a-newcomer', fieldMembership: newcomer),
      ],
      edges: [
        for (var i = 0; i < 6; i++)
          if (!without.contains(_id('m', i)))
            ConstellationTrustEdgeEntity(
              src: _ego,
              dst: _id('m', i),
              tier: 1,
            ),
        if (newcomer != null)
          const ConstellationTrustEdgeEntity(
            src: _ego,
            dst: 'a-newcomer',
            tier: 1,
          ),
      ],
      requests: [
        for (var i = 0; i < 6; i++)
          if (!without.contains(_id('m', i)))
            ConstellationRequest(
              id: _id('r', i),
              authorId: _id('m', i),
              title: 'Request $i',
              status: 0,
            ),
      ],
    );

    ConstellationLayout place(
      ConstellationField f, {
      required bool gate,
      ConstellationLayoutPriorHints? previous,
    }) {
      final composed = _compose(f, gate: gate);
      return computeConstellationPlacedLayout(
        input: (
          egoId: _ego,
          paths: composed.paths,
          automaticKeptPeerIds: composed.keptPeerIds,
          pinnedPersonIds: const {},
          pinnedRequestIds: const {},
          supportPersonIds: const {},
          anchorByNodeId: const {},
          priorHints: previous,
          nodeSizes: {
            for (final id in composed.keptPeerIds)
              id: (width: 40.0, height: 40.0),
            for (final r in f.requests) r.id: (width: 36.0, height: 36.0),
          },
          satelliteRequestIdsByAuthor: {
            for (final r in f.requests) r.authorId: [r.id],
          },
          requestAuthorById: {for (final r in f.requests) r.id: r.authorId},
          egoOwnRequestIds: const {},
          spacing: 16,
          maxHops: 3,
          viewportClass: ConstellationViewportClass.expanded,
          footprints: const {},
        ),
      );
    }

    final scenarios = <String, (ConstellationField, ConstellationField)>{
      'a visible person with no Requests joins': (
        field(),
        field(newcomer: ConstellationFieldMembership.visible),
      ),
      'a bond person with no Requests joins': (
        field(),
        field(newcomer: ConstellationFieldMembership.bond),
      ),
      'a temporary person with no Requests joins': (
        field(),
        field(newcomer: ConstellationFieldMembership.temporary),
      ),
      'a person leaves': (
        field(newcomer: ConstellationFieldMembership.visible),
        field(),
      ),
      'an author of Requests leaves': (
        field(),
        field(without: {_id('m', 2)}),
      ),
    };

    for (final gate in [false, true]) {
      for (final entry in scenarios.entries) {
        test('gate ${gate ? 'on' : 'off'}: existing nodes do not move when '
            '${entry.key}', () {
          final (beforeField, afterField) = entry.value;
          final before = place(beforeField, gate: gate);
          final after = place(
            afterField,
            gate: gate,
            previous: (
              positions: before.positions,
              ring: before.ring,
              viewportClass: ConstellationViewportClass.expanded,
            ),
          );
          final survivors = {
            for (final p in afterField.peers) p.id,
            for (final r in afterField.requests) r.id,
          };
          for (final node in before.positions.entries) {
            if (!survivors.contains(node.key)) continue;
            expect(after.positions[node.key], node.value, reason: node.key);
          }
        });
      }

      test('gate ${gate ? 'on' : 'off'}: a visible person with no Requests '
          'is placed only when the gate keeps them', () {
        final layout = place(
          field(newcomer: ConstellationFieldMembership.visible),
          gate: gate,
        );
        expect(layout.positions.containsKey('a-newcomer'), gate);
      });
    }
  });

  group('untrusting a bond peer', () {
    test('keeps the node and drops "I trust"', () {
      final field = ConstellationField(
        loadedAt: DateTime.utc(2026, 10, 24),
        context: '',
        peers: const [
          ConstellationPerson(
            id: 'b',
            fieldMembership: ConstellationFieldMembership.bond,
            autoTagKinds: {
              ConstellationAutoTagKind.iTrust,
              ConstellationAutoTagKind.trustsMe,
              ConstellationAutoTagKind.mutualContact,
            },
          ),
        ],
        edges: const [
          ConstellationTrustEdgeEntity(src: _ego, dst: 'b', tier: 1),
          ConstellationTrustEdgeEntity(src: 'b', dst: _ego, tier: 1),
        ],
        directContactIds: const ['b'],
      );
      final patched = patchViewerRelations(
        field,
        viewerId: _ego,
        relations: const [
          ConstellationViewerRelation(personId: 'b', viewerTrusts: false),
        ],
      );
      final peer = patched.peers.singleWhere((p) => p.id == 'b');
      expect(peer.autoTagKinds, {ConstellationAutoTagKind.trustsMe});
      expect(patched.directContactIds, isNot(contains('b')));
    });

    test('a contact-only node still leaves the field', () {
      final field = ConstellationField(
        loadedAt: DateTime.utc(2026, 10, 24),
        context: '',
        peers: const [ConstellationPerson(id: 'c', contactOnly: true)],
        directContactIds: const ['c'],
      );
      final patched = patchViewerRelations(
        field,
        viewerId: _ego,
        relations: const [
          ConstellationViewerRelation(personId: 'c', viewerTrusts: false),
        ],
      );
      expect(patched.peers, isEmpty);
    });
  });
}
