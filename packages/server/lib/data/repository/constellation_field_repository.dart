import 'package:drift/drift.dart' hide Column;
import 'package:injectable/injectable.dart';
import 'package:meta/meta.dart';
import 'package:postgres/postgres.dart' show Type, TypedValue;

import 'package:tentura_server/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura_server/domain/entity/constellation_field.dart';
import 'package:tentura_server/domain/entity/gql_public/image_public_record.dart';
import 'package:tentura_server/domain/port/constellation_field_repository_port.dart';
import 'package:tentura_server/domain/port/user_profile_batch_lookup_port.dart';

import '../database/tentura_db.dart';
import 'constellation_field_snapshot_reader.dart';

const constellationRequestSelectColumns = r'''
  b.id,
  b.user_id AS author_id,
  b.title,
  b.status,
  b.needs,
  b.primary_need_slug,
  b.cover_source,
  b.start_at,
  b.end_at,
  b.address_label,
  (b.lat IS NOT NULL AND b.long IS NOT NULL) AS has_coordinates,
  (b.user_id = $1) AS is_mine,
  EXISTS (
    SELECT 1 FROM public.beacon_help_offer ho
    WHERE ho.beacon_id = b.id AND ho.user_id = $1 AND ho.status = 0
  ) AS viewer_has_active_help_offer,
  EXISTS (
    SELECT 1 FROM public.beacon_participant bp
    WHERE bp.beacon_id = b.id AND bp.user_id = $1
      AND (bp.role = 1 OR bp.room_access = 3)
  ) AS viewer_is_room_participant,
  EXISTS (
    SELECT 1 FROM public.beacon_forward_edge bfe
    WHERE bfe.beacon_id = b.id AND bfe.recipient_id = $1
      AND bfe.cancelled_at IS NULL
  ) AS viewer_has_forward_edge,
  (
    SELECT COUNT(*)::int FROM public.beacon_help_offer ho
    WHERE ho.beacon_id = b.id AND ho.status = 0
  ) AS help_offer_count,
  cover.id::text AS cover_thumb_id,
  cover.hash AS cover_thumb_hash,
  cover.height AS cover_thumb_height,
  cover.width AS cover_thumb_width,
  cover.author_id AS cover_thumb_author_id,
  cover.created_at AS cover_thumb_created_at
''';

