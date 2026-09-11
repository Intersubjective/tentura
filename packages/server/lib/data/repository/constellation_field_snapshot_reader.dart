import 'package:drift/drift.dart' hide Column;
import 'package:drift_postgres/drift_postgres.dart';
import 'package:postgres/postgres.dart' show Type, TypedValue;

import 'package:tentura_server/consts/constellation_consts.dart';
import 'package:tentura_server/domain/constellation/constellation_field_selection.dart';
import 'package:tentura_server/domain/constellation/constellation_path_resolution.dart';
import 'package:tentura_server/domain/entity/constellation_anchor.dart';
import 'package:tentura_server/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura_server/domain/entity/constellation_field.dart';
import 'package:tentura_server/domain/port/constellation_field_repository_port.dart';
import 'package:tentura_server/domain/port/user_profile_batch_lookup_port.dart';

import '../database/tentura_db.dart' hide ConstellationAnchor;
import 'constellation_field_repository.dart';
import 'constellation_field_snapshot_probe.dart';

/// Builds [ConstellationFieldSnapshot] inside an existing read snapshot transaction.
final class ConstellationFieldSnapshotReader {
  ConstellationFieldSnapshotReader(this._database, this._profiles);

  final TenturaDb _database;
  final UserProfileBatchLookup _profiles;

  Future<ConstellationFieldSnapshot> read({
    required String viewerId,
    required String context,
    required ConstellationFieldReadParams params,
  }) async {
    final loadedAt = DateTime.now().toUtc();
    await constellationFieldSnapshotOpenProbe?.call(_database);
    if (viewerId.trim().isEmpty) {
      return ConstellationFieldSnapshot(
        loadedAt: loadedAt,
        context: context,
        peers: const [],
        edges: const [],
        requests: const [],
        peersCapped: false,
        requestsCapped: false,
      );
    }

    final watermark = await _readWatermark(viewerId);
    final anchorRows = await _loadAuthorizedAnchors(
      viewerId: viewerId,
      context: context,
    );
    final anchorProjection = await _buildAnchorProjection(
      viewerId: viewerId,
      context: context,
      filters: params.filters,
      watermark: watermark,
      anchorRows: anchorRows,
    );

    if (params.projection == ConstellationProjection.anchors) {
      return ConstellationFieldSnapshot(
        loadedAt: loadedAt,
        context: context,
        peers: const [],
        edges: const [],
        requests: const [],
        peersCapped: false,
        requestsCapped: false,
        anchorProjection: anchorProjection,
      );
    }

    final reservedPeerIds = <String>{
      for (final peer in anchorProjection.pinnedPeers) peer.id,
      for (final peer in anchorProjection.supportPeers) peer.id,
      for (final request in anchorProjection.pinnedRequests) request.authorId,
    };

    final graphPeers = await _visibleGraphPeerIds(
      viewerId: viewerId,
      context: context,
      cap: kConstellationPeerCap,
      excludePeerIds: reservedPeerIds,
    );

    final ownRequests = await _ownRequests(
      viewerId: viewerId,
      showClosed: params.filters.showClosed,
      participatedOnly: params.filters.participatedOnly,
    );

    final reservedBeaconIds = {
      for (final request in anchorProjection.pinnedRequests) request.id,
    };

    final peerRequestsRaw = await _discoverableRequests(
      viewerId: viewerId,
      context: context,
      cap: kConstellationRequestCap,
      excludeBeaconIds: reservedBeaconIds,
      excludeAuthorIds: reservedPeerIds,
      showClosed: params.filters.showClosed,
      participatedOnly: params.filters.participatedOnly,
    );
    final requestsCapped = peerRequestsRaw.length > kConstellationRequestCap;
    final peerRequests = requestsCapped
        ? peerRequestsRaw.sublist(0, kConstellationRequestCap)
        : peerRequestsRaw;

    final requests = [...ownRequests, ...peerRequests];

    final edgeNodeIds = {...graphPeers.ids, viewerId};
    final edges = await _repo.trustEdges(
      viewerId: viewerId,
      context: context,
      nodeIds: edgeNodeIds,
    );

    final profileIds = {...graphPeers.ids, ...reservedPeerIds};
    for (final request in requests) {
      profileIds.add(request.authorId);
    }

    final peers = await _repo.peerProfiles(ids: profileIds);

    return ConstellationFieldSnapshot(
      loadedAt: loadedAt,
      context: context,
      peers: peers,
      edges: edges,
      requests: requests,
      peersCapped: graphPeers.capped,
      requestsCapped: requestsCapped,
      anchorProjection: anchorProjection,
    );
  }

  ConstellationFieldRepository get _repo =>
      ConstellationFieldRepository(_database, _profiles);

  Future<ConstellationAnchorRevision> _readWatermark(String viewerId) async {
    final rows = await _database.customSelect(
      r'''
SELECT revision::text AS revision
FROM public.constellation_anchor_cursor
WHERE viewer_id = $1
''',
      variables: [Variable.withString(viewerId)],
    ).get();
    if (rows.isEmpty) {
      return ConstellationAnchorRevision.zero;
    }
    final parsed = ConstellationAnchorRevision.parseDecimalString(
      rows.single.read<String>('revision'),
    );
    return switch (parsed) {
      ConstellationAnchorRevisionParsed(:final revision) => revision,
      ConstellationAnchorRevisionMalformed() => ConstellationAnchorRevision.zero,
    };
  }

