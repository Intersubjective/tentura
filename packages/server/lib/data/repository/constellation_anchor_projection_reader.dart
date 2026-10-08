import 'package:postgres/postgres.dart' show Type, TypedValue;

import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura_root/domain/constellation/constellation_path_resolution.dart';
import 'package:tentura_server/domain/constellation/constellation_field_selection.dart';
import 'package:tentura_server/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura_server/domain/entity/constellation_field.dart';
import 'package:tentura_server/domain/port/user_profile_batch_lookup_port.dart';

import '../database/tentura_db.dart' hide ConstellationAnchor;
import 'constellation_field_repository.dart';

/// Snapshot inputs shared by authorization and post-write hydration.
final class PreparedConstellationAnchors {
  const PreparedConstellationAnchors({
    required this.visiblePeerIds,
    required this.beacons,
    required this.edges,
    required this.profiles,
  });

  final List<String> visiblePeerIds;
  final List<ConstellationRequestRecord> beacons;
  final List<ConstellationEdgeRecord> edges;
  final List<ConstellationPeerRecord> profiles;

  bool authorizes(ConstellationAnchorTarget target) => switch (target.kind) {
    ConstellationAnchorTargetKind.person => visiblePeerIds.contains(target.id),
    ConstellationAnchorTargetKind.beacon => beacons.any(
      (b) => b.id == target.id && isKnownConstellationBeaconStatus(b.status),
    ),
  };
}

/// Builds [ConstellationAnchorProjection] using only the caller's current
/// transaction (read snapshot or mutating repeatable read), so it sees the
/// caller's own uncommitted anchor writes.
final class ConstellationAnchorProjectionReader {
  ConstellationAnchorProjectionReader(this._database, this._profiles);

  final TenturaDb _database;
  final UserProfileBatchLookup _profiles;

  ConstellationFieldRepository get _repo =>
      ConstellationFieldRepository(_database, _profiles);

  Future<PreparedConstellationAnchors> prepare({
    required String viewerId,
    required String context,
    required ConstellationFieldMembershipFilters filters,
    required Iterable<ConstellationAnchorTarget> upsertTargets,
    List<String>? visiblePeerIds,
  }) async {
    final visible =
        visiblePeerIds ??
        await visiblePeers(viewerId: viewerId, context: context);
    final existing = await _loadAuthorizedAnchors(
      viewerId: viewerId,
      visiblePeerIds: visible,
      authorize: false,
    );
    final targets = {...existing.map((a) => a.target), ...upsertTargets};
    final beaconIds = targets
        .whereType<ConstellationAnchorBeaconTarget>()
        .map((t) => t.id)
        .toList();
    final beacons = beaconIds.isEmpty
        ? const <ConstellationRequestRecord>[]
        : await _pinnedBeaconRecords(viewerId: viewerId, beaconIds: beaconIds);
    final edges = await _repo.trustEdges(
      viewerId: viewerId,
      context: context,
      nodeIds: {...visible, viewerId},
    );
    final pinnedPeerIds = {
      for (final target in targets)
        if (target is ConstellationAnchorPersonTarget &&
            visible.contains(target.id))
          target.id,
    };
    final holderIds = {
      ...pinnedPeerIds,
      for (final beacon in beacons)
        if (classifyAuthorizedPinnedBeacon(
              status: beacon.status,
              showClosed: filters.showClosed,
              participatedOnly: filters.participatedOnly,
              viewerParticipates: beacon.viewerParticipates ?? beacon.isMine,
            ) ==
            ConstellationPinnedBeaconLayer.visiblePinned)
          beacon.authorId,
    };
    final closure = _supportClosure(
      viewerId: viewerId,
      visiblePeerIds: visible,
      pinnedPeerIds: pinnedPeerIds,
      holderIds: holderIds,
      edges: edges,
    );
    final profiles = await _repo.peerProfiles(
      ids: {
        ...holderIds,
        ...closure.supportPeerIds,
      },
    );
    return PreparedConstellationAnchors(
      visiblePeerIds: visible,
      beacons: beacons,
      edges: edges,
      profiles: profiles,
    );
  }

