import 'package:injectable/injectable.dart';
import 'package:postgres/postgres.dart' show TypedValue, Type;
import 'package:tentura_root/domain/entity/beacon_cover_source.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_capabilities.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_child_group.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_owner_summary.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_page.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_summary.dart';
import 'package:tentura_root/domain/entity/beacon_parent_reference.dart';
import 'package:tentura_root/domain/entity/beacon_promotion_source.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/domain/beacon_hierarchy_cursor.dart';
import 'package:tentura_server/domain/entity/beacon_structural_record.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/policy/beacon_hierarchy_policy.dart';
import 'package:tentura_server/domain/port/beacon_hierarchy_repository_port.dart';

import '../database/tentura_db.dart';

@Singleton(as: BeaconHierarchyRepositoryPort)
class BeaconHierarchyRepository implements BeaconHierarchyRepositoryPort {
  const BeaconHierarchyRepository(this._database);

  final TenturaDb _database;

  static const _mutationScopeKey = 'tentura.beacon_hierarchy.v1';

  @override
  Future<void> lockMutationScope() => _database.customStatement(
    r"SELECT pg_advisory_xact_lock(hashtextextended($1, 0))",
    [_mutationScopeKey],
  );

  @override
  Future<BeaconHierarchyCapabilities> loadCapabilities({
    required String parentBeaconId,
    required String viewerId,
  }) async {
    final parent = await _loadBeaconRow(parentBeaconId);
    if (parent == null) {
      return const BeaconHierarchyCapabilities(
        canListChildren: false,
        canCreateChild: false,
      );
    }
    final admission = await _loadAdmissionFacts(
      beaconId: parentBeaconId,
      viewerId: viewerId,
      ownerId: parent.ownerId,
    );
    final viewerCanReadParentContent = await _predicate(
      'beacon_can_read_content',
      parentBeaconId,
      viewerId,
    );
    return BeaconHierarchyPolicy.resolveCapabilities(
      BeaconHierarchyCapabilityFacts(
        admission: admission,
        parentStatus: BeaconStatus.fromSmallint(parent.status),
        parentHasKnownOwner: parent.ownerId.isNotEmpty,
        viewerCanReadParentContent: viewerCanReadParentContent,
      ),
    );
  }

  @override
  Future<BeaconHierarchyPage> listChildren({
    required String parentBeaconId,
    required String viewerId,
    required BeaconHierarchyChildGroup group,
    required int first,
    String? after,
  }) async {
    final cursor = decodeBeaconHierarchyCursor(
      after,
      expectedParentId: parentBeaconId,
      expectedGroup: group,
    );
    final parentReadable = await _database
        .customSelect(
          r'SELECT public.beacon_can_read_content($1, $2) AS allowed',
          variables: [
            Variable<String>(parentBeaconId),
            Variable<String>(viewerId),
          ],
        )
        .getSingle();
    if (!parentReadable.read<bool>('allowed')) {
      return const BeaconHierarchyPage(summaries: []);
    }

    final statusFilter = _statusSqlForGroup(group);
    final variables = <Variable>[
      Variable<String>(parentBeaconId),
      Variable<int>(first + 1),
    ];
    var cursorSql = '';
    if (cursor != null) {
      cursorSql = r'''
  AND (b.published_at < $3::timestamptz
    OR (b.published_at = $3::timestamptz AND b.id < $4))
''';
      variables.addAll([
        Variable(TypedValue(Type.timestampTz, cursor.publishedAt.toUtc())),
        Variable<String>(cursor.beaconId),
      ]);
    }
    variables.add(Variable<String>(viewerId));
    final viewer = '\$${variables.length}';
    // Deleted children are unreadable on their own; admitted parent viewers
    // still see the tombstone.
    final visibilitySql =
        '''
  AND NOT public.block_hides(b.user_id, $viewer)
  AND (
    (b.status <> 2 AND public.beacon_can_read_content(b.id, $viewer))
    OR (b.status = 2 AND public.beacon_effective_admission(\$1, $viewer))
  )
''';

    final query =
        r'''
SELECT
  b.id,
  b.title,
  b.description,
  b.status,
  b.published_at,
  b.status_changed_at,
  b.user_id,
  u.display_name,
  u.image_id::text AS avatar_image_id,
  b.cover_source,
  b.cover_image_id::text AS cover_image_id,
  b.cover_thumb_image_id::text AS cover_thumb_image_id,
  b.primary_need_slug,
  b.needs
FROM public.beacon b
LEFT JOIN public."user" u ON u.id = b.user_id
WHERE b.parent_beacon_id = $1
  AND b.published_at IS NOT NULL
  AND b.status IN (''' +
        statusFilter +
        r''')
''' +
        visibilitySql +
        cursorSql +
        r'''
ORDER BY b.published_at DESC, b.id DESC
LIMIT $2
''';

    final rows = await _database
        .customSelect(
          query,
          variables: variables,
        )
        .get();

    final hasMore = rows.length > first;
    final pageRows = hasMore ? rows.sublist(0, first) : rows;
    final helpersByBeacon = await _loadAdmittedHelperPreviews(
      pageRows
          .where(
            (row) =>
                row.read<int>('status') != BeaconStatus.deleted.smallintValue,
          )
          .map((row) => row.read<String>('id'))
          .toList(growable: false),
    );
    final summaries = pageRows
        .map((row) => _mapChildSummaryRow(row, helpersByBeacon))
        .toList();

    String? nextCursor;
    if (hasMore && pageRows.isNotEmpty) {
      final last = pageRows.last;
      nextCursor = encodeBeaconHierarchyCursor(
        parentId: parentBeaconId,
        group: group,
        publishedAt: DateTime.parse(
          last.read<String>('published_at'),
        ).toUtc(),
        beaconId: last.read<String>('id'),
      );
    }

    return BeaconHierarchyPage(summaries: summaries, nextCursor: nextCursor);
  }

