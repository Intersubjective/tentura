import 'package:postgres/postgres.dart' show Type, TypedValue;

import 'package:tentura_server/consts/constellation_consts.dart';
import 'package:tentura_server/domain/constellation/constellation_field_selection.dart';
import 'package:tentura_server/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura_server/domain/entity/constellation_field.dart';
import 'package:tentura_server/domain/port/constellation_field_repository_port.dart';
import 'package:tentura_server/domain/port/user_profile_batch_lookup_port.dart';

import '../database/tentura_db.dart' hide ConstellationAnchor;
import 'constellation_anchor_projection_reader.dart';
import 'constellation_field_repository.dart';

/// Builds [ConstellationFieldSnapshot] inside an existing read snapshot transaction.
final class ConstellationFieldSnapshotReader {
  ConstellationFieldSnapshotReader(
    this._database,
    this._profiles, {
    Future<void> Function(TenturaDb db)? snapshotOpenProbe,
  }) : _snapshotOpenProbe = snapshotOpenProbe;

  final TenturaDb _database;
  final UserProfileBatchLookup _profiles;
  final Future<void> Function(TenturaDb db)? _snapshotOpenProbe;

  late final _anchors = ConstellationAnchorProjectionReader(
    _database,
    _profiles,
  );

  Future<ConstellationFieldSnapshot> read({
    required String viewerId,
    required String context,
    required ConstellationFieldReadParams params,
  }) async {
    final loadedAt = DateTime.now().toUtc();
    await _snapshotOpenProbe?.call(_database);
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

    // The viewer's mutually visible, unblocked peers, in id order. Computed
    // once per snapshot; every query below takes it as an array instead of
    // re-deriving it (each derivation is a MeritRank round-trip).
    final visiblePeerIds = await _anchors.visiblePeers(
      viewerId: viewerId,
      context: context,
    );
    final anchorProjection = await _anchors.readForVisiblePeers(
      viewerId: viewerId,
      context: context,
      filters: params.filters,
      visiblePeerIds: visiblePeerIds,
      trustEdges: () => _trustEdges(
        viewerId: viewerId,
        context: context,
        visiblePeerIds: visiblePeerIds,
      ),
      peerProfiles: _peerProfiles,
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

    final graphPeers = _visibleGraphPeerIds(
      visiblePeerIds: visiblePeerIds,
      cap: kConstellationPeerCap,
      excludePeerIds: reservedPeerIds,
    );

    final ownRequests = await _ownRequests(
      viewerId: viewerId,
      showClosed: params.filters.showClosed,
      participatedOnly: params.filters.participatedOnly,
    );

    final postFeed = await _postsAndMemberWebs(
      viewerId: viewerId,
      visiblePeerIds: visiblePeerIds,
    );

    final reservedBeaconIds = {
      for (final request in anchorProjection.pinnedRequests) request.id,
    };

    final peerRequestsRaw = await _discoverableRequests(
      viewerId: viewerId,
      visiblePeerIds: visiblePeerIds,
      cap: kConstellationRequestCap,
      excludeBeaconIds: reservedBeaconIds,
      showClosed: params.filters.showClosed,
      participatedOnly: params.filters.participatedOnly,
    );
    final requestsCapped = peerRequestsRaw.length > kConstellationRequestCap;
    final peerRequests = requestsCapped
        ? peerRequestsRaw.sublist(0, kConstellationRequestCap)
        : peerRequestsRaw;

    final requests = [...ownRequests, ...peerRequests];

    final edgeNodeIds = {...graphPeers.ids, viewerId};
    final edges = [
      for (final edge in await _trustEdges(
        viewerId: viewerId,
        context: context,
        visiblePeerIds: visiblePeerIds,
      ))
        if (edgeNodeIds.contains(edge.src) && edgeNodeIds.contains(edge.dst))
          edge,
    ];

    final profileIds = {...graphPeers.ids, ...reservedPeerIds};
    for (final request in requests) {
      profileIds.add(request.authorId);
    }
    for (final post in postFeed.posts) {
      profileIds.add(post.authorId);
    }
    for (final web in postFeed.memberWebs) {
      profileIds.add(web.personId);
    }

    final peers = await _peerProfiles(profileIds);

    return ConstellationFieldSnapshot(
      loadedAt: loadedAt,
      context: context,
      peers: peers,
      edges: edges,
      requests: requests,
      peersCapped: graphPeers.capped,
      requestsCapped: requestsCapped,
      posts: postFeed.posts,
      memberWebs: postFeed.memberWebs,
      anchorProjection: anchorProjection,
    );
  }

  ConstellationFieldRepository get _repo =>
      ConstellationFieldRepository(_database, _profiles);

  Future<List<ConstellationEdgeRecord>>? _allTrustEdges;

  final _profileById = <String, ConstellationPeerRecord?>{};

  /// Trust edges among the viewer and every visible peer, fetched once per
  /// snapshot. Callers that need a smaller node set filter it: edges only
  /// ever join allowed nodes (the viewer and its visible peers), so the
  /// subset query would return exactly the filtered rows.
  Future<List<ConstellationEdgeRecord>> _trustEdges({
    required String viewerId,
    required String context,
    required List<String> visiblePeerIds,
  }) => _allTrustEdges ??= _repo.trustEdges(
    viewerId: viewerId,
    context: context,
    nodeIds: {...visiblePeerIds, viewerId},
  );

  /// Profiles in id order; ids already fetched in this snapshot are reused.
  Future<List<ConstellationPeerRecord>> _peerProfiles(Set<String> ids) async {
    final missing = ids.where((id) => !_profileById.containsKey(id)).toSet();
    if (missing.isNotEmpty) {
      final fetched = await _repo.peerProfiles(ids: missing);
      for (final id in missing) {
        _profileById[id] = null;
      }
      for (final profile in fetched) {
        _profileById[profile.id] = profile;
      }
    }
    return [
      for (final id in ids.toList()..sort()) ?_profileById[id],
    ];
  }

  /// Posts the viewer authored or was admitted to (role 6), active within the
  /// last 72 hours or pinned by the viewer, plus their member webs. Members
  /// outside the viewer's visible peer set are only counted.
  Future<
    ({
      List<ConstellationPostRecord> posts,
      List<ConstellationMemberWebRecord> memberWebs,
    })
  >
  _postsAndMemberWebs({
    required String viewerId,
    required List<String> visiblePeerIds,
  }) async {
    final postRows = await _database
        .customSelect(
          '''
SELECT
  b.id,
  b.user_id AS author_id,
  COALESCE(b.last_activity_at, b.published_at, b.created_at) AS last_activity_at,
  left(COALESCE(root.body, ''), \$2::int) AS root_excerpt,
  EXISTS (
    SELECT 1 FROM public.beacon_pinned pin
    WHERE pin.beacon_id = b.id AND pin.user_id = \$1
  ) AS is_pinned
FROM public.beacon b
LEFT JOIN public.beacon_room_message root ON root.id = b.post_root_message_id
WHERE b.kind = 1
  AND b.status = 0
  AND ${constellationBeaconContentReadableSql(viewerParam: r'$1', beaconAlias: 'b')}
  AND (
    b.user_id = \$1
    OR EXISTS (
      SELECT 1 FROM public.beacon_participant bp
      WHERE bp.beacon_id = b.id AND bp.user_id = \$1
        AND bp.role = 6 AND bp.room_access = 3
    )
  )
  AND (
    COALESCE(b.last_activity_at, b.published_at, b.created_at)
      > now() - interval '72 hours'
    OR EXISTS (
      SELECT 1 FROM public.beacon_pinned pin
      WHERE pin.beacon_id = b.id AND pin.user_id = \$1
    )
  )
ORDER BY last_activity_at DESC, b.id
''',
          variables: [
            Variable.withString(viewerId),
            Variable.withInt(kConstellationPostExcerptLength),
          ],
        )
        .get();
    if (postRows.isEmpty) {
      return (
        posts: const <ConstellationPostRecord>[],
        memberWebs: const <ConstellationMemberWebRecord>[],
      );
    }

    final postIds = [for (final row in postRows) row.read<String>('id')];
    final memberRows = await _database
        .customSelect(
          r'''
SELECT m.beacon_id, m.person_id, bool_or(m.is_inside) AS is_inside
FROM (
  SELECT b.id AS beacon_id, b.user_id AS person_id, true AS is_inside
  FROM public.beacon b
  WHERE b.id = ANY($2::text[])
  UNION ALL
  SELECT bp.beacon_id, bp.user_id, true
  FROM public.beacon_participant bp
  WHERE bp.beacon_id = ANY($2::text[])
    AND bp.room_access = 3
    AND EXISTS (
      SELECT 1 FROM public.beacon_room_seen s
      WHERE s.beacon_id = bp.beacon_id AND s.user_id = bp.user_id
        AND s.thread_item_id IS NULL
    )
  UNION ALL
  SELECT e.beacon_id, e.recipient_id, false
  FROM public.beacon_forward_edge e
  WHERE e.beacon_id = ANY($2::text[]) AND e.cancelled_at IS NULL
) m
WHERE m.person_id <> $1
GROUP BY m.beacon_id, m.person_id
ORDER BY m.beacon_id, m.person_id
''',
          variables: [
            Variable.withString(viewerId),
            Variable(TypedValue(Type.textArray, postIds)),
          ],
        )
        .get();

    final visible = visiblePeerIds.toSet();
    final memberWebs = <ConstellationMemberWebRecord>[];
    final hiddenByPost = <String, int>{};
    for (final row in memberRows) {
      final beaconId = row.read<String>('beacon_id');
      final personId = row.read<String>('person_id');
      if (visible.contains(personId)) {
        memberWebs.add(
          ConstellationMemberWebRecord(
            beaconId: beaconId,
            personId: personId,
            state: row.read<bool>('is_inside')
                ? ConstellationMemberWebState.inside
                : ConstellationMemberWebState.forwarded,
          ),
        );
      } else {
        hiddenByPost[beaconId] = (hiddenByPost[beaconId] ?? 0) + 1;
      }
    }

    return (
      posts: [
        for (final row in postRows)
          ConstellationPostRecord(
            id: row.read<String>('id'),
            authorId: row.read<String>('author_id'),
            lastActivityAt: readCustomSelectTimestamptz(
              row.data['last_activity_at'],
            )!,
            rootExcerpt: row.read<String>('root_excerpt'),
            isPinned: row.read<bool>('is_pinned'),
            hiddenReachCount: hiddenByPost[row.read<String>('id')] ?? 0,
          ),
      ],
      memberWebs: memberWebs,
    );
  }

  ({Set<String> ids, bool capped}) _visibleGraphPeerIds({
    required List<String> visiblePeerIds,
    required int cap,
    required Set<String> excludePeerIds,
  }) {
    if (cap <= 0) {
      return (ids: const <String>{}, capped: false);
    }
    final candidates = [
      for (final id in visiblePeerIds)
        if (!excludePeerIds.contains(id)) id,
    ];
    return (
      ids: candidates.take(cap).toSet(),
      capped: candidates.length > cap,
    );
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
  AND b.kind = 0
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
    required List<String> visiblePeerIds,
    required int cap,
    required Set<String> excludeBeaconIds,
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
    final statusVariable = Variable(TypedValue(Type.integerArray, statusArray));
    final excludedVariable = Variable(
      TypedValue(Type.textArray, excludeBeaconIds.toList()..sort()),
    );
    final peersVariable = Variable(TypedValue(Type.textArray, visiblePeerIds));

    // Keyset scan over `(user_id, id)`: each batch of candidates passing the
    // cheap row predicates is checked for readability set-wise, and the key
    // advances past every examined candidate, readable or not, so each one is
    // asked about at most once and the scan stops at cap + 1 eligible rows.
    final eligible = <ConstellationRequestRecord>[];
    String? lastUserId;
    String? lastId;
    while (eligible.length <= cap) {
      final candidates = await _database.customSelect(
        '''
SELECT b.user_id AS user_id, b.id AS id
FROM public.beacon b
WHERE b.user_id = ANY(\$2::text[])
  AND b.is_discoverable
  AND b.kind = 0
  AND b.status = ANY(\$3::int[])
  AND b.published_at IS NOT NULL
  AND NOT public.block_hides(\$1, b.user_id)
  AND NOT (b.id = ANY(\$4::text[]))
  ${participation == null ? '' : 'AND ($participation)'}
  ${lastId == null ? '' : r'AND (b.user_id, b.id) > ($6, $7)'}
ORDER BY b.user_id, b.id
LIMIT \$5
''',
        variables: [
          Variable.withString(viewerId),
          peersVariable,
          statusVariable,
          excludedVariable,
          Variable.withInt(kConstellationDiscoverableScanBatch),
          if (lastId != null) ...[
            Variable.withString(lastUserId!),
            Variable.withString(lastId),
          ],
        ],
      ).get();
      if (candidates.isEmpty) {
        break;
      }
      final batchIds = [for (final row in candidates) row.read<String>('id')];
      lastUserId = candidates.last.read<String>('user_id');
      lastId = batchIds.last;

      final rows = await _database.customSelect(
        '''
SELECT $constellationRequestSelectColumns
FROM public.beacon b
LEFT JOIN public.image cover ON cover.id = b.cover_thumb_image_id
WHERE b.id IN (SELECT public.beacon_readable_ids(\$1, \$2::text[]))
ORDER BY b.user_id, b.id
''',
        variables: [
          Variable.withString(viewerId),
          Variable(TypedValue(Type.textArray, batchIds)),
        ],
      ).get();
      eligible.addAll(rows.map(readConstellationRequestRow));
      if (candidates.length < kConstellationDiscoverableScanBatch) {
        break;
      }
    }
    return eligible.length > cap ? eligible.sublist(0, cap + 1) : eligible;
  }
}
