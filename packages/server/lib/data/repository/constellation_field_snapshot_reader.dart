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
      for (final request in anchorProjection.pinnedRequests)
        if (!request.isPlaceholder) request.authorId,
    };

    // Everyone the viewer trusts directly is on the field (#246) and outside
    // the peer cap (Q6): a visible one as an ordinary peer, any other as a
    // contact node without content (Q5).
    final directContactIds = await _directContactIds(viewerId);
    final visibleSet = visiblePeerIds.toSet();
    final directVisibleIds = <String>{
      for (final id in directContactIds)
        if (visibleSet.contains(id)) id,
    };

    // Bond (B) and temporary (T) peers outside the visible set are on the
    // field with full content; visible > bond > temporary > contactOnly.
    final bondContexts = await _bondContexts(viewerId, visibleSet);
    final temporaryBeacons = await _temporaryBeacons(
      viewerId,
      excluding: {...visibleSet, ...bondContexts.keys},
    );
    final contactOnlyIds = <String>{
      for (final id in directContactIds)
        if (!visibleSet.contains(id) &&
            !bondContexts.containsKey(id) &&
            !temporaryBeacons.containsKey(id))
          id,
    };

    final kept = await _cappedPeerIds(
      viewerId: viewerId,
      context: context,
      visiblePeerIds: visiblePeerIds,
      reservedPeerIds: reservedPeerIds,
      directContactIds: directContactIds.toSet(),
      bondPeerIds: bondContexts.keys.toSet(),
      temporaryPeerIds: temporaryBeacons.keys.toSet(),
    );
    bondContexts.removeWhere((id, _) => !kept.ids.contains(id));
    temporaryBeacons.removeWhere((id, _) => !kept.ids.contains(id));
    final graphPeerIds = {
      ...directVisibleIds.where(reservedPeerIds.contains),
      ...kept.ids.where(visibleSet.contains),
    };

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

    final knownRequestIds = {
      for (final r in [...ownRequests, ...peerRequests]) r.id,
      ...reservedBeaconIds,
    };
    final temporaryRequests = await _temporaryRequests(
      viewerId: viewerId,
      beaconIds: {
        for (final id in temporaryBeacons.values)
          if (!knownRequestIds.contains(id)) id,
      },
      showClosed: params.filters.showClosed,
    );

    final requests = [...ownRequests, ...peerRequests, ...temporaryRequests];

    // The graph only draws edges among its capped peers and the viewer. Reuse
    // the full set when the anchor projection already loaded it; otherwise
    // ask for these nodes only, which returns the same rows (an edge's tier
    // depends on its own endpoints only).
    final edgeNodeIds = {...graphPeerIds, viewerId};
    final allTrustEdges = _allTrustEdges;
    final visibleEdges = allTrustEdges == null
        ? await _repo.trustEdges(
            viewerId: viewerId,
            context: context,
            nodeIds: edgeNodeIds,
          )
        : [
            for (final edge in await allTrustEdges)
              if (edgeNodeIds.contains(edge.src) &&
                  edgeNodeIds.contains(edge.dst))
                edge,
          ];
    // A contact node carries the viewer's own trust edge and nothing else:
    // trust edges only ever join visible nodes, so it has none of its own.
    final edges = contactOnlyIds.isEmpty
        ? visibleEdges
        : ([
            ...visibleEdges,
            for (final id in contactOnlyIds)
              ConstellationEdgeRecord(src: viewerId, dst: id, tier: 1),
          ]..sort(_compareEdges));

    final profileIds = {
      ...graphPeerIds,
      ...reservedPeerIds,
      ...contactOnlyIds,
      ...bondContexts.keys,
      ...temporaryBeacons.keys,
    };
    for (final request in requests) {
      profileIds.add(request.authorId);
    }
    for (final post in postFeed.posts) {
      profileIds.add(post.authorId);
    }
    for (final web in postFeed.memberWebs) {
      profileIds.add(web.personId);
    }

    final peers = [
      for (final peer in await _peerProfiles(profileIds))
        if (visibleSet.contains(peer.id))
          peer
        else if (bondContexts.containsKey(peer.id))
          peer.withPresence(
            ConstellationPeerPresence.bond,
            bondContexts: bondContexts[peer.id]!,
          )
        else if (temporaryBeacons.containsKey(peer.id))
          peer.withPresence(
            ConstellationPeerPresence.temporary,
            temporaryBeaconId: temporaryBeacons[peer.id],
          )
        else if (contactOnlyIds.contains(peer.id))
          peer.asContactOnly()
        else if (reservedPeerIds.contains(peer.id) && peer.id != viewerId)
          peer.withPresence(ConstellationPeerPresence.pinnedOnly)
        else
          peer,
    ];
    final peerIds = {for (final peer in peers) peer.id};
    final taggedPeers = await _withPeopleTags(viewerId, peers);

    return ConstellationFieldSnapshot(
      loadedAt: loadedAt,
      context: context,
      peers: taggedPeers,
      edges: edges,
      requests: requests,
      peersCapped: kept.capped,
      requestsCapped: requestsCapped,
      posts: postFeed.posts,
      memberWebs: postFeed.memberWebs,
      directContactIds: [
        for (final id in directContactIds)
          if (peerIds.contains(id)) id,
      ],
      anchorProjection: contactOnlyIds.isEmpty
          ? anchorProjection
          : _withPinnedContactNodes(anchorProjection, contactOnlyIds),
    );
  }

  /// Bond peers (people sharing a live Request with the viewer) outside
  /// [visibleSet], each with the titled Requests they share.
  Future<Map<String, List<ConstellationBondContext>>> _bondContexts(
    String viewerId,
    Set<String> visibleSet,
  ) async {
    final rows = await _database
        .customSelect(
          r'''
SELECT b.peer_id, c.beacon_id, c.title
FROM public.person_bond_peers($1) b
CROSS JOIN LATERAL public.person_shared_contexts($1, b.peer_id) c
ORDER BY b.peer_id, c.beacon_id
''',
          variables: [Variable.withString(viewerId)],
        )
        .get();
    final result = <String, List<ConstellationBondContext>>{};
    for (final row in rows) {
      final peerId = row.read<String>('peer_id');
      if (visibleSet.contains(peerId)) {
        continue;
      }
      (result[peerId] ??= []).add(
        ConstellationBondContext(
          beaconId: row.read<String>('beacon_id'),
          title: row.read<String>('title'),
        ),
      );
    }
    return result;
  }

  /// Temporarily visible peers (forward holders and authors) not in
  /// [excluding], each with the forwarded Request that explains them.
  Future<Map<String, String>> _temporaryBeacons(
    String viewerId, {
    required Set<String> excluding,
  }) async {
    final rows = await _database
        .customSelect(
          r'''
SELECT peer_id, beacon_id
FROM public.person_temporary_forward_peers($1)
ORDER BY peer_id, direction, beacon_id
''',
          variables: [Variable.withString(viewerId)],
        )
        .get();
    final result = <String, String>{};
    for (final row in rows) {
      final peerId = row.read<String>('peer_id');
      if (!excluding.contains(peerId)) {
        result.putIfAbsent(peerId, () => row.read<String>('beacon_id'));
      }
    }
    return result;
  }

  /// The forwarded Requests behind temporary peers, only those the viewer
  /// can read; the author's other Requests are not added.
  Future<List<ConstellationRequestRecord>> _temporaryRequests({
    required String viewerId,
    required Set<String> beaconIds,
    required bool showClosed,
  }) async {
    if (beaconIds.isEmpty) {
      return const [];
    }
    final statuses = constellationFieldBeaconStatuses(
      showClosed: showClosed,
    ).toList()..sort();
    final rows = await _database
        .customSelect(
          '''
SELECT $constellationRequestSelectColumns
FROM public.beacon b
LEFT JOIN public.image cover ON cover.id = b.cover_thumb_image_id
WHERE b.id IN (SELECT public.beacon_readable_ids(\$1, \$2::text[]))
  AND b.status = ANY(\$3::int[])
ORDER BY b.user_id, b.id
''',
          variables: [
            Variable.withString(viewerId),
            Variable(TypedValue(Type.textArray, beaconIds.toList()..sort())),
            Variable(TypedValue(Type.integerArray, statuses)),
          ],
        )
        .get();
    return rows.map(readConstellationRequestRow).toList(growable: false);
  }

  /// A pinned contact node is the same identity-only record as in the
  /// snapshot's peers.
  static ConstellationAnchorProjection _withPinnedContactNodes(
    ConstellationAnchorProjection projection,
    Set<String> contactOnlyIds,
  ) => ConstellationAnchorProjection(
    revision: projection.revision,
    anchors: projection.anchors,
    pinnedPeers: [
      for (final peer in projection.pinnedPeers)
        if (contactOnlyIds.contains(peer.id) && peer.pinState == null)
          peer.asContactOnly()
        else
          peer,
    ],
    pinnedRequests: projection.pinnedRequests,
    supportPeers: projection.supportPeers,
    supportEdges: projection.supportEdges,
    serverFilteredBeaconIds: projection.serverFilteredBeaconIds,
    serverFilteredBeaconCount: projection.serverFilteredBeaconCount,
  );

  static int _compareEdges(
    ConstellationEdgeRecord a,
    ConstellationEdgeRecord b,
  ) {
    final src = a.src.compareTo(b.src);
    if (src != 0) {
      return src;
    }
    final dst = a.dst.compareTo(b.dst);
    return dst != 0 ? dst : a.tier.compareTo(b.tier);
  }

  /// People the viewer trusts directly (positive explicit trust, `vote_user`,
  /// as the friends list reads it), with no block in either direction, in id
  /// order. Unlike the visible set this needs no MeritRank round trip.
  Future<List<String>> _directContactIds(String viewerId) async {
    final rows = await _database
        .customSelect(
          r'''
SELECT vu.object AS id
FROM public.vote_user vu
INNER JOIN public."user" u ON u.id = vu.object
WHERE vu.subject = $1
  AND vu.amount > 0
  AND vu.object <> $1
  AND NOT EXISTS (
    SELECT 1 FROM public.user_block ub
    WHERE (ub.blocker_id = $1 AND ub.blocked_id = vu.object)
       OR (ub.blocker_id = vu.object AND ub.blocked_id = $1)
  )
ORDER BY vu.object
''',
          variables: [Variable.withString(viewerId)],
        )
        .get();
    return [for (final row in rows) row.read<String>('id')];
  }

  ConstellationFieldRepository get _repo =>
      ConstellationFieldRepository(_database, _profiles);

  Future<List<ConstellationEdgeRecord>>? _allTrustEdges;

  final _profileById = <String, ConstellationPeerRecord?>{};

  /// Trust edges among the viewer and every visible peer, fetched at most
  /// once per snapshot, for the anchors' support closure (path resolution
  /// over the whole visible graph). A smaller node set filters it when it is
  /// already loaded: edges only ever join allowed nodes (the viewer and its
  /// visible peers), so the subset query would return exactly those rows.
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

  /// Posts the viewer authored or was admitted to (role 6), open and unexpired
  /// or pinned by the viewer (including closed Posts), plus their member webs.
  /// Members outside the viewer's visible peer set are only counted.
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
    // Pinned Requests were already checked when the anchors were read.
    final known = _anchors.pinnedBeaconReadability;
    final readable = [
      for (final e in known.entries)
        if (e.value) e.key,
    ];
    final unreadable = [
      for (final e in known.entries)
        if (!e.value) e.key,
    ];
    final postRows = await _database
        .customSelect(
          '''
SELECT
  b.id,
  b.user_id AS author_id,
  b.expires_at,
  b.status,
  COALESCE(b.last_activity_at, b.published_at, b.created_at) AS last_activity_at,
  left(COALESCE(root.body, ''), \$2::int) AS root_excerpt,
  EXISTS (
    SELECT 1 FROM public.beacon_pinned pin
    WHERE pin.beacon_id = b.id AND pin.user_id = \$1
  ) AS is_pinned
FROM public.beacon b
LEFT JOIN public.beacon_room_message root ON root.id = b.post_root_message_id
WHERE b.kind = 1
  AND b.status IN (0, 6)
  AND CASE
    WHEN b.id = ANY(\$3::text[]) THEN true
    WHEN b.id = ANY(\$4::text[]) THEN false
    ELSE ${constellationBeaconContentReadableSql(viewerParam: r'$1', beaconAlias: 'b')}
  END
  AND (
    b.user_id = \$1
    OR EXISTS (
      SELECT 1 FROM public.beacon_participant bp
      WHERE bp.beacon_id = b.id AND bp.user_id = \$1
        AND bp.role = 6 AND bp.room_access = 3
    )
  )
  AND (
    (b.status = 0 AND b.expires_at > now())
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
            Variable(TypedValue(Type.textArray, [...readable]..sort())),
            Variable(TypedValue(Type.textArray, [...unreadable]..sort())),
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
            expiresAt: readCustomSelectTimestamptz(row.data['expires_at']),
            status: row.read<int>('status'),
          ),
      ],
      memberWebs: memberWebs,
    );
  }

  /// People the viewer has not been recorded as seeing yet, from the last
  /// [read]; the caller records them after the snapshot closes.
  List<String> unseenPeerIds = const [];

  /// True when the viewer has no first-seen row at all (the backfill case).
  bool firstSeenBackfill = false;

  /// The peers kept under [kConstellationPeerCap], reserved ones aside:
  /// own-tagged > direct contacts > bond / temporary > BFS depth over the
  /// visible trust graph > id.
  Future<({Set<String> ids, bool capped})> _cappedPeerIds({
    required String viewerId,
    required String context,
    required List<String> visiblePeerIds,
    required Set<String> reservedPeerIds,
    required Set<String> directContactIds,
    required Set<String> bondPeerIds,
    required Set<String> temporaryPeerIds,
  }) async {
    final candidates = {
      for (final id in [
        ...visiblePeerIds,
        ...bondPeerIds,
        ...temporaryPeerIds,
      ])
        if (!reservedPeerIds.contains(id)) id,
    };
    if (candidates.length <= kConstellationPeerCap) {
      return (ids: candidates, capped: false);
    }

    final ownTagged = (await _ownTagIds(viewerId, candidates)).keys.toSet();
    final edges = await _trustEdges(
      viewerId: viewerId,
      context: context,
      visiblePeerIds: visiblePeerIds,
    );
    final adjacency = <String, List<String>>{};
    for (final edge in edges) {
      (adjacency[edge.src] ??= []).add(edge.dst);
      (adjacency[edge.dst] ??= []).add(edge.src);
    }
    final depth = <String, int>{viewerId: 0};
    final queue = [viewerId];
    for (var i = 0; i < queue.length; i++) {
      for (final next in adjacency[queue[i]] ?? const <String>[]) {
        if (!depth.containsKey(next)) {
          depth[next] = depth[queue[i]]! + 1;
          queue.add(next);
        }
      }
    }
    int tier(String id) => ownTagged.contains(id)
        ? 0
        : directContactIds.contains(id)
        ? 1
        : bondPeerIds.contains(id) || temporaryPeerIds.contains(id)
        ? 2
        : 3;
    final ranked = candidates.toList()
      ..sort((a, b) {
        final byTier = tier(a).compareTo(tier(b));
        if (byTier != 0) {
          return byTier;
        }
        final byDepth = (depth[a] ?? 1 << 30).compareTo(depth[b] ?? 1 << 30);
        return byDepth != 0 ? byDepth : a.compareTo(b);
      });
    return (ids: ranked.take(kConstellationPeerCap).toSet(), capped: true);
  }

  /// The viewer's own tag ids per person among [personIds].
  Future<Map<String, List<String>>> _ownTagIds(
    String viewerId,
    Iterable<String> personIds,
  ) async {
    final rows = await _database
        .customSelect(
          r'''
SELECT person_id, tag_id
FROM public.person_tag_member
WHERE owner_id = $1 AND person_id = ANY($2::text[])
ORDER BY person_id, tag_id
''',
          variables: [
            Variable.withString(viewerId),
            Variable(TypedValue(Type.textArray, personIds.toList())),
          ],
        )
        .get();
    final result = <String, List<String>>{};
    for (final row in rows) {
      (result[row.read<String>('person_id')] ??= []).add(
        row.read<String>('tag_id'),
      );
    }
    return result;
  }

  /// [peers] with the viewer's own tags, automatic tag kinds and first-seen
  /// time; also notes who has no first-seen row yet.
  Future<List<ConstellationPeerRecord>> _withPeopleTags(
    String viewerId,
    List<ConstellationPeerRecord> peers,
  ) async {
    final ids = [
      for (final peer in peers)
        if (peer.id != viewerId) peer.id,
    ];
    if (ids.isEmpty) {
      return peers;
    }
    final own = await _ownTagIds(viewerId, ids);
    final idsVariable = Variable(TypedValue(Type.textArray, ids));
    final autoRows = await _database
        .customSelect(
          r'''
SELECT peer_id, kind::int AS kind
FROM public.person_auto_tags($1, $2::text[])
ORDER BY peer_id, kind
''',
          variables: [Variable.withString(viewerId), idsVariable],
        )
        .get();
    final auto = <String, Set<int>>{};
    for (final row in autoRows) {
      (auto[row.read<String>('peer_id')] ??= {}).add(row.read<int>('kind'));
    }
    final seenRows = await _database
        .customSelect(
          r'''
SELECT peer_id,
       CASE WHEN isfinite(first_seen_at) THEN first_seen_at END AS seen_at
FROM public.person_field_first_seen
WHERE viewer_id = $1 AND peer_id = ANY($2::text[])
''',
          variables: [Variable.withString(viewerId), idsVariable],
        )
        .get();
    final seen = {
      for (final row in seenRows)
        row.read<String>('peer_id'): readCustomSelectTimestamptz(
          row.data['seen_at'],
        ),
    };
    unseenPeerIds = [
      for (final id in ids)
        if (!seen.containsKey(id)) id,
    ];
    if (unseenPeerIds.isNotEmpty) {
      firstSeenBackfill =
          !(await _database
                  .customSelect(
                    r'''
SELECT EXISTS (
  SELECT 1 FROM public.person_field_first_seen WHERE viewer_id = $1
) AS present
''',
                    variables: [Variable.withString(viewerId)],
                  )
                  .getSingle())
              .read<bool>('present');
    }
    return [
      for (final peer in peers)
        if (peer.id == viewerId)
          peer
        else
          peer.withPeopleTags(
            ownTagIds: own[peer.id] ?? const [],
            autoTagKinds: (auto[peer.id] ?? const <int>{}).toList(),
            firstSeenAt: seen[peer.id],
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
    final rows = await _database
        .customSelect(
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
        )
        .get();
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
      final candidates = await _database
          .customSelect(
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
          )
          .get();
      if (candidates.isEmpty) {
        break;
      }
      final batchIds = [for (final row in candidates) row.read<String>('id')];
      lastUserId = candidates.last.read<String>('user_id');
      lastId = batchIds.last;

      final rows = await _database
          .customSelect(
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
          )
          .get();
      eligible.addAll(rows.map(readConstellationRequestRow));
      if (candidates.length < kConstellationDiscoverableScanBatch) {
        break;
      }
    }
    return eligible.length > cap ? eligible.sublist(0, cap + 1) : eligible;
  }
}