  @override
  Future<BeaconHierarchySummary?> loadChildPreview({
    required String beaconId,
    required String viewerId,
  }) async {
    if (!await _predicate('beacon_can_read_content', beaconId, viewerId)) {
      return null;
    }
    final rows = await _database
        .customSelect(
          r'''
SELECT
  b.id,
  b.title,
  b.description,
  b.status,
  b.published_at,
  b.status_changed_at,
  b.user_id,
  u.display_name,
  u.image_id::text AS avatar_image_id,
  b.cover_source,
  b.cover_image_id::text AS cover_image_id,
  b.cover_thumb_image_id::text AS cover_thumb_image_id,
  b.primary_need_slug,
  b.needs
FROM public.beacon b
LEFT JOIN public."user" u ON u.id = b.user_id
WHERE b.id = $1
  AND b.published_at IS NOT NULL
  AND NOT public.block_hides(b.user_id, $2)
''',
          variables: [
            Variable<String>(beaconId),
            Variable<String>(viewerId),
          ],
        )
        .get();
    if (rows.isEmpty) {
      return null;
    }
    final row = rows.single;
    final isTombstone =
        row.read<int>('status') == BeaconStatus.deleted.smallintValue;
    if (isTombstone) {
      // Tombstones are list-only; single-id preview stays non-leaking.
      return null;
    }
    final helpersByBeacon = await _loadAdmittedHelperPreviews([beaconId]);
    return _mapChildSummaryRow(row, helpersByBeacon);
  }

  @override
  Future<BeaconParentReference> loadParentReference({
    required String childBeaconId,
    required String viewerId,
  }) async {
    // A viewer who cannot read the child learns nothing about its parent.
    if (!await _predicate(
      'beacon_can_read_content',
      childBeaconId,
      viewerId,
    )) {
      return BeaconParentReference.none;
    }
    final parentId = await loadImmediateParentBeaconId(childBeaconId);
    if (parentId == null) {
      return BeaconParentReference.none;
    }
    final parent = await _loadBeaconRow(parentId);
    if (parent == null ||
        BeaconStatus.fromSmallint(parent.status) == BeaconStatus.deleted) {
      return BeaconParentReference.unavailable;
    }
    if (await _predicate('beacon_can_read_content', parentId, viewerId)) {
      return BeaconParentReference(
        state: BeaconParentReferenceState.available,
        beaconId: parentId,
        title: parent.title,
      );
    }
    return BeaconParentReference.unavailable;
  }

  @override
  Future<BeaconPromotionSource> loadPromotionSource({
    required String parentBeaconId,
    required String sourceMessageId,
    required String viewerId,
  }) async {
    final rows = await _database
        .customSelect(
          r'''
SELECT
  m.id,
  m.beacon_id,
  m.body,
  m.author_id,
  u.display_name
FROM public.beacon_room_message m
LEFT JOIN public."user" u ON u.id = m.author_id
WHERE m.id = $1
  AND m.beacon_id = $2
  AND m.thread_item_id IS NULL
''',
          variables: [
            Variable<String>(sourceMessageId),
            Variable<String>(parentBeaconId),
          ],
        )
        .get();
    if (rows.isEmpty) {
      throw IdNotFoundException(id: sourceMessageId);
    }
    final row = rows.single;
    final authorId = row.readNullable<String>('author_id');
    return BeaconPromotionSource(
      sourceBeaconId: row.read<String>('beacon_id'),
      sourceMessageId: row.read<String>('id'),
      textPreview: row.read<String>('body'),
      author: authorId == null
          ? const BeaconHierarchyOwnerSummary(id: '', displayName: '')
          : BeaconHierarchyOwnerSummary(
              id: authorId,
              displayName: row.read<String>('display_name'),
            ),
    );
  }

