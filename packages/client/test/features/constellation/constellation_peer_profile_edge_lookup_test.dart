// Turning a field peer into a profile needs the viewer<->peer explicit-trust
// flags. Resolving them must not rescan the field's whole edge list once per
// peer (compose does it for every drawn peer, the body for every label), or
// the cost grows with peers x edges.

import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';

import '../../support/constellation_store_fixture.dart';

const _viewer = Profile(id: 'ego', displayName: 'Ego');
const _peerCount = 200;
const _edgeCount = 400;

/// A list that counts every element it hands out, however it is traversed.
final class _CountingList<T> extends ListBase<T> {
  _CountingList(this._inner);

  final List<T> _inner;
  int reads = 0;

  @override
  int get length => _inner.length;

  @override
  set length(int value) => throw UnsupportedError('read-only');

  @override
  T operator [](int index) {
    reads++;
    return _inner[index];
  }

  @override
  void operator []=(int index, T value) => throw UnsupportedError('read-only');

  @override
  Iterator<T> get iterator => _CountingIterator(this);
}

final class _CountingIterator<T> implements Iterator<T> {
  _CountingIterator(this._list);

  final _CountingList<T> _list;
  int _index = -1;

  @override
  T get current => _list._inner[_index];

  @override
  bool moveNext() {
    _index++;
    if (_index >= _list._inner.length) return false;
    _list.reads++;
    return true;
  }
}

final class _StubRepository implements ConstellationRepositoryPort {
  _StubRepository(this.field);

  final ConstellationField field;

  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async => field;
}

ConstellationField _field({
  required List<ConstellationPerson> peers,
  required List<ConstellationTrustEdgeEntity> edges,
  List<ConstellationRequest> requests = const [],
}) => ConstellationField(
  loadedAt: DateTime.utc(2026, 10, 9),
  context: '',
  peers: peers,
  edges: edges,
  requests: requests,
);

List<ConstellationPerson> _peers() => [
  for (var i = 0; i < _peerCount; i++)
    ConstellationPerson(id: 'p$i', displayName: 'Peer $i'),
];

/// Edges that touch the viewer, one shape per peer:
/// p0 viewer->peer, p1 peer->viewer, p2 derived peer->viewer, p3 both ways,
/// p4 derived viewer->peer. Every other peer has no edge to the viewer.
const _viewerEdges = [
  ConstellationTrustEdgeEntity(src: 'ego', dst: 'p0', tier: 1),
  ConstellationTrustEdgeEntity(src: 'p1', dst: 'ego', tier: 1),
  ConstellationTrustEdgeEntity(src: 'p2', dst: 'ego', tier: 2),
  ConstellationTrustEdgeEntity(src: 'ego', dst: 'p3', tier: 1),
  ConstellationTrustEdgeEntity(src: 'p3', dst: 'ego', tier: 1),
  ConstellationTrustEdgeEntity(src: 'ego', dst: 'p4', tier: 2),
];

/// With [viewerTrustsAll] the viewer has a direct edge to every other peer, so
/// composition keeps (and therefore profiles) every one of them.
_CountingList<ConstellationTrustEdgeEntity> _edges({
  bool viewerTrustsAll = false,
}) {
  final extraViewerEdges = [
    if (viewerTrustsAll)
      for (var i = 5; i < _peerCount; i++)
        ConstellationTrustEdgeEntity(src: 'ego', dst: 'p$i', tier: 1),
  ];
  return _CountingList([
    ..._viewerEdges,
    ...extraViewerEdges,
    // Peer-to-peer edges: none of them touch the viewer, so a per-peer scan
    // has to walk the whole list for almost every peer. Two of them join
    // peers that do have viewer edges, to catch a lookup that keys on the
    // wrong endpoint.
    const ConstellationTrustEdgeEntity(src: 'p0', dst: 'p1', tier: 1),
    const ConstellationTrustEdgeEntity(src: 'p5', dst: 'p3', tier: 1),
    for (
      var i = 0;
      i < _edgeCount - _viewerEdges.length - extraViewerEdges.length - 2;
      i++
    )
      ConstellationTrustEdgeEntity(
        src: 'p${5 + i % (_peerCount - 5)}',
        dst: 'p${5 + (i * 7 + 1) % (_peerCount - 5)}',
        tier: 1,
      ),
  ]);
}

