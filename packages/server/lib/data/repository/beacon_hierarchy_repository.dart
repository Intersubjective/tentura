import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';
import 'package:postgres/postgres.dart' show TypedValue, Type;
import 'package:tentura_root/domain/entity/beacon_hierarchy_capabilities.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_child_group.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_owner_summary.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_page.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_summary.dart';
import 'package:tentura_root/domain/entity/beacon_parent_reference.dart';
import 'package:tentura_root/domain/entity/beacon_promotion_source.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/consts/beacon_hierarchy_consts.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
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
    return BeaconHierarchyPolicy.resolveCapabilities(
      BeaconHierarchyCapabilityFacts(
        admission: admission,
        parentStatus: BeaconStatus.fromSmallint(parent.status),
        parentHasKnownOwner: parent.ownerId.isNotEmpty,
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
    final cursor = _decodeCursor(
      after,
      expectedParentId: parentBeaconId,
      expectedGroup: group,
    );
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

    final query =
        r'''
SELECT
  b.id,
  b.title,
  b.status,
  b.published_at,
  b.user_id,
  u.display_name
FROM public.beacon b
LEFT JOIN public."user" u ON u.id = b.user_id
WHERE b.parent_beacon_id = $1
  AND b.published_at IS NOT NULL
  AND b.status IN (''' +
        statusFilter +
        r''')
''' +
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
    final summaries = pageRows
        .map(
          (row) => BeaconHierarchySummary(
            beaconId: row.read<String>('id'),
            title: row.read<int>('status') == BeaconStatus.deleted.smallintValue
                ? null
                : row.read<String>('title'),
            owner: row.readNullable<String>('user_id') == null
                ? null
                : BeaconHierarchyOwnerSummary(
                    id: row.read<String>('user_id'),
                    displayName: row.read<String>('display_name'),
                  ),
            status: BeaconStatus.fromSmallint(row.read<int>('status')),
            publishedAt: DateTime.parse(
              row.read<String>('published_at'),
            ).toUtc(),
            isTombstone: row.read<int>('status') == BeaconStatus.deleted.smallintValue,
          ),
        )
        .toList();

    String? nextCursor;
    if (hasMore && pageRows.isNotEmpty) {
      final last = pageRows.last;
      nextCursor = _encodeCursor(
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
  Future<BeaconParentReference> loadParentReference({
    required String childBeaconId,
    required String viewerId,
  }) async {
    final parentId = await loadImmediateParentBeaconId(childBeaconId);
    if (parentId == null) {
      return BeaconParentReference.none;
    }
    final parent = await _loadBeaconRow(parentId);
    if (parent == null) {
      return BeaconParentReference.unavailable;
    }
    final parentStatus = BeaconStatus.fromSmallint(parent.status);
    final viewerAdmission = await _loadAdmissionFacts(
      beaconId: parentId,
      viewerId: viewerId,
      ownerId: parent.ownerId,
    );
    final linkedAuthorized = BeaconHierarchyPolicy.isAdmittedToImmediateParent(
      BeaconImmediateParentLinkFacts(
        parentStatus: parentStatus,
        viewerEffectivelyAdmittedToParent:
            BeaconHierarchyPolicy.hasEffectiveAdmission(viewerAdmission),
        isBlockedByParentOwner: viewerAdmission.isBlockedByOwner,
      ),
    );
    return BeaconHierarchyPolicy.resolveParentReference(
      BeaconParentReferenceFacts(
        hasParent: true,
        parentStatus: parentStatus,
        parentLinkedDetailAuthorized: linkedAuthorized,
        parentBeaconId: linkedAuthorized ? parentId : null,
        parentTitle: linkedAuthorized ? parent.title : null,
      ),
    );
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

  static String _encodeCursor({
    required String parentId,
    required BeaconHierarchyChildGroup group,
    required DateTime publishedAt,
    required String beaconId,
  }) {
    final payload = jsonEncode({
      'v': kBeaconHierarchyCursorVersion,
      'p': parentId,
      'g': group.name,
      't': publishedAt.toUtc().toIso8601String(),
      'i': beaconId,
    });
    return base64Url.encode(utf8.encode(payload)).replaceAll('=', '');
  }

  static _HierarchyCursor? _decodeCursor(
    String? after, {
    required String expectedParentId,
    required BeaconHierarchyChildGroup expectedGroup,
  }) {
    if (after == null || after.isEmpty) {
      return null;
    }
    try {
      final normalized = after.padRight(
        after.length + ((4 - after.length % 4) % 4),
        '=',
      );
      final decoded = utf8.decode(base64Url.decode(normalized));
      final map = jsonDecode(decoded) as Map<String, dynamic>;
      if (map['v'] != kBeaconHierarchyCursorVersion) {
        throw const FormatException('cursor version');
      }
      if (map['p'] != expectedParentId) {
        throw const FormatException('cursor parent');
      }
      if (map['g'] != expectedGroup.name) {
        throw const FormatException('cursor group');
      }
      return _HierarchyCursor(
        publishedAt: DateTime.parse(map['t'] as String),
        beaconId: map['i'] as String,
      );
    } on Object {
      throw const UnspecifiedException(
        description: 'BEACON_HIERARCHY_CURSOR_INVALID',
      );
    }
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

final class _HierarchyCursor {
  const _HierarchyCursor({
    required this.publishedAt,
    required this.beaconId,
  });

  final DateTime publishedAt;
  final String beaconId;
}