  @override
  Future<BeaconStatus?> loadBeaconStatus(String beaconId) async {
    final row = await _loadBeaconRow(beaconId);
    return row == null ? null : BeaconStatus.fromSmallint(row.status);
  }

  @override
  Future<String?> loadImmediateParentBeaconId(String childBeaconId) async {
    final rows = await _database
        .customSelect(
          r'''
SELECT parent_beacon_id
FROM public.beacon
WHERE id = $1
''',
          variables: [Variable<String>(childBeaconId)],
        )
        .get();
    if (rows.isEmpty) {
      return null;
    }
    return rows.single.readNullable<String>('parent_beacon_id');
  }

  @override
  Future<BeaconStructuralRecord?> loadStructuralRecord(String beaconId) async {
    final rows = await _database.customSelect(
      r'''
SELECT id, status, parent_beacon_id, published_at
FROM public.beacon
WHERE id = $1
''',
      variables: [Variable<String>(beaconId)],
    ).get();
    if (rows.isEmpty) {
      return null;
    }
    final row = rows.single;
    final status = BeaconStatus.fromSmallint(row.read<int>('status'));
    return BeaconStructuralRecord(
      beaconId: row.read<String>('id'),
      status: status,
      isTombstone: status == BeaconStatus.deleted,
      parentBeaconId: row.readNullable<String>('parent_beacon_id'),
      publishedAt: row.readNullable<String>('published_at') == null
          ? null
          : DateTime.parse(row.read<String>('published_at')).toUtc(),
    );
  }

  Future<_BeaconRow?> _loadBeaconRow(String beaconId) async {
    final rows = await _database
        .customSelect(
          r'''
SELECT id, user_id, title, status
FROM public.beacon
WHERE id = $1
''',
          variables: [Variable<String>(beaconId)],
        )
        .get();
    if (rows.isEmpty) {
      return null;
    }
    final row = rows.single;
    return _BeaconRow(
      id: row.read<String>('id'),
      ownerId: row.readNullable<String>('user_id') ?? '',
      title: row.read<String>('title'),
      status: row.read<int>('status'),
    );
  }

  Future<bool> _predicate(
    String functionName,
    String beaconId,
    String viewerId,
  ) async {
    final row = await _database
        .customSelect(
          'SELECT public.$functionName(\$1, \$2) AS allowed',
          variables: [
            Variable<String>(beaconId),
            Variable<String>(viewerId),
          ],
        )
        .getSingle();
    return row.read<bool>('allowed');
  }

  Future<BeaconEffectiveAdmissionFacts> _loadAdmissionFacts({
    required String beaconId,
    required String viewerId,
    required String ownerId,
  }) async {
    final rows = await _database
        .customSelect(
          r'''
SELECT
  EXISTS (
    SELECT 1 FROM public.beacon_participant p
    WHERE p.beacon_id = $1
      AND p.user_id = $2
      AND p.room_access = $3
  ) AS admitted,
  EXISTS (
    SELECT 1 FROM public.beacon_participant p
    WHERE p.beacon_id = $1
      AND p.user_id = $2
      AND p.role = $4
  ) AS steward
''',
          variables: [
            Variable<String>(beaconId),
            Variable<String>(viewerId),
            Variable<int>(RoomAccessBits.admitted),
            Variable<int>(BeaconParticipantRoleBits.steward),
          ],
        )
        .get();
    final row = rows.single;
    final isAuthor = ownerId == viewerId;
    return BeaconEffectiveAdmissionFacts(
      isAuthor: isAuthor,
      isSteward: row.read<bool>('steward'),
      isAdmittedParticipant: row.read<bool>('admitted'),
      isBlockedByOwner: false,
    );
  }

  static String _statusSqlForGroup(BeaconHierarchyChildGroup group) =>
      switch (group) {
        BeaconHierarchyChildGroup.active => '0, 5, 7, 8',
        BeaconHierarchyChildGroup.finished => '1, 6',
        BeaconHierarchyChildGroup.deleted => '2',
      };