  Future<ConstellationAnchorProjection> readPrepared({
    required String viewerId,
    required String context,
    required ConstellationFieldMembershipFilters filters,
    required PreparedConstellationAnchors prepared,
    ConstellationAnchorRevision? revision,
  }) async {
    final rows = await _loadAuthorizedAnchors(
      viewerId: viewerId,
      visiblePeerIds: prepared.visiblePeerIds,
      authorize: false,
    );
    final readableBeacons = prepared.beacons.map((b) => b.id).toSet();
    return _buildAnchorProjection(
      viewerId: viewerId,
      context: context,
      filters: filters,
      watermark: revision ?? await _readWatermark(viewerId),
      anchorRows: rows
          .where(
            (a) => a.target.kind == ConstellationAnchorTargetKind.person
                ? prepared.visiblePeerIds.contains(a.target.id)
                : readableBeacons.contains(a.target.id),
          )
          .toList(),
      visiblePeerIds: prepared.visiblePeerIds,
      trustEdges: () async => prepared.edges,
      peerProfiles: (_) async => prepared.profiles,
      preparedBeacons: prepared.beacons,
    );
  }

  Future<ConstellationAnchorProjection> read({
    required String viewerId,
    required String context,
    required ConstellationFieldMembershipFilters filters,
  }) async {
    final visiblePeerIds = await visiblePeers(
      viewerId: viewerId,
      context: context,
    );
    return readForVisiblePeers(
      viewerId: viewerId,
      context: context,
      filters: filters,
      visiblePeerIds: visiblePeerIds,
      trustEdges: () => _repo.trustEdges(
        viewerId: viewerId,
        context: context,
        nodeIds: {...visiblePeerIds, viewerId},
      ),
      peerProfiles: (ids) => _repo.peerProfiles(ids: ids),
    );
  }

  /// Like [read], for callers that already hold the viewer's
  /// [visiblePeerIds] and memoise trust edges and profiles across a wider
  /// snapshot.
  Future<ConstellationAnchorProjection> readForVisiblePeers({
    required String viewerId,
    required String context,
    required ConstellationFieldMembershipFilters filters,
    required List<String> visiblePeerIds,
    required Future<List<ConstellationEdgeRecord>> Function() trustEdges,
    required Future<List<ConstellationPeerRecord>> Function(Set<String> ids)
    peerProfiles,
  }) async {
    final watermark = await _readWatermark(viewerId);
    final anchorRows = await _loadAuthorizedAnchors(
      viewerId: viewerId,
      visiblePeerIds: visiblePeerIds,
    );
    return _buildAnchorProjection(
      viewerId: viewerId,
      context: context,
      filters: filters,
      watermark: watermark,
      anchorRows: anchorRows,
      visiblePeerIds: visiblePeerIds,
      trustEdges: trustEdges,
      peerProfiles: peerProfiles,
    );
  }

  Future<ConstellationAnchorRevision> _readWatermark(String viewerId) async {
    final rows = await _database
        .customSelect(
          r'''
SELECT revision::text AS revision
FROM public.constellation_anchor_cursor
WHERE viewer_id = $1
''',
          variables: [Variable.withString(viewerId)],
        )
        .get();
    if (rows.isEmpty) {
      return ConstellationAnchorRevision.zero;
    }
    final parsed = ConstellationAnchorRevision.parseDecimalString(
      rows.single.read<String>('revision'),
    );
    return switch (parsed) {
      ConstellationAnchorRevisionParsed(:final revision) => revision,
      ConstellationAnchorRevisionMalformed() =>
        ConstellationAnchorRevision.zero,
    };
  }

  Future<List<ConstellationAnchor>> _loadAuthorizedAnchors({
    required String viewerId,
    required List<String> visiblePeerIds,
    bool authorize = true,
  }) async {
    final beaconReadable = constellationBeaconContentReadableSql(
      viewerParam: r'$1',
      beaconAlias: 'b',
    );
    final rows = await _database
        .customSelect(
          '''
SELECT
  ca.person_id,
  ca.beacon_id,
  ca.x_units,
  ca.y_units,
  ca.coordinate_space_version,
  ca.revision::text AS revision,
  ca.placed_at
FROM public.constellation_anchor ca
-- Join (not EXISTS): an EXISTS here gets planned as a hashed SubPlan that
-- runs beacon_can_read_content over every beacon in the table (12s+ on dev).
${authorize ? 'LEFT JOIN public.beacon b ON b.id = ca.beacon_id' : ''}
WHERE ca.viewer_id = \$1
${authorize ? '''
  AND (
    -- Visible peers exclude the viewer and blocks in either direction.
    ca.person_id = ANY(\$2::text[])
    OR (
      b.id IS NOT NULL
      AND $beaconReadable
    )
  )''' : ''}
ORDER BY ca.placed_at, COALESCE(ca.beacon_id, ca.person_id)
''',
          variables: [
            Variable.withString(viewerId),
            if (authorize) Variable(TypedValue(Type.textArray, visiblePeerIds)),
          ],
        )
        .get();

    return [
      for (final row in rows)
        ConstellationAnchor(
          target: row.readNullable<String>('person_id') != null
              ? ConstellationAnchorTarget.person(
                  row.read<String>('person_id'),
                )
              : ConstellationAnchorTarget.beacon(row.read<String>('beacon_id')),
          position: ConstellationAnchorPosition(
            xUnits: row.read<double>('x_units'),
            yUnits: row.read<double>('y_units'),
            coordinateSpaceVersion: row.read<int>('coordinate_space_version'),
          ),
          revision: switch (ConstellationAnchorRevision.parseDecimalString(
            row.read<String>('revision'),
          )) {
            ConstellationAnchorRevisionParsed(:final revision) => revision,
            ConstellationAnchorRevisionMalformed() =>
              ConstellationAnchorRevision.zero,
          },
          placedAt: DateTime.parse(row.read<String>('placed_at')).toUtc(),
        ),
    ];
  }