  Future<List<_AuthorizedAnchorRow>> _loadAuthorizedAnchors({
    required String viewerId,
    required String context,
  }) async {
    final rows = await _database.customSelect(
      r'''
SELECT
  ca.person_id,
  ca.beacon_id,
  ca.x_units,
  ca.y_units,
  ca.coordinate_space_version,
  ca.revision::text AS revision,
  ca.placed_at
FROM public.constellation_anchor ca
WHERE ca.viewer_id = $1
  AND (
    (
      ca.person_id IS NOT NULL
      AND ca.person_id <> $1
      AND EXISTS (
        SELECT 1 FROM public.person_visible_peers_symmetric($1, $2) p
        WHERE p.peer_id::text = ca.person_id
      )
      AND NOT public.block_hides($1, ca.person_id)
      AND NOT public.block_hides(ca.person_id, $1)
    )
    OR (
      ca.beacon_id IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM public.beacon b
        WHERE b.id = ca.beacon_id
          AND b.published_at IS NOT NULL
          AND b.status = ANY('{0,7,8,5,4,6}'::int[])
          AND public.beacon_can_read_content(b.id, $1)
          AND NOT public.block_hides($1, b.user_id)
          AND NOT public.block_hides(b.user_id, $1)
      )
    )
  )
ORDER BY ca.placed_at, COALESCE(ca.beacon_id, ca.person_id)
''',
      variables: [
        Variable.withString(viewerId),
        Variable.withString(context),
      ],
    ).get();

    return [
      for (final row in rows)
        _AuthorizedAnchorRow(
          anchor: ConstellationAnchor(
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
        ),
    ];
  }

  Future<ConstellationAnchorProjection> _buildAnchorProjection({
    required String viewerId,
    required String context,
    required ConstellationFieldMembershipFilters filters,
    required ConstellationAnchorRevision watermark,
    required List<_AuthorizedAnchorRow> anchorRows,
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

    final anchors = [
      for (final row in anchorRows) row.anchor,
    ]..sort(ConstellationAnchor.comparePaintOrder);

    final beaconIds = [
      for (final row in anchorRows)
        if (row.anchor.target case ConstellationAnchorBeaconTarget(:final id))
          id,
    ];

    final pinnedBeaconRecords = beaconIds.isEmpty
        ? const <ConstellationRequestRecord>[]
        : await _pinnedBeaconRecords(
            viewerId: viewerId,
            beaconIds: beaconIds,
          );

    final byBeaconId = {
      for (final record in pinnedBeaconRecords) record.id: record,
    };

    final pinnedPeerIds = <String>[];
    final pinnedRequests = <ConstellationRequestRecord>[];
    final filterHiddenIds = <String>[];

    for (final row in anchorRows) {
      final target = row.anchor.target;
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

    final visiblePeerIds = await _allVisiblePeerIds(
      viewerId: viewerId,
      context: context,
    );

    final pathNodeIds = {...visiblePeerIds, viewerId, ...pathHolderIds};
    final pathEdges = await _repo.trustEdges(
      viewerId: viewerId,
      context: context,
      nodeIds: pathNodeIds,
    );

    final resolution = resolveConstellationPaths(
      egoId: viewerId,
      visiblePeerIds: visiblePeerIds,
      holderIds: pathHolderIds,
      edges: [
        for (final edge in pathEdges)
          (src: edge.src, dst: edge.dst, tier: edge.tier),
      ],
    );

    final supportPeerIds = resolution.keep
        .difference({
          viewerId,
          ...pinnedPeerIds,
          ...pinnedRequests.map((r) => r.authorId),
        })
        .toList()
      ..sort();

    final profileIds = {...pinnedPeerIds, ...supportPeerIds};
    final profiles = await _repo.peerProfiles(ids: profileIds);
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

  Future<Set<String>> _allVisiblePeerIds({
    required String viewerId,
    required String context,
  }) async {
    final rows = await _database.customSelect(
      r'''
SELECT s.peer_id::text AS peer_id
FROM public.person_visible_peers_symmetric($1, $2) s
WHERE NOT public.block_hides($1, s.peer_id::text)
  AND NOT public.block_hides(s.peer_id::text, $1)
ORDER BY s.peer_id
''',
      variables: [
        Variable.withString(viewerId),
        Variable.withString(context),
      ],
    ).get();
    return {for (final row in rows) row.read<String>('peer_id')};
  }

  Future<({Set<String> ids, bool capped})> _visibleGraphPeerIds({
    required String viewerId,
    required String context,
    required int cap,
    required Set<String> excludePeerIds,
  }) async {
    if (cap <= 0) {
      return (ids: const <String>{}, capped: false);
    }
    final rows = await _database.customSelect(
      r'''
SELECT s.peer_id::text AS peer_id
FROM public.person_visible_peers_symmetric($1, $2) s
WHERE NOT public.block_hides($1, s.peer_id::text)
  AND NOT public.block_hides(s.peer_id::text, $1)
  AND NOT (s.peer_id::text = ANY($3::text[]))
ORDER BY s.peer_id
LIMIT $4
''',
      variables: [
        Variable.withString(viewerId),
        Variable.withString(context),
        Variable(
          TypedValue(Type.textArray, excludePeerIds.toList()..sort()),
        ),
        Variable.withInt(cap + 1),
      ],
    ).get();
    final capped = rows.length > cap;
    return (
      ids: {for (final row in rows.take(cap)) row.read<String>('peer_id')},
      capped: capped,
    );
  }

  Future<List<ConstellationRequestRecord>> _pinnedBeaconRecords({
    required String viewerId,
    required List<String> beaconIds,
  }) async {
    final participation = constellationViewerParticipatesSql(
      viewerParam: r'$1',
      beaconAlias: 'b',
    );
    final rows = await _database.customSelect(
      '''
SELECT $constellationRequestSelectColumns
  , ($participation) AS viewer_participates
FROM public.beacon b
LEFT JOIN public.image cover ON cover.id = b.cover_thumb_image_id
WHERE b.id = ANY(\$2::text[])
  AND b.published_at IS NOT NULL
  AND public.beacon_can_read_content(b.id, \$1)
  AND NOT public.block_hides(\$1, b.user_id)
  AND NOT public.block_hides(b.user_id, \$1)
ORDER BY b.id
''',
      variables: [
        Variable.withString(viewerId),
        Variable(TypedValue(Type.textArray, beaconIds)),
      ],
    ).get();

    return [
      for (final row in rows)
        readConstellationRequestRow(
          row,
          viewerParticipates: row.read<bool>('viewer_participates'),
        ),
    ];
  }

  Future<List<ConstellationRequestRecord>> _ownRequests({
    required String viewerId,
    required bool showClosed,
    required bool participatedOnly,
  }) async {
    final statuses = constellationFieldBeaconStatuses(showClosed: showClosed);
    final statusArray = statuses.toList()..sort();
    final participation = participatedOnly
        ? constellationViewerParticipatesSql(
            viewerParam: r'$1',
            beaconAlias: 'b',
          )
        : null;
    final rows = await _database.customSelect(
      '''
SELECT $constellationRequestSelectColumns
FROM public.beacon b
LEFT JOIN public.image cover ON cover.id = b.cover_thumb_image_id
WHERE b.user_id = \$1
  AND b.status = ANY(\$2::int[])
  AND b.published_at IS NOT NULL
  ${participation == null ? '' : 'AND ($participation)'}
ORDER BY b.id
''',
      variables: [
        Variable.withString(viewerId),
        Variable(TypedValue(Type.integerArray, statusArray)),
      ],
    ).get();
    return rows.map(readConstellationRequestRow).toList(growable: false);
  }

  Future<List<ConstellationRequestRecord>> _discoverableRequests({
    required String viewerId,
    required String context,
    required int cap,
    required Set<String> excludeBeaconIds,
    required Set<String> excludeAuthorIds,
    required bool showClosed,
    required bool participatedOnly,
  }) async {
    if (cap <= 0) {
      return const [];
    }
    final statuses = constellationFieldBeaconStatuses(showClosed: showClosed);
    final statusArray = statuses.toList()..sort();
    final participation = participatedOnly
        ? constellationViewerParticipatesSql(
            viewerParam: r'$1',
            beaconAlias: 'b',
          )
        : null;
    final rows = await _database.customSelect(
      '''
SELECT $constellationRequestSelectColumns
FROM public.person_visible_peers_symmetric(\$1, \$2) p
INNER JOIN public.beacon b ON b.user_id = p.peer_id::text
LEFT JOIN public.image cover ON cover.id = b.cover_thumb_image_id
WHERE b.user_id <> \$1
  AND b.is_discoverable
  AND b.status = ANY(\$3::int[])
  AND b.published_at IS NOT NULL
  AND NOT public.block_hides(\$1, b.user_id)
  AND public.beacon_can_read_content(b.id, \$1)
  AND NOT (b.id = ANY(\$4::text[]))
  AND NOT (b.user_id = ANY(\$5::text[]))
  ${participation == null ? '' : 'AND ($participation)'}
ORDER BY b.user_id, b.id
LIMIT \$6
''',
      variables: [
        Variable.withString(viewerId),
        Variable.withString(context),
        Variable(TypedValue(Type.integerArray, statusArray)),
        Variable(
          TypedValue(Type.textArray, excludeBeaconIds.toList()..sort()),
        ),
        Variable(
          TypedValue(Type.textArray, excludeAuthorIds.toList()..sort()),
        ),
        Variable.withInt(cap + 1),
      ],
    ).get();
    return rows.map(readConstellationRequestRow).toList(growable: false);
  }
}

final class _AuthorizedAnchorRow {
  const _AuthorizedAnchorRow({required this.anchor});

  final ConstellationAnchor anchor;
}
