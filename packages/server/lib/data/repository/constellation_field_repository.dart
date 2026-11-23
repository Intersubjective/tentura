import 'dart:async';

import 'package:drift_postgres/drift_postgres.dart';
import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:postgres/postgres.dart' show Type, TypedValue;

import 'package:tentura_server/domain/constellation/constellation_field_selection.dart';
import 'package:tentura_server/domain/entity/constellation_field.dart';
import 'package:tentura_server/domain/entity/gql_public/image_public_record.dart';
import 'package:tentura_server/domain/port/constellation_db_admission_port.dart';
import 'package:tentura_server/domain/port/constellation_field_repository_port.dart';
import 'package:tentura_server/domain/port/user_profile_batch_lookup_port.dart';
import 'package:tentura_server/domain/request_context.dart';

import '../database/tentura_db.dart';
import 'constellation_field_snapshot_reader.dart';
import 'constellation_new_people_repository.dart';
import 'room_unread_sql.dart';

/// Effective activity of beacon alias `b` in Field reads.
const constellationLastActivitySql =
    'COALESCE(b.last_activity_at, b.published_at, b.created_at)';

/// Columns of one [ConstellationRequestRecord] row; `$1` is the viewer.
/// `parent_beacon_id` is set only when the parent is a Post the viewer can
/// read (budding C8, Arch §8.2).
final constellationRequestSelectColumns = _constellationRequestSelectColumns();
final constellationPinnedItemSelectColumns = _constellationRequestSelectColumns(
  includePosts: true,
);

/// Both cover images for the selected Request alias `b`.
const constellationRequestCoverJoins = '''
LEFT JOIN public.image cover ON cover.id = b.cover_thumb_image_id
LEFT JOIN public.beacon_image gallery_link
  ON gallery_link.beacon_id = b.id AND gallery_link.image_id = b.cover_image_id
LEFT JOIN public.image gallery_cover ON gallery_cover.id = gallery_link.image_id''';