  Future<ConstellationAnchorProjection> _buildAnchorProjection({
    required String viewerId,
    required String context,
    required ConstellationFieldMembershipFilters filters,
    required ConstellationAnchorRevision watermark,
    required List<ConstellationAnchor> anchorRows,
    required List<String> visiblePeerIds,
    required Future<List<ConstellationEdgeRecord>> Function() trustEdges,
    required Future<List<ConstellationPeerRecord>> Function(Set<String> ids)
    peerProfiles,
    List<ConstellationRequestRecord>? preparedBeacons,
  }) async {
    if (anchorRows.isEmpty) {
      return ConstellationAnchorProjection(
        revision: watermark,
        anchors: const [],
        pinnedPeers: const [],
        pinnedRequests: const [],
        supportPeers: const [],
        supportEdges: const [],
        serverFilteredBeaconIds: const [],
        serverFilteredBeaconCount: 0,
      );
    }

    final anchors = [...anchorRows]
      ..sort(ConstellationAnchor.comparePaintOrder);

    final beaconIds = [
      for (final anchor in anchorRows)
        if (anchor.target case ConstellationAnchorBeaconTarget(:final id)) id,
    ];

    final pinnedBeaconRecords =
        preparedBeacons ??
        (beaconIds.isEmpty
            ? const <ConstellationRequestRecord>[]
            : await _pinnedBeaconRecords(
                viewerId: viewerId,
                beaconIds: beaconIds,
              ));

    final byBeaconId = {
      for (final record in pinnedBeaconRecords) record.id: record,
    };

    final pinnedPeerIds = <String>[];
    final pinnedRequests = <ConstellationRequestRecord>[];
    final filterHiddenIds = <String>[];

    for (final anchor in anchorRows) {
      final target = anchor.target;
      if (target is ConstellationAnchorPersonTarget) {
        pinnedPeerIds.add(target.id);
        continue;
      }
      if (target is ConstellationAnchorBeaconTarget) {
        final id = target.id;
        final record = byBeaconId[id];
        if (record == null) {
          continue;
        }
        final participates = record.viewerParticipates ?? record.isMine;
        final layer = classifyAuthorizedPinnedBeacon(
          status: record.status,
          showClosed: filters.showClosed,
          participatedOnly: filters.participatedOnly,
          viewerParticipates: participates,
        );
        switch (layer) {
          case ConstellationPinnedBeaconLayer.visiblePinned:
            pinnedRequests.add(record);
          case ConstellationPinnedBeaconLayer.filterHidden:
            filterHiddenIds.add(id);
          case ConstellationPinnedBeaconLayer.dormantAnchor:
            break;
        }
      }
    }

    final uniqueFilterHidden = filterHiddenIds.toSet().toList()..sort();

    final pathHolderIds = <String>{
      ...pinnedPeerIds,
      for (final request in pinnedRequests) request.authorId,
    };

    // Holders outside the visible set never had edges: trust edges only
    // join the viewer and visible peers.
    final pathEdges = await trustEdges();

    final closure = _supportClosure(
      viewerId: viewerId,
      visiblePeerIds: visiblePeerIds,
      pinnedPeerIds: pinnedPeerIds.toSet(),
      holderIds: pathHolderIds,
      edges: pathEdges,
    );
    final resolution = closure.resolution;
    final supportPeerIds = closure.supportPeerIds.toList()..sort();
    final profileIds = {...pathHolderIds, ...supportPeerIds};
    final profiles = await peerProfiles(profileIds);
    final profileById = {for (final p in profiles) p.id: p};

    final pinnedPeers = [
      for (final id in pinnedPeerIds..sort())
        profileById[id] ?? ConstellationPeerRecord(id: id, displayName: id),
    ];

    pinnedRequests.sort((a, b) => a.id.compareTo(b.id));

    final supportPeers = [
      for (final id in supportPeerIds)
        profileById[id] ?? ConstellationPeerRecord(id: id, displayName: id),
    ];

    final supportEdgeSet = constellationSupportEdges(
      egoId: viewerId,
      resolution: resolution,
      trustEdges: [
        for (final edge in pathEdges)
          (src: edge.src, dst: edge.dst, tier: edge.tier),
      ],
    );
    final supportEdges = [
      for (final edge in supportEdgeSet)
        ConstellationEdgeRecord(
          src: edge.src,
          dst: edge.dst,
          tier: edge.tier,
        ),
    ];

    return ConstellationAnchorProjection(
      revision: watermark,
      anchors: anchors,
      pinnedPeers: pinnedPeers,
      pinnedRequests: pinnedRequests,
      supportPeers: supportPeers,
      supportEdges: supportEdges,
      serverFilteredBeaconIds: uniqueFilterHidden,
      serverFilteredBeaconCount: uniqueFilterHidden.length,
    );
  }

