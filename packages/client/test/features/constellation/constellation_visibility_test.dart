import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/constellation/domain/constellation_anchor_composition.dart';
import 'package:tentura/features/constellation/domain/constellation_consts.dart';
import 'package:tentura/features/constellation/domain/constellation_filters.dart';
import 'package:tentura/features/constellation/domain/constellation_shown_field.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

/// #645: global show/hide switches for Requests, Posts and people by trust
/// degree; #641: the selected person's chain over what the field shows.
const _me = 'me';
final _asOf = DateTime.utc(2026, 10, 22, 12);

ConstellationAnchor _anchor(ConstellationAnchorTarget target) =>
    ConstellationAnchor(
      target: target,
      position: const ConstellationAnchorPosition(
        xUnits: 1,
        yUnits: 1,
        coordinateSpaceVersion: kConstellationCoordinateSpaceVersionV1,
      ),
      revision: ConstellationAnchorRevision.zero,
      placedAt: DateTime.utc(2026, 10, 2),
    );

ConstellationRequest _request(String id, String authorId) =>
    ConstellationRequest(id: id, authorId: authorId, title: id, status: 0);

ConstellationPost _post(String id, String authorId) => ConstellationPost(
  id: id,
  authorId: authorId,
  rootExcerpt: id,
  lastActivityAt: _asOf.subtract(const Duration(hours: 1)),
);

/// Ann (mutual) and Olga (one-way, a contact node) are direct contacts; Dan
/// is one derived step away; Bob is two steps away through Ann, Cid three;
/// Far authored a Request but no visible trust reaches them; everyone but
/// Olga and Cid has a Request or a Post on the field. Bob's Request
/// and Cid himself are pinned.
ConstellationField _field() => ConstellationField(
  loadedAt: _asOf,
  context: '',
  peers: const [
    ConstellationPerson(id: 'ann', displayName: 'Ann'),
    ConstellationPerson(
      id: 'olga',
      displayName: 'Olga',
      visible: false,
      contactOnly: true,
    ),
    ConstellationPerson(id: 'dan', displayName: 'Dan'),
    ConstellationPerson(id: 'bob', displayName: 'Bob'),
    ConstellationPerson(id: 'far', displayName: 'Far'),
  ],
  edges: const [
    ConstellationTrustEdgeEntity(src: _me, dst: 'ann', tier: 1),
    ConstellationTrustEdgeEntity(src: 'ann', dst: _me, tier: 1),
    ConstellationTrustEdgeEntity(src: _me, dst: 'olga', tier: 1),
    ConstellationTrustEdgeEntity(src: _me, dst: 'dan', tier: 2),
    ConstellationTrustEdgeEntity(src: 'ann', dst: 'bob', tier: 1),
  ],
  requests: [
    _request('r-me', _me),
    _request('r-ann', 'ann'),
    _request('r-bob', 'bob'),
    _request('r-far', 'far'),
    _request('r-dan', 'dan'),
  ],
  posts: [_post('p-ann', 'ann'), _post('p-bob', 'bob')],
  memberWebs: const [
    ConstellationMemberWeb(
      beaconId: 'p-bob',
      personId: 'ann',
      state: ConstellationMemberWebState.inside,
    ),
  ],
  directContactIds: const ['ann', 'olga'],
  anchorProjection: ConstellationAnchorProjection(
    revision: ConstellationAnchorRevision.zero,
    anchors: [
      _anchor(ConstellationAnchorTarget.beacon('r-bob')),
      _anchor(ConstellationAnchorTarget.person('cid')),
    ],
    pinnedPeers: const [ConstellationPerson(id: 'cid', displayName: 'Cid')],
    pinnedRequests: const [],
    supportPeers: const [],
    supportEdges: const [
      ConstellationTrustEdgeEntity(src: 'bob', dst: 'cid', tier: 1),
    ],
    serverFilteredBeaconIds: const [],
    serverFilteredBeaconCount: 0,
  ),
);

ConstellationField _shown(ConstellationVisibility visibility) =>
    constellationVisibleField(
      field: _field(),
      viewerId: _me,
      visibility: visibility,
    );