@LazySingleton(
  as: ConstellationFieldRepositoryPort,
  env: [Environment.dev, Environment.prod],
  order: 1,
)
final class ConstellationFieldRepository
    implements ConstellationFieldRepositoryPort {
  ConstellationFieldRepository(
    this._database,
    this._profiles, {
    @ignoreParam @visibleForTesting
    Future<void> Function(TenturaDb db)? snapshotOpenProbe,
  }) : _snapshotOpenProbe = snapshotOpenProbe;

  final TenturaDb _database;
  final UserProfileBatchLookup _profiles;
  final Future<void> Function(TenturaDb db)? _snapshotOpenProbe;

  @override
  Future<ConstellationFieldSnapshot> readSnapshot({
    required String viewerId,
    required String context,
    required ConstellationFieldReadParams params,
  }) {
    return _database.withReadSnapshot(
      () => ConstellationFieldSnapshotReader(
        _database,
        _profiles,
        snapshotOpenProbe: _snapshotOpenProbe,
      ).read(
        viewerId: viewerId,
        context: context,
        params: params,
      ),
    );
  }

  @override
  Future<({Set<String> ids, bool capped})> visibleGraphPeerIds({
    required String viewerId,
    required String context,
    required int cap,
  }) async {
    if (viewerId.trim().isEmpty || cap <= 0) {
      return (ids: const <String>{}, capped: false);
    }

    final rows = await _database
        .customSelect(
          r'''
SELECT s.peer_id::text AS peer_id
FROM public.person_visible_peers_symmetric($1, $2) s
WHERE NOT public.block_hides($1, s.peer_id::text)
  AND NOT public.block_hides(s.peer_id::text, $1)
ORDER BY s.peer_id
LIMIT $3
''',
          variables: [
            Variable.withString(viewerId),
            Variable.withString(context),
            Variable.withInt(cap + 1),
          ],
        )
        .get();

    final capped = rows.length > cap;
    final ids = {
      for (final row in rows.take(cap)) row.read<String>('peer_id'),
    };
    return (ids: ids, capped: capped);
  }

  @override
  Future<List<ConstellationEdgeRecord>> trustEdges({
    required String viewerId,
    required String context,
    required Set<String> nodeIds,
  }) async {
    if (viewerId.trim().isEmpty || nodeIds.isEmpty) {
      return const [];
    }

    final rows = await _database
        .customSelect(
          r'''
SELECT src, dst, tier
FROM public.constellation_trust_edges($1, $2, $3::text[])
ORDER BY src, dst, tier
''',
          variables: [
            Variable.withString(viewerId),
            Variable.withString(context),
            Variable(TypedValue(Type.textArray, nodeIds.toList()..sort())),
          ],
        )
        .get();

    return [
      for (final row in rows)
        ConstellationEdgeRecord(
          src: row.read<String>('src'),
          dst: row.read<String>('dst'),
          tier: row.read<int>('tier'),
        ),
    ];
  }

  @override
  Future<List<ConstellationRequestRecord>> ownRequests({
    required String viewerId,
  }) async {
    if (viewerId.trim().isEmpty) {
      return const [];
    }

    final rows = await _database
        .customSelect(
          '''
SELECT $constellationRequestSelectColumns
FROM public.beacon b
LEFT JOIN public.image cover ON cover.id = b.cover_thumb_image_id
WHERE b.user_id = \$1
  AND b.status IN (0, 7, 8)
  AND b.published_at IS NOT NULL
ORDER BY b.id
''',
          variables: [Variable.withString(viewerId)],
        )
        .get();

    return rows.map(readConstellationRequestRow).toList(growable: false);
  }

  @override
  Future<List<ConstellationRequestRecord>> discoverableRequests({
    required String viewerId,
    required String context,
    required int cap,
  }) async {
    if (viewerId.trim().isEmpty || cap <= 0) {
      return const [];
    }

    final rows = await _database
        .customSelect(
          '''
SELECT $constellationRequestSelectColumns
FROM public.person_visible_peers_symmetric(\$1, \$2) p
INNER JOIN public.beacon b ON b.user_id = p.peer_id::text
LEFT JOIN public.image cover ON cover.id = b.cover_thumb_image_id
WHERE b.user_id <> \$1
  AND b.is_discoverable
  AND b.status IN (0, 7, 8)
  AND b.published_at IS NOT NULL
  AND NOT public.block_hides(\$1, b.user_id)
  AND public.beacon_can_read_content(b.id, \$1)
ORDER BY b.user_id, b.id
LIMIT \$3
''',
          variables: [
            Variable.withString(viewerId),
            Variable.withString(context),
            Variable.withInt(cap + 1),
          ],
        )
        .get();

    return rows.map(readConstellationRequestRow).toList(growable: false);
  }

  @override
  Future<List<ConstellationPeerRecord>> peerProfiles({
    required Set<String> ids,
  }) async {
    if (ids.isEmpty) {
      return const [];
    }

    final sortedIds = ids.toList()..sort();
    final profiles = await _profiles.userPublicRecordsByIds(
      ids: sortedIds,
      reciprocalPeerIds: const {},
    );

    return [
      for (final id in sortedIds)
        if (profiles[id] case final profile?)
          ConstellationPeerRecord(
            id: profile.id,
            displayName: profile.displayName,
            handle: profile.handle,
            image: profile.image,
          ),
    ];
  }
}

ConstellationRequestRecord readConstellationRequestRow(
  QueryRow row, {
  bool? viewerParticipates,
}) {
  ImagePublicRecord? coverThumb;
  final coverId = row.readNullable<String>('cover_thumb_id');
  if (coverId != null) {
    coverThumb = ImagePublicRecord(
      id: coverId,
      hash: row.read<String>('cover_thumb_hash'),
      height: row.read<int>('cover_thumb_height'),
      width: row.read<int>('cover_thumb_width'),
      authorId: row.read<String>('cover_thumb_author_id'),
      createdAt: row.read<DateTime>('cover_thumb_created_at').toUtc(),
    );
  }

  final needsRaw = row.read<String>('needs');
  final needs = needsRaw.isEmpty
      ? const <String>[]
      : needsRaw.split(',').where((s) => s.isNotEmpty).toList();

  return ConstellationRequestRecord(
    id: row.read<String>('id'),
    authorId: row.read<String>('author_id'),
    title: row.read<String>('title'),
    status: row.read<int>('status'),
    needs: needs,
    primaryNeedSlug: row.readNullable<String>('primary_need_slug'),
    startAt: row.readNullable<DateTime>('start_at')?.toUtc(),
    endAt: row.readNullable<DateTime>('end_at')?.toUtc(),
    addressLabel: row.readNullable<String>('address_label'),
    hasCoordinates: row.read<bool>('has_coordinates'),
    isMine: row.read<bool>('is_mine'),
    viewerHasActiveHelpOffer: row.read<bool>('viewer_has_active_help_offer'),
    viewerIsRoomParticipant: row.read<bool>('viewer_is_room_participant'),
    viewerHasForwardEdge: row.read<bool>('viewer_has_forward_edge'),
    helpOfferCount: row.read<int>('help_offer_count'),
    coverSource: row.read<int>('cover_source'),
    coverThumb: coverThumb,
    viewerParticipates: viewerParticipates,
  );
}
