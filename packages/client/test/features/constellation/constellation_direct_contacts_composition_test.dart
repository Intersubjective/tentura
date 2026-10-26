import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/constellation/domain/constellation_anchor_composition.dart';
import 'package:tentura/features/constellation/domain/constellation_consts.dart';
import 'package:tentura/features/constellation/domain/constellation_filters.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

/// #246 client half: every direct contact the snapshot lists is a holder,
/// kept regardless of the 120-peer render budget (Q6); the budget still
/// limits indirect peers; pinned and support guarantees are unchanged.
const _ego = 'U_ego';
final _asOf = DateTime.utc(2026, 10, 22, 12);

String _id(String prefix, int i) => '$prefix${i.toString().padLeft(4, '0')}';

ConstellationComposedPresentation _compose(ConstellationField field) =>
    composeConstellationPresentation(
      viewerId: _ego,
      field: field,
      localFilters: const (
        capabilitySlugs: {},
        location: LocationFilter.any,
        timing: TimingFilterAny(),
        includeUnspecified: true,
      ),
      asOfUtc: _asOf,
      labelBudget: (perPerson: 3, total: 150),
    );

ConstellationAnchor _anchor(ConstellationAnchorTarget target) =>
    ConstellationAnchor(
      target: target,
      position: const ConstellationAnchorPosition(
        xUnits: 1,
        yUnits: 1,
        coordinateSpaceVersion: kConstellationCoordinateSpaceVersionV1,
      ),
      revision: ConstellationAnchorRevision.zero,
      placedAt: DateTime.utc(2026, 10, 1),
    );

void main() {
  test('a direct contact with nothing to show is on the field', () {
    final field = ConstellationField(
      loadedAt: _asOf,
      context: '',
      peers: const [ConstellationPerson(id: 'quiet')],
      edges: const [
        ConstellationTrustEdgeEntity(src: _ego, dst: 'quiet', tier: 1),
      ],
      directContactIds: const ['quiet'],
    );

    final composed = _compose(field);

    expect(composed.keptPeerIds, contains('quiet'));
    expect(composed.eligiblePersonIds, contains('quiet'));
  });

  test(
    'a visible person stays on the Field without a direct contact entry',
    () {
      final field = ConstellationField(
        loadedAt: _asOf,
        context: '',
        peers: const [ConstellationPerson(id: 'quiet')],
        edges: const [
          ConstellationTrustEdgeEntity(src: _ego, dst: 'quiet', tier: 1),
        ],
      );

      expect(_compose(field).keptPeerIds, contains('quiet'));
    },
  );

  test('a contact node without content is kept with its single edge', () {
    final field = ConstellationField(
      loadedAt: _asOf,
      context: '',
      peers: const [
        ConstellationPerson(id: 'oneway', visible: false, contactOnly: true),
      ],
      edges: const [
        ConstellationTrustEdgeEntity(src: _ego, dst: 'oneway', tier: 1),
      ],
      directContactIds: const ['oneway'],
    );

    final composed = _compose(field);

    expect(composed.keptPeerIds, contains('oneway'));
    expect(composed.paths.depth['oneway'], 1);
  });

  test('direct contacts beyond the render budget are all kept, and the '
      'budget still caps indirect holders', () {
    final directCount = constellationRenderPeerCap() + 180;
    final indirectCount = constellationRenderPeerCap() + 40;
    final direct = [for (var i = 0; i < directCount; i++) _id('d', i)];
    // Every visible bridge and descendant is independently a holder in phase 1.
    final bridges = [for (var i = 0; i < indirectCount; i++) _id('b', i)];
    final indirect = [for (var i = 0; i < indirectCount; i++) _id('i', i)];
    final field = ConstellationField(
      loadedAt: _asOf,
      context: '',
      peers: [
        for (final id in [...direct, ...bridges, ...indirect])
          ConstellationPerson(id: id),
      ],
      edges: [
        for (final id in direct)
          ConstellationTrustEdgeEntity(src: _ego, dst: id, tier: 1),
        for (var i = 0; i < indirectCount; i++) ...[
          ConstellationTrustEdgeEntity(src: _ego, dst: bridges[i], tier: 2),
          ConstellationTrustEdgeEntity(
            src: bridges[i],
            dst: indirect[i],
            tier: 2,
          ),
        ],
      ],
      requests: [
        for (final id in indirect)
          ConstellationRequest(
            id: 'r-$id',
            authorId: id,
            title: 'Request',
            status: 0,
          ),
      ],
      directContactIds: direct,
    );

    final composed = _compose(field);

    expect(composed.keptPeerIds.containsAll(direct), isTrue);
    final keptIndirect = composed.keptPeerIds.intersection(indirect.toSet());
    // With every visible person a holder, shallower bridge peers fill the
    // render budget before their depth-2 descendants.
    expect(keptIndirect, isEmpty);
    expect(
      composed.keptPeerIds.intersection(bridges.toSet()),
      hasLength(constellationRenderPeerCap()),
    );
    expect(composed.renderBudgetCapped, isTrue);
  });

  test('pinned people and pinned-Request support paths are unchanged', () {
    final field = ConstellationField(
      loadedAt: _asOf,
      context: '',
      peers: const [
        ConstellationPerson(id: 'contact'),
        ConstellationPerson(id: 'bridge'),
      ],
      edges: const [
        ConstellationTrustEdgeEntity(src: _ego, dst: 'contact', tier: 1),
        ConstellationTrustEdgeEntity(src: _ego, dst: 'bridge', tier: 2),
      ],
      directContactIds: const ['contact'],
      anchorProjection: ConstellationAnchorProjection(
        revision: ConstellationAnchorRevision.zero,
        anchors: [
          _anchor(ConstellationAnchorTarget.person('pinned')),
          _anchor(ConstellationAnchorTarget.beacon('req-far')),
        ],
        pinnedPeers: const [ConstellationPerson(id: 'pinned')],
        pinnedRequests: const [
          ConstellationRequest(
            id: 'req-far',
            authorId: 'far',
            title: 'Far',
            status: 0,
          ),
        ],
        supportPeers: const [
          ConstellationPerson(id: 'bridge'),
          ConstellationPerson(id: 'far'),
        ],
        supportEdges: const [
          ConstellationTrustEdgeEntity(src: _ego, dst: 'bridge', tier: 2),
          ConstellationTrustEdgeEntity(src: 'bridge', dst: 'far', tier: 2),
        ],
        serverFilteredBeaconIds: const [],
        serverFilteredBeaconCount: 0,
      ),
    );

    final composed = _compose(field);

    expect(
      composed.keptPeerIds,
      containsAll(<String>['contact', 'pinned', 'bridge', 'far']),
    );
    expect(composed.eligibleRequestIds, contains('req-far'));
  });

  test('the viewer and unknown ids in the contact list are ignored', () {
    final field = ConstellationField(
      loadedAt: _asOf,
      context: '',
      peers: const [ConstellationPerson(id: 'known')],
      edges: const [
        ConstellationTrustEdgeEntity(src: _ego, dst: 'known', tier: 1),
      ],
      directContactIds: const [_ego, 'known', 'ghost'],
    );

    expect(constellationDirectContactIds(field: field, viewerId: _ego), {
      'known',
    });
  });
}