  BeaconHierarchySummary _mapChildSummaryRow(
    QueryRow row,
    Map<String, _AdmittedHelperBatch> helpersByBeacon,
  ) {
    final status = BeaconStatus.fromSmallint(row.read<int>('status'));
    final isTombstone = status == BeaconStatus.deleted;
    if (isTombstone) {
      return BeaconHierarchySummary(
        beaconId: row.read<String>('id'),
        status: status,
        publishedAt: DateTime.parse(row.read<String>('published_at')).toUtc(),
        isTombstone: true,
      );
    }

    final needsRaw = row.readNullable<String>('needs') ?? '';
    final needs = {
      if (needsRaw.isNotEmpty) ...needsRaw.split(','),
    };
    final helpers = helpersByBeacon[row.read<String>('id')];
    final ownerId = row.readNullable<String>('user_id');
    return BeaconHierarchySummary(
      beaconId: row.read<String>('id'),
      title: row.read<String>('title'),
      description: row.readNullable<String>('description'),
      owner: ownerId == null
          ? null
          : BeaconHierarchyOwnerSummary(
              id: ownerId,
              displayName: row.read<String>('display_name'),
              avatarImageId: row.readNullable<String>('avatar_image_id'),
            ),
      status: status,
      publishedAt: DateTime.parse(row.read<String>('published_at')).toUtc(),
      isTombstone: false,
      coverSource: BeaconCoverSource.fromWireOrPhoto(
        row.readNullable<int>('cover_source'),
      ),
      coverImageId: row.readNullable<String>('cover_image_id'),
      coverThumbImageId: row.readNullable<String>('cover_thumb_image_id'),
      primaryNeedSlug: row.readNullable<String>('primary_need_slug'),
      needs: needs,
      statusChangedAt: row.readNullable<String>('status_changed_at') == null
          ? null
          : DateTime.parse(row.read<String>('status_changed_at')).toUtc(),
      admittedHelperPreviews: helpers?.previews ?? const [],
      admittedHelperCount: helpers?.totalCount ?? 0,
    );
  }

  /// Batch-load admitted helpers for a page of child ids (author excluded).
  Future<Map<String, _AdmittedHelperBatch>> _loadAdmittedHelperPreviews(
    List<String> beaconIds,
  ) async {
    if (beaconIds.isEmpty) {
      return const {};
    }
    final countRows = await _database
        .customSelect(
          r'''
SELECT h.beacon_id, COUNT(*)::int AS total
FROM public.beacon_admitted_helper h
WHERE h.beacon_id = ANY($1)
GROUP BY h.beacon_id
''',
          variables: [
            Variable(TypedValue(Type.textArray, beaconIds)),
          ],
        )
        .get();
    final totals = <String, int>{
      for (final row in countRows)
        row.read<String>('beacon_id'): row.read<int>('total'),
    };

    final previewRows = await _database
        .customSelect(
          r'''
SELECT
  ranked.beacon_id,
  ranked.user_id,
  ranked.display_name,
  ranked.avatar_image_id
FROM (
  SELECT
    h.beacon_id,
    h.user_id,
    u.display_name,
    u.image_id::text AS avatar_image_id,
    ROW_NUMBER() OVER (
      PARTITION BY h.beacon_id
      ORDER BY h.user_id ASC
    ) AS rn
  FROM public.beacon_admitted_helper h
  JOIN public."user" u ON u.id = h.user_id
  WHERE h.beacon_id = ANY($1)
) ranked
WHERE ranked.rn <= 3
ORDER BY ranked.beacon_id, ranked.user_id
''',
          variables: [
            Variable(TypedValue(Type.textArray, beaconIds)),
          ],
        )
        .get();

    final previews = <String, List<BeaconHierarchyOwnerSummary>>{};
    for (final row in previewRows) {
      final beaconId = row.read<String>('beacon_id');
      previews
          .putIfAbsent(beaconId, () => <BeaconHierarchyOwnerSummary>[])
          .add(
            BeaconHierarchyOwnerSummary(
              id: row.read<String>('user_id'),
              displayName: row.read<String>('display_name'),
              avatarImageId: row.readNullable<String>('avatar_image_id'),
            ),
          );
    }

    return {
      for (final id in beaconIds)
        id: _AdmittedHelperBatch(
          previews: previews[id] ?? const [],
          totalCount: totals[id] ?? 0,
        ),
    };
  }
}

final class _BeaconRow {
  const _BeaconRow({
    required this.id,
    required this.ownerId,
    required this.title,
    required this.status,
  });

  final String id;
  final String ownerId;
  final String title;
  final int status;
}

final class _AdmittedHelperBatch {
  const _AdmittedHelperBatch({
    required this.previews,
    required this.totalCount,
  });

  final List<BeaconHierarchyOwnerSummary> previews;
  final int totalCount;
}