Set<String> _peerIds(ConstellationField field) => {
  for (final peer in field.peers) peer.id,
  for (final peer in field.resolvedAnchorProjection.pinnedPeers) peer.id,
};

Set<String> _beaconIds(ConstellationField field) => {
  for (final request in field.requests) request.id,
  for (final post in field.posts) post.id,
};

Set<String> _anchorIds(ConstellationField field) => {
  for (final anchor in field.resolvedAnchorProjection.anchors) anchor.target.id,
};

ConstellationComposedPresentation _compose(ConstellationField field) =>
    composeConstellationPresentation(
      viewerId: _me,
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

void main() {
  group('trust degrees', () {
    test('come from visible edges only, in three buckets', () {
      expect(constellationTrustDegrees(field: _field(), viewerId: _me), {
        'ann': ConstellationTrustDegree.first,
        'olga': ConstellationTrustDegree.first,
        'dan': ConstellationTrustDegree.second,
        'bob': ConstellationTrustDegree.second,
        'cid': ConstellationTrustDegree.further,
        'far': ConstellationTrustDegree.further,
      });
    });

    test('nobody is reached through a contact node', () {
      final field = _field().copyWith(
        edges: [
          ..._field().edges,
          const ConstellationTrustEdgeEntity(src: 'olga', dst: 'far', tier: 1),
        ],
      );
      expect(
        constellationTrustDegrees(field: field, viewerId: _me)['far'],
        ConstellationTrustDegree.further,
      );
    });
  });

  group('show/hide', () {
    test('everything shown leaves the field as it is', () {
      final field = _field();
      expect(
        identical(
          constellationVisibleField(
            field: field,
            viewerId: _me,
            visibility: ConstellationVisibility.all,
          ),
          field,
        ),
        isTrue,
      );
    });

    test("hiding Requests hides all of them, the viewer's and pinned", () {
      final field = _shown(const ConstellationVisibility(requests: false));
      expect(_beaconIds(field), {'p-ann', 'p-bob'});
      expect(_anchorIds(field), {'cid'});
      expect(_peerIds(field), _peerIds(_field()));
    });

    test('hiding Posts hides them and their webs', () {
      final field = _shown(const ConstellationVisibility(posts: false));
      expect(_beaconIds(field), {'r-me', 'r-ann', 'r-bob', 'r-far', 'r-dan'});
      expect(field.memberWebs, isEmpty);
    });

    test('hiding a degree hides its people with their items and edges, '
        'pinned ones too', () {
      final field = _shown(const ConstellationVisibility(secondDegree: false));
      expect(_peerIds(field), {'ann', 'olga', 'far', 'cid'});
      expect(_beaconIds(field), {'r-me', 'r-ann', 'r-far', 'p-ann'});
      // The pin of Bob's Request is kept by the store; only the field drops it.
      expect(_anchorIds(field), {'cid'});
      expect(field.edges.any((e) => e.dst == 'bob' || e.src == 'bob'), isFalse);
      expect(field.resolvedAnchorProjection.supportEdges, isEmpty);
      expect(field.memberWebs, isEmpty);
    });

    test('a pinned person of a hidden degree is hidden', () {
      final field = _shown(
        const ConstellationVisibility(furtherDegrees: false),
      );
      expect(_peerIds(field), {'ann', 'olga', 'dan', 'bob'});
      expect(field.resolvedAnchorProjection.pinnedPeers, isEmpty);
      expect(_anchorIds(field), {'r-bob'});
      expect(_beaconIds(field), isNot(contains('r-far')));
    });

    test(
      'hiding direct contacts empties the contact list; the viewer stays',
      () {
        final field = _shown(const ConstellationVisibility(firstDegree: false));
        expect(field.directContactIds, isEmpty);
        expect(_peerIds(field), {'dan', 'bob', 'far', 'cid'});
        expect(_beaconIds(field), contains('r-me'));
        expect(_compose(field).eligiblePersonIds, contains(_me));
      },
    );

    test('everything hidden leaves only the viewer', () {
      final field = _shown(
        const ConstellationVisibility(
          requests: false,
          posts: false,
          firstDegree: false,
          secondDegree: false,
          furtherDegrees: false,
        ),
      );
      expect(_peerIds(field), isEmpty);
      expect(_beaconIds(field), isEmpty);
      expect(_compose(field).eligiblePersonIds, {_me});
    });
  });

  test('people whose content is hidden by type stay holders', () {
    Set<String> holders(ConstellationVisibility visibility) =>
        constellationHiddenItemHolderIds(
          field: _field(),
          viewerId: _me,
          visibility: visibility,
        );
    expect(holders(ConstellationVisibility.all), isEmpty);
    expect(holders(const ConstellationVisibility(requests: false)), {
      'ann',
      'bob',
      'far',
      'dan',
    });
    expect(
      holders(
        const ConstellationVisibility(requests: false, secondDegree: false),
      ),
      {'ann', 'far'},
    );
    expect(holders(const ConstellationVisibility(posts: false)), {
      'ann',
      'bob',
    });
  });

  group('ConstellationVisibility', () {
    test('round-trips through JSON', () {
      const visibility = ConstellationVisibility(
        posts: false,
        secondDegree: false,
      );
      expect(
        ConstellationVisibility.fromJson(visibility.toJson()),
        visibility,
      );
    });

    test('anything unreadable shows', () {
      expect(
        ConstellationVisibility.fromJson('nope'),
        ConstellationVisibility.all,
      );
      expect(
        ConstellationVisibility.fromJson(const {'posts': 'no', 'first': false}),
        const ConstellationVisibility(firstDegree: false),
      );
    });

    test('withDegree flips one degree only', () {
      expect(
        ConstellationVisibility.all.withDegree(
          ConstellationTrustDegree.second,
          shown: false,
        ),
        const ConstellationVisibility(secondDegree: false),
      );
    });
  });

  test('counts what the field holds by switch', () {
    final field = _field();
    final counts = constellationVisibilityCounts(
      field: field,
      viewerId: _me,
      peopleOnField: _compose(field).eligiblePersonIds,
      asOfUtc: _asOf,
    );
    expect(counts.requests, 5);
    expect(counts.posts, 2);
    expect(counts.people, {
      ConstellationTrustDegree.first: 2,
      ConstellationTrustDegree.second: 2,
      ConstellationTrustDegree.further: 2,
    });
  });

  group('trust chain on the field', () {
    test('runs over the shown people and support paths', () {
      final field = _field();
      final chain = constellationTrustChainFor(
        viewerId: _me,
        personId: 'cid',
        field: field,
        composition: _compose(field),
      );
      expect(chain, isA<ConstellationTrustChainFound>());
      expect((chain as ConstellationTrustChainFound).path, [
        _me,
        'ann',
        'bob',
        'cid',
      ]);
      expect(chain.derivedHops, isEmpty);
    });

    test('a direct contact needs no chain, a contact node included', () {
      final field = _field();
      for (final id in ['ann', 'olga']) {
        expect(
          constellationTrustChainFor(
            viewerId: _me,
            personId: id,
            field: field,
            composition: _compose(field),
          ),
          isA<ConstellationTrustChainDirect>(),
        );
      }
    });

    test('says so when no visible chain reaches the person', () {
      final field = _field();
      expect(
        constellationTrustChainFor(
          viewerId: _me,
          personId: 'far',
          field: field,
          composition: _compose(field),
        ),
        isA<ConstellationTrustChainNone>(),
      );
    });

    test('marks the hops only a derived edge makes', () {
      final field = _field();
      final chain =
          constellationTrustChainFor(
                viewerId: _me,
                personId: 'dan',
                field: field,
                composition: _compose(field),
              )
              as ConstellationTrustChainFound;
      expect(chain.path, [_me, 'dan']);
      expect(chain.derivedHops, {(_me, 'dan')});
    });

    test('hidden intermediaries break the chain', () {
      final shown = _shown(const ConstellationVisibility(secondDegree: false));
      expect(
        constellationTrustChainFor(
          viewerId: _me,
          personId: 'cid',
          field: shown,
          composition: _compose(shown),
        ),
        isA<ConstellationTrustChainNone>(),
      );
    });
  });
}