  static ({ConstellationPathResolution resolution, Set<String> supportPeerIds})
  _supportClosure({
    required String viewerId,
    required List<String> visiblePeerIds,
    required Set<String> pinnedPeerIds,
    required Set<String> holderIds,
    required List<ConstellationEdgeRecord> edges,
  }) {
    final resolution = resolveConstellationPaths(
      egoId: viewerId,
      visiblePeerIds: {...visiblePeerIds, ...holderIds},
      holderIds: holderIds,
      edges: [
        for (final edge in edges)
          (src: edge.src, dst: edge.dst, tier: edge.tier),
      ],
    );
    return (
      resolution: resolution,
      supportPeerIds: {
        ...resolution.keep.difference({viewerId, ...pinnedPeerIds}),
        ...resolution.ring.difference({viewerId, ...pinnedPeerIds}),
      },
    );
  }

  /// Reads the transaction's visibility memo, so later SQL in the same
  /// snapshot (`beacon_can_read_content`, `constellation_trust_edges`) reuses
  /// it. Blocks hide in both directions, as in `block_hides`; the predicate
  /// is an anti-join because `block_hides` is never inlined and costs a
  /// function call per visible peer (~20 ms at V ≈ 1,000).
  Future<List<String>> visiblePeers({
    required String viewerId,
    required String context,
  }) async {
    final row = await _database
        .customSelect(
          r'''
WITH blocked AS (
  SELECT ub.blocked_id AS id FROM public.user_block ub WHERE ub.blocker_id = $1
  UNION
  SELECT ub.blocker_id FROM public.user_block ub WHERE ub.blocked_id = $1
)
SELECT ARRAY(
  SELECT p.peer_id
  FROM unnest(public.person_visible_peer_ids_tx($1, $2)) AS p(peer_id)
  WHERE NOT EXISTS (SELECT 1 FROM blocked b WHERE b.id = p.peer_id)
  ORDER BY p.peer_id
) AS peer_ids
''',
          variables: [
            Variable.withString(viewerId),
            Variable.withString(context),
          ],
        )
        .getSingle();
    return row.read<List<dynamic>>('peer_ids').cast<String>();
  }

  Future<List<ConstellationRequestRecord>> _pinnedBeaconRecords({
    required String viewerId,
    required List<String> beaconIds,
  }) async {
    final participation = constellationViewerParticipatesSql(
      viewerParam: r'$1',
      beaconAlias: 'b',
    );
    final rows = await _database
        .customSelect(
          '''
SELECT $constellationRequestSelectColumns
  , ($participation) AS viewer_participates
FROM public.beacon b
LEFT JOIN public.image cover ON cover.id = b.cover_thumb_image_id
WHERE b.id = ANY(\$2::text[])
  AND ${constellationBeaconContentReadableSql(viewerParam: r'$1', beaconAlias: 'b')}
ORDER BY b.id
''',
          variables: [
            Variable.withString(viewerId),
            Variable(TypedValue(Type.textArray, beaconIds)),
          ],
        )
        .get();

    return [
      for (final row in rows)
        readConstellationRequestRow(
          row,
          viewerParticipates: row.read<bool>('viewer_participates'),
        ),
    ];
  }
}
