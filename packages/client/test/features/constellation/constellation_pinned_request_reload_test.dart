import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_anchor_repository_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_store_case.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../../support/constellation_store_fixture.dart';
import '../../support/test_realtime_sync.dart';

// #673: after a reload a FULL read carries a pinned Request only in the anchor
// projection. The author's panel must still list it, and unpinning it (here
// or on another device) must hand it back to the field instead of dropping
// the only copy until the next reload.

const _viewer = Profile(id: 'me', displayName: 'Me');

ConstellationAnchorRevision _rev(int v) =>
    ConstellationAnchorRevision(BigInt.from(v));

const _ladder = ConstellationRequest(
  id: 'req-ladder',
  authorId: 'max',
  title: 'Max: borrow a ladder',
  status: 0,
);

ConstellationAnchor _pin(int revision) => ConstellationAnchor(
  target: ConstellationAnchorTarget.beacon('req-ladder'),
  position: const ConstellationAnchorPosition(
    xUnits: 3,
    yUnits: 4,
    coordinateSpaceVersion: 1,
  ),
  revision: _rev(revision),
  placedAt: DateTime.utc(2026, 10, 23),
);

ConstellationAnchorProjection _projection({
  required bool pinned,
  int rev = 5,
}) => ConstellationAnchorProjection(
  revision: _rev(rev),
  anchors: pinned ? [_pin(rev)] : const [],
  pinnedPeers: const [],
  pinnedRequests: pinned ? const [_ladder] : const [],
  supportPeers: const [],
  supportEdges: const [],
  serverFilteredBeaconIds: const [],
  serverFilteredBeaconCount: 0,
);

/// What the server returns after a reload: the pinned Request is left out of
/// `requests` and travels in the projection only.
ConstellationField _afterReload({bool pinned = true, int rev = 5}) =>
    ConstellationField(
      loadedAt: DateTime.utc(2026, 10, 23),
      context: '',
      peers: const [ConstellationPerson(id: 'max', displayName: 'Max')],
      edges: const [
        ConstellationTrustEdgeEntity(src: 'me', dst: 'max', tier: 1),
        ConstellationTrustEdgeEntity(src: 'max', dst: 'me', tier: 1),
      ],
      requests: pinned ? const [] : const [_ladder],
      directContactIds: const ['max'],
      anchorProjection: _projection(pinned: pinned, rev: rev),
    );

final class _Server implements ConstellationRepositoryPort {
  ConstellationField full = _afterReload();
  ConstellationField? anchors;

  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async =>
      projection == ConstellationProjection.anchors ? anchors ?? full : full;
}

ConstellationAnchorApplyResult _unpinAck() => ConstellationAnchorApplyResult(
  beforeRevision: _rev(5),
  afterRevision: _rev(6),
  results: [
    ConstellationAnchorOpResult(
      clientOpId: 'op-unpin',
      status: ConstellationAnchorOpStatus.ok,
      resultingTargetRevision: _rev(6),
      target: ConstellationAnchorTarget.beacon('req-ladder'),
    ),
  ],
);

void main() {
  late _Server server;
  late ConstellationStoreFixture fixture;

  Future<void> loaded() async {
    server = _Server();
    fixture = ConstellationStoreFixture(server, accountId: _viewer.id);
    await fixture.ready();
    fixture.store.lease();
    await fixture.store.requestRefresh(ConstellationRefreshReason.load);
  }

  Iterable<String> requestIds() =>
      fixture.store.current.field!.requests.map((r) => r.id);

  test("the author's panel lists a pinned Request after a reload", () async {
    await loaded();
    final cubit = fixture.createCubit(viewer: _viewer);
    await cubit.load();

    expect(
      cubit.discoverableRequestsForPerson('max').map((r) => r.id),
      ['req-ladder'],
    );
  });

  test('unpinning after a reload keeps the Request on the field', () async {
    await loaded();
    expect(requestIds(), isEmpty);

    fixture.store.settle(_unpinAck(), () {});

    final field = fixture.store.current.field!;
    expect(field.resolvedAnchorProjection.pinnedRequests, isEmpty);
    expect(requestIds(), ['req-ladder']);
  });

  test('an unpin from another device (ANCHORS read) keeps it too', () async {
    final sync = buildTestRealtimeSync();
    addTearDown(sync.port.dispose);
    server = _Server();
    fixture = ConstellationStoreFixture(
      server,
      accountId: _viewer.id,
      realtime: sync.case_,
    );
    await fixture.ready();
    fixture.store.lease();
    await fixture.store.requestRefresh(ConstellationRefreshReason.load);
    server.anchors = _afterReload(pinned: false, rev: 6);

    sync.port.emitChange(
      RealtimeEntityChange(
        kind: RealtimeEntityKind.constellationAnchor,
        aggregateId: _viewer.id,
        operation: RealtimeOperation.update,
        source: RealtimeChangeSource.serverInvalidation,
        revision: BigInt.from(6),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }

    expect(fixture.store.current.coveredRevision, _rev(6));
    expect(requestIds(), contains('req-ladder'));
  });

  test('an older FULL that still has it pinned does not drop it after the '
      'unpin', () async {
    await loaded();
    fixture.store.settle(_unpinAck(), () {});
    expect(requestIds(), ['req-ladder']);

    // A read that started before the unpin lands: revision 5, still pinned,
    // so its Requests leave it out.
    await fixture.store.requestRefresh(ConstellationRefreshReason.load);

    expect(
      fixture.store.current.field!.resolvedAnchorProjection.anchors,
      isEmpty,
    );
    expect(requestIds(), ['req-ladder']);
  });

  test('the person panel still lists it after the unpin', () async {
    await loaded();
    final cubit = fixture.createCubit(viewer: _viewer);
    await cubit.load();

    fixture.store.settle(_unpinAck(), () {});
    await Future<void>.delayed(Duration.zero);

    expect(
      cubit.discoverableRequestsForPerson('max').map((r) => r.id),
      ['req-ladder'],
    );
  });
}
