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

  /// Content readability of every pinned Request this transaction has decided,
  /// so later queries in the same transaction do not ask
  /// `beacon_can_read_content` again.
  final pinnedBeaconReadability = <String, bool>{};

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
    final existing = await _loadAnchors(viewerId);
    final blocks = await _blocks(viewerId);
    final targets = {...existing.map((a) => a.target), ...upsertTargets};
    final beaconIds = targets
        .whereType<ConstellationAnchorBeaconTarget>()
        .map((t) => t.id)
        .toList();
    final beacons = beaconIds.isEmpty
        ? const <ConstellationRequestRecord>[]
        : await _pinnedBeaconRecords(
            viewerId: viewerId,
            beaconIds: beaconIds,
            blocks: blocks,
          );
    final edges = await _repo.trustEdges(
      viewerId: viewerId,
      context: context,
      nodeIds: {...visible, viewerId},
    );
    final pinnedPeerIds = {
      for (final target in targets)
        if (target is ConstellationAnchorPersonTarget &&
            !blocks.blockingViewer.contains(target.id))
          target.id,
    };
    final holderIds = {
      ...pinnedPeerIds,
      for (final beacon in beacons)
        if (!beacon.isPlaceholder) beacon.authorId,
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
    final rows = await _loadAnchors(viewerId);
    return _buildAnchorProjection(
      viewerId: viewerId,
      context: context,
      filters: filters,
      watermark: revision ?? await _readWatermark(viewerId),
      anchorRows: rows,
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
    final anchorRows = await _loadAnchors(viewerId);
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

  Future<List<ConstellationAnchor>> _loadAnchors(String viewerId) async {
    final rows = await _database
        .customSelect(
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
WHERE ca.viewer_id = $1 AND ca.tombstone_at IS NULL
ORDER BY ca.placed_at, COALESCE(ca.beacon_id, ca.person_id)
''',
          variables: [Variable.withString(viewerId)],
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

  /// Pins whose target was deleted: identity and placement only.
  Future<List<ConstellationAnchor>> _loadTombstones(String viewerId) async {
    final rows = await _database
        .customSelect(
          r'''
SELECT target_id, target_kind, x_units, y_units, coordinate_space_version,
       revision::text AS revision, placed_at
FROM public.constellation_anchor
WHERE viewer_id = $1 AND tombstone_at IS NOT NULL
''',
          variables: [Variable.withString(viewerId)],
        )
        .get();
    return [
      for (final row in rows)
        ConstellationAnchor(
          target: row.read<String>('target_kind') == 'PERSON'
              ? ConstellationAnchorTarget.person(row.read<String>('target_id'))
              : ConstellationAnchorTarget.beacon(row.read<String>('target_id')),
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

  /// Only incoming blocks hide pins. Outgoing blocks mark them instead.
  Future<({Set<String> blockedByViewer, Set<String> blockingViewer})> _blocks(
    String viewerId,
  ) async {
    final rows = await _database
        .customSelect(
          'SELECT blocker_id, blocked_id FROM public.user_block '
          r'WHERE blocker_id = $1 OR blocked_id = $1',
          variables: [Variable.withString(viewerId)],
        )
        .get();
    return (
      blockedByViewer: {
        for (final row in rows)
          if (row.read<String>('blocker_id') == viewerId)
            row.read<String>('blocked_id'),
      },
      blockingViewer: {
        for (final row in rows)
          if (row.read<String>('blocked_id') == viewerId)
            row.read<String>('blocker_id'),
      },
    );
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
    final tombstoned = await _loadTombstones(viewerId);
    if (anchorRows.isEmpty) {
      return ConstellationAnchorProjection(
        revision: watermark,
        anchors: tombstoned..sort(ConstellationAnchor.comparePaintOrder),
        pinnedPeers: [
          for (final a in tombstoned)
            if (a.target is ConstellationAnchorPersonTarget)
              ConstellationPeerRecord.tombstone(a.target.id),
        ],
        pinnedRequests: [
          for (final a in tombstoned)
            if (a.target is ConstellationAnchorBeaconTarget)
              ConstellationRequestRecord.tombstone(a.target.id),
        ],
        supportPeers: const [],
        supportEdges: const [],
        serverFilteredBeaconIds: const [],
        serverFilteredBeaconCount: 0,
      );
    }

    final blocks = await _blocks(viewerId);

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
                blocks: blocks,
              ));

    final byBeaconId = {
      for (final record in pinnedBeaconRecords) record.id: record,
    };

    final shownAnchors = [
      for (final anchor in anchorRows)
        if (anchor.target is ConstellationAnchorPersonTarget
            ? !blocks.blockingViewer.contains(anchor.target.id)
            : byBeaconId.containsKey(anchor.target.id))
          anchor,
    ];
    final anchors = [...shownAnchors, ...tombstoned]
      ..sort(ConstellationAnchor.comparePaintOrder);

    final pinnedPeerIds = <String>[];
    final pinnedRequests = <ConstellationRequestRecord>[];
    final filterHiddenIds = <String>[];

    for (final anchor in shownAnchors) {
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
        if (record.isPlaceholder) {
          pinnedRequests.add(record);
          continue;
        }
        final participates = record.viewerParticipates ?? record.isMine;
        final layer = classifyAuthorizedPinnedBeacon(
          status: record.status,
          showClosed: filters.showClosed,
          participatedOnly: filters.participatedOnly,
          viewerParticipates: participates,
        );
        // Non-open readable pins keep their content and state badge even
        // when the field filter hides that lifecycle. Keep its counter too.
        if (record.pinState != null) pinnedRequests.add(record);
        switch (layer) {
          case ConstellationPinnedBeaconLayer.visiblePinned:
            if (record.pinState == null) pinnedRequests.add(record);
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
      for (final request in pinnedRequests)
        if (!request.isPlaceholder) request.authorId,
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

    final visibleSet = visiblePeerIds.toSet();
    final pinnedPeers = [
      for (final id in pinnedPeerIds..sort())
        (profileById[id] ?? ConstellationPeerRecord(id: id, displayName: id))
            .withVisible(
              visible: visibleSet.contains(id),
              pinState: blocks.blockedByViewer.contains(id)
                  ? 'blockedByMe'
                  : null,
            ),
      for (final a in tombstoned)
        if (a.target is ConstellationAnchorPersonTarget)
          ConstellationPeerRecord.tombstone(a.target.id),
    ];

    pinnedRequests.sort((a, b) => a.id.compareTo(b.id));
    pinnedRequests.addAll([
      for (final a in tombstoned)
        if (a.target is ConstellationAnchorBeaconTarget)
          ConstellationRequestRecord.tombstone(a.target.id),
    ]);

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
    required ({Set<String> blockedByViewer, Set<String> blockingViewer}) blocks,
  }) async {
    // Classify using only identity, lifecycle and the canonical read wall.
    // Fetch content separately, for readable targets only.
    final states = await _database
        .customSelect(
          r'''
SELECT b.id, b.user_id AS author_id, b.status,
       ((b.published_at IS NOT NULL OR b.status = 3)
         AND public.beacon_can_read_content(b.id, $1)) AS readable
FROM public.beacon b
WHERE b.id = ANY($2::text[])
''',
          variables: [
            Variable.withString(viewerId),
            Variable(TypedValue(Type.textArray, beaconIds)),
          ],
        )
        .get();
    final placeholders = <ConstellationRequestRecord>[];
    final readableStates = <String, String?>{};
    for (final row in states) {
      final id = row.read<String>('id');
      final authorId = row.readNullable<String>('author_id');
      final status = row.read<int>('status');
      final incoming = blocks.blockingViewer.contains(authorId);
      final outgoing = blocks.blockedByViewer.contains(authorId);
      final readable = !incoming && !outgoing && row.read<bool>('readable');
      pinnedBeaconReadability[id] = readable;
      if (incoming) continue;
      final placeholderState = outgoing
          ? 'blockedByMe'
          : status == 2
          ? 'deleted'
          : !readable
          ? (status == 3 ? 'unpublished' : 'noAccess')
          : null;
      if (placeholderState != null) {
        placeholders.add(
          ConstellationRequestRecord.placeholder(
            id,
            pinState: placeholderState,
          ),
        );
      } else {
        readableStates[id] = switch (status) {
          1 => 'cancelled',
          3 => 'unpublished',
          4 || 6 => 'closed',
          5 => 'wrappingUp',
          _ => null,
        };
      }
    }
    if (readableStates.isEmpty) return placeholders;
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
ORDER BY b.id
''',
          variables: [
            Variable.withString(viewerId),
            Variable(TypedValue(Type.textArray, readableStates.keys.toList())),
          ],
        )
        .get();

    return [
      ...placeholders,
      for (final row in rows)
        readConstellationRequestRow(
          row,
          viewerParticipates: row.read<bool>('viewer_participates'),
          pinState: readableStates[row.read<String>('id')],
        ),
    ];
  }
}