/// Expected flags for [peerId], computed by brute force from [edges].
({int myVote, bool trustsViewer}) _expectedFlags(
  List<ConstellationTrustEdgeEntity> edges,
  String peerId,
) => (
  myVote: edges.any(
    (e) => e.tier == 1 && e.src == _viewer.id && e.dst == peerId,
  )
      ? 1
      : 0,
  trustsViewer: edges.any(
    (e) => e.tier == 1 && e.src == peerId && e.dst == _viewer.id,
  ),
);

ConstellationCubit _cubitFor(ConstellationField field) =>
    ConstellationStoreFixture(
      _StubRepository(field),
      accountId: _viewer.id,
    ).createCubit(viewer: _viewer);

void main() {
  test(
    'peer profiles carry the viewer trust flags from the field edges',
    () async {
      final cubit = _cubitFor(_field(peers: _peers(), edges: _edges()));
      await cubit.load();

      final trusted = cubit.profileForPersonId('p0')!;
      expect(trusted.myVote, 1);
      expect(trusted.subjectExplicitlyTrustsViewer, isFalse);

      final trusting = cubit.profileForPersonId('p1')!;
      expect(trusting.myVote, 0);
      expect(trusting.subjectExplicitlyTrustsViewer, isTrue);

      final derived = cubit.profileForPersonId('p2')!;
      expect(derived.myVote, 0);
      expect(derived.subjectExplicitlyTrustsViewer, isFalse);

      final mutual = cubit.profileForPersonId('p3')!;
      expect(mutual.myVote, 1);
      expect(mutual.subjectExplicitlyTrustsViewer, isTrue);

      final derivedOutgoing = cubit.profileForPersonId('p4')!;
      expect(derivedOutgoing.myVote, 0);
      expect(derivedOutgoing.subjectExplicitlyTrustsViewer, isFalse);
    },
  );

  test(
    'a peer with no edge to the viewer gets default flags even when other '
    'peers have one',
    () async {
      final cubit = _cubitFor(_field(peers: _peers(), edges: _edges()));
      await cubit.load();

      // p5 has a peer-to-peer edge to p3 (which the viewer trusts), but none
      // to the viewer itself.
      for (final id in ['p5', 'p6', 'p${_peerCount - 1}']) {
        final profile = cubit.profileForPersonId(id)!;
        expect(profile.myVote, 0, reason: 'myVote of $id');
        expect(
          profile.subjectExplicitlyTrustsViewer,
          isFalse,
          reason: 'subjectExplicitlyTrustsViewer of $id',
        );
      }
    },
  );

  test(
    'profiling every peer reads each field edge a bounded number of times '
    "and keeps every peer's own trust flags",
    () async {
      final peers = _peers();
      final edges = _edges();
      final cubit = _cubitFor(_field(peers: peers, edges: edges));
      await cubit.load();
      final expectedEdges = List.of(edges.toList());
      edges.reads = 0;

      final profiles = {
        for (final peer in peers) peer.id: cubit.profileForPersonId(peer.id),
      };

      expect(
        edges.reads,
        lessThanOrEqualTo(_edgeCount * 4),
        reason:
            'edge reads while profiling $_peerCount peers '
            'over $_edgeCount edges',
      );
      for (final peer in peers) {
        final profile = profiles[peer.id];
        expect(profile, isNotNull, reason: 'profile of ${peer.id}');
        final expected = _expectedFlags(expectedEdges, peer.id);
        expect(profile!.myVote, expected.myVote, reason: 'myVote ${peer.id}');
        expect(
          profile.subjectExplicitlyTrustsViewer,
          expected.trustsViewer,
          reason: 'subjectExplicitlyTrustsViewer of ${peer.id}',
        );
      }
    },
  );

  test(
    'loading the field composes its peers without a per-peer edge scan',
    () async {
      final edges = _edges();
      final cubit = _cubitFor(
        _field(
          peers: _peers(),
          edges: edges,
          requests: [
            for (var i = 0; i < _peerCount; i++)
              ConstellationRequest(
                id: 'r$i',
                authorId: 'p$i',
                title: 'Request $i',
                status: 0,
              ),
          ],
        ),
      );

      await cubit.load();

      expect(
        edges.reads,
        lessThanOrEqualTo(_edgeCount * 40),
        reason:
            'edge reads while composing $_peerCount peers '
            'over $_edgeCount edges',
      );
    },
  );
}