String _constellationRequestSelectColumns({bool includePosts = false}) =>
    '''
  b.id,
  b.user_id AS author_id,
  b.title,
  b.status,
  b.kind,
  $constellationLastActivitySql AS last_activity_at,
  ${fieldHasUnreadSql(includePosts: includePosts)} AS has_unread,
  b.needs,
  b.primary_need_slug,
  b.cover_source,
  b.start_at,
  b.end_at,
  b.address_label,
  (b.lat IS NOT NULL AND b.long IS NOT NULL) AS has_coordinates,
  (b.user_id = \$1) AS is_mine,
  EXISTS (
    SELECT 1 FROM public.beacon_help_offer ho
    WHERE ho.beacon_id = b.id AND ho.user_id = \$1 AND ho.status = 0
  ) AS viewer_has_active_help_offer,
  EXISTS (
    SELECT 1 FROM public.beacon_participant bp
    WHERE bp.beacon_id = b.id AND bp.user_id = \$1
      AND (bp.role = 1 OR bp.room_access = 3)
  ) AS viewer_is_room_participant,
  EXISTS (
    SELECT 1 FROM public.beacon_forward_edge bfe
    WHERE bfe.beacon_id = b.id AND bfe.recipient_id = \$1
      AND bfe.cancelled_at IS NULL
  ) AS viewer_has_forward_edge,
  (
    SELECT ARRAY[e.sender_id, sender.display_name]
    FROM public.beacon_forward_edge e
    JOIN public."user" sender ON sender.id = e.sender_id
    WHERE e.beacon_id = b.id AND e.recipient_id = \$1
      AND e.cancelled_at IS NULL
    ORDER BY e.created_at DESC, e.id DESC
    LIMIT 1
  ) AS forwarded_by,
  (
    SELECT COUNT(*)::int FROM public.beacon_help_offer ho
    WHERE ho.beacon_id = b.id AND ho.status = 0
  ) AS help_offer_count,
  cover.id::text AS cover_thumb_id,
  cover.hash AS cover_thumb_hash,
  cover.height AS cover_thumb_height,
  cover.width AS cover_thumb_width,
  cover.author_id AS cover_thumb_author_id,
  cover.created_at AS cover_thumb_created_at,
  gallery_cover.id::text AS gallery_cover_id,
  gallery_cover.hash AS gallery_cover_hash,
  gallery_cover.height AS gallery_cover_height,
  gallery_cover.width AS gallery_cover_width,
  gallery_cover.author_id AS gallery_cover_author_id,
  gallery_cover.created_at AS gallery_cover_created_at,
  (
    SELECT parent.id FROM public.beacon parent
    WHERE parent.id = b.parent_beacon_id
      AND parent.kind = 1
      AND ${constellationBeaconContentReadableSql(viewerParam: r'$1', beaconAlias: 'parent')}
  ) AS parent_beacon_id
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
    @ignoreParam @visibleForTesting this._snapshotOpenProbe,
  });

  @FactoryMethod()
  ConstellationFieldRepository.injected(
    this._database,
    this._profiles, [
    @ignoreParam ConstellationDbAdmissionPort? _,
  ]) : _snapshotOpenProbe = null;

  static final _log = Logger('ConstellationFieldRepository');
  final TenturaDb _database;
  final UserProfileBatchLookup _profiles;
  late final _newPeople = ConstellationNewPeopleRepository(_database);
  final Future<void> Function(TenturaDb db)? _snapshotOpenProbe;

  @override
  Future<ConstellationFieldSnapshot> readSnapshot({
    required String viewerId,
    required String context,
    required ConstellationFieldReadParams params,
  }) async {
    final reader = ConstellationFieldSnapshotReader(
      _database,
      _profiles,
      snapshotOpenProbe: _snapshotOpenProbe,
    );
    final snapshot = await _database.withConnectionScope(
      () => _readSnapshotInTx(reader, viewerId, context, params),
      actorUserId: viewerId,
      kind: MainDbWorkKind.full,
    );
    if (reader.unseenPeerIds.isNotEmpty) {
      await _recordFirstSeen(viewerId, reader);
    }
    return snapshot;
  }

  Future<void> _recordFirstSeen(
    String viewerId,
    ConstellationFieldSnapshotReader reader,
  ) async {
    // Keep the uncontended write synchronous. If the viewer's scope is held,
    // return the snapshot while the same write waits in its own transaction.
    final waiting = Completer<void>();
    Future<void> write() => _newPeople.recordFirstSeen(
      viewerId: viewerId,
      peerIds: reader.unseenPeerIds,
      backfill: reader.firstSeenBackfill,
      onScopeWait: () {
        if (!waiting.isCompleted) waiting.complete();
      },
    );

    // A deferred write can outlive the HTTP response and its cancellation.
    final request = RequestContext.current;
    request?.check();
    final writeContext = request == null
        ? null
        : (RequestContext(requestId: request.requestId)..actor = viewerId);
    final recorded = writeContext == null
        ? write()
        : writeContext.run(write).whenComplete(writeContext.dispose);
    await Future.any([
      waiting.future,
      recorded.onError<Object>((error, stackTrace) {
        if (!waiting.isCompleted) {
          Error.throwWithStackTrace(error, stackTrace);
        }
        _log.warning(
          'Deferred Field first-seen write failed',
          error,
          stackTrace,
        );
      }),
    ]);
  }

  Future<ConstellationFieldSnapshot> _readSnapshotInTx(
    ConstellationFieldSnapshotReader reader,
    String viewerId,
    String context,
    ConstellationFieldReadParams params,
  ) async {
    // The snapshot is READ ONLY, so it can serve the stored visible set but
    // not fill it: store it first, in its own transaction (m0235).
    await _database
        .customSelect(
          'SELECT public.person_visible_peer_ids_tx(\$1, \$2) AS ids',
          variables: [
            Variable.withString(viewerId),
            Variable.withString(context),
          ],
        )
        .get();
    return _database.withReadSnapshot(() async {
      await _database.freezeVisibilityMemo();
      return reader.read(
        viewerId: viewerId,
        context: context,
        params: params,
      );
    });
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
$constellationRequestCoverJoins
WHERE b.user_id = \$1
  AND b.kind = 0
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
$constellationRequestCoverJoins
WHERE b.user_id <> \$1
  AND b.is_discoverable
  AND b.kind = 0
  AND b.status IN (0, 7, 8)
  AND ${constellationBeaconContentReadableSql(viewerParam: r'$1', beaconAlias: 'b')}
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
    final profiles = await _profiles.constellationProfilesByIds(sortedIds);

    return [
      for (final id in sortedIds) ?profiles[id],
    ];
  }
}

/// Drift's `read<DateTime>` treats customSelect `timestamptz` as unix seconds
/// and `int.parse`s the driver's `DateTime.toString()` (`yyyy-mm-dd hh:mm:ss.mmmZ`).
DateTime? readCustomSelectTimestamptz(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is DateTime) {
    return value.toUtc();
  }
  if (value is PgDateTime) {
    return value.dateTime.toUtc();
  }
  return DateTime.parse(value.toString()).toUtc();
}

ConstellationRequestRecord readConstellationRequestRow(
  QueryRow row, {
  bool? viewerParticipates,
  String? pinState,
}) {
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
    startAt: readCustomSelectTimestamptz(row.data['start_at']),
    endAt: readCustomSelectTimestamptz(row.data['end_at']),
    addressLabel: row.readNullable<String>('address_label'),
    hasCoordinates: row.read<bool>('has_coordinates'),
    isMine: row.read<bool>('is_mine'),
    viewerHasActiveHelpOffer: row.read<bool>('viewer_has_active_help_offer'),
    viewerIsRoomParticipant: row.read<bool>('viewer_is_room_participant'),
    viewerHasForwardEdge: row.read<bool>('viewer_has_forward_edge'),
    forwardedBy: switch (row.data['forwarded_by']) {
      [final String id, final String? displayName] => (
        id: id,
        displayName: displayName,
      ),
      null => null,
      _ => throw const FormatException('Invalid incoming-forward sender'),
    },
    helpOfferCount: row.read<int>('help_offer_count'),
    kind: row.read<int>('kind'),
    hasUnread: row.read<bool>('has_unread'),
    lastActivityAt: readCustomSelectTimestamptz(row.data['last_activity_at']),
    coverSource: row.read<int>('cover_source'),
    coverThumb: _readRequestCover(row, 'cover_thumb'),
    coverImage: _readRequestCover(row, 'gallery_cover'),
    viewerParticipates: viewerParticipates,
    pinState: pinState,
    parentBeaconId: row.readNullable<String>('parent_beacon_id'),
  );
}

ImagePublicRecord? _readRequestCover(QueryRow row, String prefix) {
  final id = row.readNullable<String>('${prefix}_id');
  if (id == null) return null;
  return ImagePublicRecord(
    id: id,
    hash: row.read<String>('${prefix}_hash'),
    height: row.read<int>('${prefix}_height'),
    width: row.read<int>('${prefix}_width'),
    authorId: row.read<String>('${prefix}_author_id'),
    createdAt:
        readCustomSelectTimestamptz(row.data['${prefix}_created_at']) ??
        (throw const FormatException(
          'Request cover image has no creation time',
        )),
  );
}
