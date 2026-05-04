import 'package:injectable/injectable.dart';
import 'package:postgres/postgres.dart' show Type, TypedValue;

import 'package:tentura_server/domain/capability/capability_event_source.dart';
import 'package:tentura_server/domain/capability/capability_event_visibility.dart';
import 'package:tentura_server/domain/port/person_capability_event_repository_port.dart';
import 'package:tentura_server/utils/id.dart';

import '../database/tentura_db.dart';

@Injectable(
  as: PersonCapabilityEventRepositoryPort,
  env: [Environment.dev, Environment.prod],
  order: 1,
)
class PersonCapabilityEventRepository
    implements PersonCapabilityEventRepositoryPort {
  const PersonCapabilityEventRepository(this._database);

  final TenturaDb _database;

  @override
  Future<void> upsertPrivateLabels({
    required String observerId,
    required String subjectId,
    required List<String> slugs,
  }) => _database.withMutatingUser(observerId, () async {
    // Soft-delete slugs no longer in the set
    await _database.customStatement(
      r'''
      UPDATE public.person_capability_event
      SET deleted_at = now()
      WHERE observer_user_id = $1
        AND subject_user_id  = $2
        AND source_type = $3
        AND deleted_at IS NULL
        AND NOT (tag_slug = ANY($4::text[]))
      ''',
      [
        observerId,
        subjectId,
        CapabilityEventSource.privateLabel.dbValue,
        TypedValue(Type.textArray, slugs),
      ],
    );

    // Insert new slugs (conflict on pce_private_label_uq → ignore)
    for (final slug in slugs) {
      await _database.customStatement(
        r'''
        INSERT INTO public.person_capability_event
          (id, subject_user_id, observer_user_id, tag_slug, source_type, visibility)
        VALUES ($1, $2, $3, $4, $5, $6)
        ON CONFLICT DO NOTHING
        ''',
        [
          generateId('CE'),
          subjectId,
          observerId,
          slug,
          CapabilityEventSource.privateLabel.dbValue,
          CapabilityEventVisibility.private.dbValue,
        ],
      );
    }
  });

  @override
  Future<List<String>> fetchPrivateLabels({
    required String observerId,
    required String subjectId,
  }) => _database
      .customSelect(
        r'''
        SELECT tag_slug FROM public.person_capability_event
        WHERE observer_user_id = $1
          AND subject_user_id  = $2
          AND source_type = $3
          AND deleted_at IS NULL
        ORDER BY tag_slug
        ''',
        variables: [
          Variable.withString(observerId),
          Variable.withString(subjectId),
          Variable.withInt(CapabilityEventSource.privateLabel.dbValue),
        ],
      )
      .get()
      .then((rows) => rows.map((r) => r.read<String>('tag_slug')).toList());

  @override
  Future<void> insertForwardReasons({
    required String observerId,
    required String subjectId,
    required String beaconId,
    required List<String> slugs,
    String note = '',
  }) => _database.withMutatingUser(observerId, () async {
    for (final slug in slugs) {
      await _database.customStatement(
        r'''
        INSERT INTO public.person_capability_event
          (id, subject_user_id, observer_user_id, tag_slug, source_type,
           beacon_id, visibility, note)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
        ''',
        [
          generateId('CE'),
          subjectId,
          observerId,
          slug,
          CapabilityEventSource.forwardReason.dbValue,
          beaconId,
          CapabilityEventVisibility.private.dbValue,
          note,
        ],
      );
      // A new positive forward signal lifts any tombstone the observer placed
      // on this slug for this subject.
      await _database.customStatement(
        r'''
        UPDATE public.person_capability_event
        SET deleted_at = now()
        WHERE observer_user_id = $1
          AND subject_user_id  = $2
          AND tag_slug         = $3
          AND is_negative      = true
          AND deleted_at IS NULL
        ''',
        [observerId, subjectId, slug],
      );
    }
  });

  @override
  Future<void> insertCommitRole({
    required String observerId,
    required String subjectId,
    required String beaconId,
    required String slug,
  }) => _database.withMutatingUser(observerId, () async {
    await _database.customStatement(
      r'''
      INSERT INTO public.person_capability_event
        (id, subject_user_id, observer_user_id, tag_slug, source_type,
         beacon_id, visibility)
      VALUES ($1, $2, $3, $4, $5, $6, $7)
      ON CONFLICT DO NOTHING
      ''',
      [
        generateId('CE'),
        subjectId,
        observerId,
        slug,
        CapabilityEventSource.commitRole.dbValue,
        beaconId,
        CapabilityEventVisibility.beaconScoped.dbValue,
      ],
    );
  });

  @override
  Future<void> insertCloseAcknowledgements({
    required String observerId,
    required String subjectId,
    required String beaconId,
    required List<String> slugs,
  }) => _database.withMutatingUser(observerId, () async {
    for (final slug in slugs) {
      await _database.customStatement(
        r'''
        INSERT INTO public.person_capability_event
          (id, subject_user_id, observer_user_id, tag_slug, source_type,
           beacon_id, visibility)
        VALUES ($1, $2, $3, $4, $5, $6, $7)
        ''',
        [
          generateId('CE'),
          subjectId,
          observerId,
          slug,
          CapabilityEventSource.closeAcknowledgement.dbValue,
          beaconId,
          CapabilityEventVisibility.beaconScoped.dbValue,
        ],
      );
    }
  });

  @override
  Future<PersonCapabilityCuesRow> fetchCues({
    required String viewerId,
    required String subjectId,
  }) async {
    // Private labels: only rows where viewer is the observer (never self-label)
    final privateLabelRows = await _database
        .customSelect(
          r'''
          SELECT tag_slug FROM public.person_capability_event
          WHERE observer_user_id = $1
            AND subject_user_id  = $2
            AND source_type = $3
            AND deleted_at IS NULL
          ORDER BY tag_slug
          ''',
          variables: [
            Variable.withString(viewerId),
            Variable.withString(subjectId),
            Variable.withInt(CapabilityEventSource.privateLabel.dbValue),
          ],
        )
        .get();
    final privateLabels =
        privateLabelRows.map((r) => r.read<String>('tag_slug')).toList();

    // Forward reasons by viewer about subject
    final forwardRows = await _database
        .customSelect(
          r'''
          SELECT tag_slug,
                 COUNT(*)::int AS cnt,
                 MAX(created_at)::text AS last_seen
          FROM public.person_capability_event
          WHERE observer_user_id = $1
            AND subject_user_id  = $2
            AND source_type = $3
            AND deleted_at IS NULL
          GROUP BY tag_slug
          ORDER BY cnt DESC, tag_slug
          ''',
          variables: [
            Variable.withString(viewerId),
            Variable.withString(subjectId),
            Variable.withInt(CapabilityEventSource.forwardReason.dbValue),
          ],
        )
        .get();
    final forwardReasonsByMe = forwardRows
        .map(
          (r) => TagCountRow(
            slug: r.read<String>('tag_slug'),
            count: r.read<int>('cnt'),
            lastSeenAt: r.read<String>('last_seen'),
          ),
        )
        .toList();

    // Commit roles (beacon-scoped — readable by any viewer)
    final commitRows = await _database
        .customSelect(
          r'''
          SELECT pce.tag_slug, pce.beacon_id, b.title, pce.created_at::text AS ts
          FROM public.person_capability_event pce
          JOIN public.beacon b ON b.id = pce.beacon_id
          WHERE pce.subject_user_id = $1
            AND pce.source_type = $2
            AND pce.deleted_at IS NULL
          ORDER BY pce.created_at DESC
          ''',
          variables: [
            Variable.withString(subjectId),
            Variable.withInt(CapabilityEventSource.commitRole.dbValue),
          ],
        )
        .get();
    final commitRoles = commitRows
        .map(
          (r) => TagBeaconRefRow(
            slug: r.read<String>('tag_slug'),
            beaconId: r.read<String>('beacon_id'),
            beaconTitle: r.read<String>('title'),
            createdAt: r.read<String>('ts'),
          ),
        )
        .toList();

    // Close acks written by viewer about subject
    final closeByMeRows = await _database
        .customSelect(
          r'''
          SELECT pce.tag_slug, pce.beacon_id, b.title, pce.created_at::text AS ts
          FROM public.person_capability_event pce
          JOIN public.beacon b ON b.id = pce.beacon_id
          WHERE pce.observer_user_id = $1
            AND pce.subject_user_id  = $2
            AND pce.source_type = $3
            AND pce.deleted_at IS NULL
          ORDER BY pce.created_at DESC
          ''',
          variables: [
            Variable.withString(viewerId),
            Variable.withString(subjectId),
            Variable.withInt(
              CapabilityEventSource.closeAcknowledgement.dbValue,
            ),
          ],
        )
        .get();
    final closeAckByMe = closeByMeRows
        .map(
          (r) => TagBeaconRefRow(
            slug: r.read<String>('tag_slug'),
            beaconId: r.read<String>('beacon_id'),
            beaconTitle: r.read<String>('title'),
            createdAt: r.read<String>('ts'),
          ),
        )
        .toList();

    // Close acks about viewer (only when viewer == subject)
    final closeAckAboutMe = <TagBeaconRefRow>[];
    if (viewerId == subjectId) {
      final rows = await _database
          .customSelect(
            r'''
            SELECT pce.tag_slug, pce.beacon_id, b.title, pce.created_at::text AS ts
            FROM public.person_capability_event pce
            JOIN public.beacon b ON b.id = pce.beacon_id
            WHERE pce.subject_user_id = $1
              AND pce.source_type = $2
              AND pce.deleted_at IS NULL
            ORDER BY pce.created_at DESC
            ''',
            variables: [
              Variable.withString(subjectId),
              Variable.withInt(
                CapabilityEventSource.closeAcknowledgement.dbValue,
              ),
            ],
          )
          .get();
      closeAckAboutMe.addAll(
        rows.map(
          (r) => TagBeaconRefRow(
            slug: r.read<String>('tag_slug'),
            beaconId: r.read<String>('beacon_id'),
            beaconTitle: r.read<String>('title'),
            createdAt: r.read<String>('ts'),
          ),
        ),
      );
    }

    return PersonCapabilityCuesRow(
      privateLabels: privateLabels,
      forwardReasonsByMe: forwardReasonsByMe,
      commitRoles: commitRoles,
      closeAckByMe: closeAckByMe,
      closeAckAboutMe: closeAckAboutMe,
    );
  }

  @override
  Future<void> insertTombstone({
    required String observerId,
    required String subjectId,
    required String slug,
  }) => _database.withMutatingUser(observerId, () async {
    await _database.customStatement(
      r'''
      INSERT INTO public.person_capability_event
        (id, subject_user_id, observer_user_id, tag_slug, source_type, visibility, is_negative)
      VALUES ($1, $2, $3, $4, 0, 0, true)
      ON CONFLICT DO NOTHING
      ''',
      [generateId('CE'), subjectId, observerId, slug],
    );
  });

  @override
  Future<void> deleteTombstone({
    required String observerId,
    required String subjectId,
    required String slug,
  }) => _database.withMutatingUser(observerId, () async {
    await _database.customStatement(
      r'''
      UPDATE public.person_capability_event
      SET deleted_at = now()
      WHERE observer_user_id = $1
        AND subject_user_id  = $2
        AND tag_slug         = $3
        AND is_negative      = true
        AND deleted_at IS NULL
      ''',
      [observerId, subjectId, slug],
    );
  });

  @override
  Future<List<ViewerVisibleCapabilityRow>> fetchDeduplicatedCapabilities({
    required String viewerId,
    required String subjectId,
  }) async {
    // Build the self-view close-ack branch only when viewer == subject.
    final selfViewBranch = viewerId == subjectId
        ? r'''
          UNION ALL
          -- close-acks about subject by anyone (self-view only)
          SELECT tag_slug, false AS has_manual_label
          FROM public.person_capability_event
          WHERE subject_user_id = $2
            AND source_type     = 3
            AND is_negative     = false
            AND deleted_at IS NULL
        '''
        : '';

    final rows = await _database
        .customSelect(
          '''
          WITH positive_slugs AS (
            SELECT tag_slug, true  AS has_manual_label
            FROM public.person_capability_event
            WHERE observer_user_id = \$1
              AND subject_user_id  = \$2
              AND source_type      = 0
              AND is_negative      = false
              AND deleted_at IS NULL

            UNION ALL

            SELECT tag_slug, false AS has_manual_label
            FROM public.person_capability_event
            WHERE observer_user_id = \$1
              AND subject_user_id  = \$2
              AND source_type      = 1
              AND is_negative      = false
              AND deleted_at IS NULL

            UNION ALL

            SELECT tag_slug, false AS has_manual_label
            FROM public.person_capability_event
            WHERE subject_user_id = \$2
              AND source_type     = 2
              AND is_negative     = false
              AND deleted_at IS NULL

            UNION ALL

            SELECT tag_slug, false AS has_manual_label
            FROM public.person_capability_event
            WHERE observer_user_id = \$1
              AND subject_user_id  = \$2
              AND source_type      = 3
              AND is_negative      = false
              AND deleted_at IS NULL
            $selfViewBranch
          ),
          tombstoned AS (
            SELECT tag_slug
            FROM public.person_capability_event
            WHERE observer_user_id = \$1
              AND subject_user_id  = \$2
              AND is_negative      = true
              AND deleted_at IS NULL
          )
          SELECT tag_slug,
                 bool_or(has_manual_label) AS has_manual_label
          FROM positive_slugs
          WHERE tag_slug NOT IN (SELECT tag_slug FROM tombstoned)
          GROUP BY tag_slug
          ORDER BY tag_slug
          ''',
          variables: [
            Variable.withString(viewerId),
            Variable.withString(subjectId),
          ],
        )
        .get();

    return rows
        .map(
          (r) => ViewerVisibleCapabilityRow(
            slug: r.read<String>('tag_slug'),
            hasManualLabel: r.read<bool>('has_manual_label'),
          ),
        )
        .toList();
  }

  @override
  Future<Map<String, List<String>>> fetchTopCapabilitiesBatch({
    required String viewerId,
    required List<String> subjectIds,
    int limit = 2,
  }) async {
    if (subjectIds.isEmpty) return {};

    // Build IN-list placeholders: $2, $3, ... for subject IDs; limit is last.
    // Paired with fetchDeduplicatedCapabilities source-type semantics:
    //   source 0,1,3: observer-scoped; source 2: subject-only (commit roles).
    final sp = List.generate(subjectIds.length, (i) => '\$${i + 2}').join(', ');
    final lp = '\$${subjectIds.length + 2}';

    final rows = await _database
        .customSelect(
          '''
          WITH positive_slugs AS (
            SELECT subject_user_id, tag_slug
            FROM public.person_capability_event
            WHERE observer_user_id = \$1
              AND subject_user_id IN ($sp)
              AND source_type = 0 AND is_negative = false AND deleted_at IS NULL
            UNION ALL
            SELECT subject_user_id, tag_slug
            FROM public.person_capability_event
            WHERE observer_user_id = \$1
              AND subject_user_id IN ($sp)
              AND source_type = 1 AND is_negative = false AND deleted_at IS NULL
            UNION ALL
            SELECT subject_user_id, tag_slug
            FROM public.person_capability_event
            WHERE subject_user_id IN ($sp)
              AND source_type = 2 AND is_negative = false AND deleted_at IS NULL
            UNION ALL
            SELECT subject_user_id, tag_slug
            FROM public.person_capability_event
            WHERE observer_user_id = \$1
              AND subject_user_id IN ($sp)
              AND source_type = 3 AND is_negative = false AND deleted_at IS NULL
          ),
          tombstoned AS (
            SELECT subject_user_id, tag_slug
            FROM public.person_capability_event
            WHERE observer_user_id = \$1
              AND subject_user_id IN ($sp)
              AND is_negative = true AND deleted_at IS NULL
          ),
          counted AS (
            SELECT ps.subject_user_id, ps.tag_slug, COUNT(*) AS cnt
            FROM positive_slugs ps
            LEFT JOIN tombstoned t USING (subject_user_id, tag_slug)
            WHERE t.tag_slug IS NULL
            GROUP BY ps.subject_user_id, ps.tag_slug
          ),
          ranked AS (
            SELECT subject_user_id, tag_slug,
                   ROW_NUMBER() OVER (
                     PARTITION BY subject_user_id ORDER BY cnt DESC, tag_slug ASC
                   ) AS rn
            FROM counted
          )
          SELECT subject_user_id, tag_slug
          FROM ranked
          WHERE rn <= $lp
          ORDER BY subject_user_id, rn
          ''',
          variables: [
            Variable.withString(viewerId),
            ...subjectIds.map(Variable.withString),
            Variable.withInt(limit),
          ],
        )
        .get();

    final result = <String, List<String>>{};
    for (final row in rows) {
      result
          .putIfAbsent(row.read<String>('subject_user_id'), () => [])
          .add(row.read<String>('tag_slug'));
    }
    return result;
  }

  @override
  Future<List<ForwardReasonRow>> fetchForwardReasonsByBeaconId({
    required String beaconId,
    required String viewerId,
  }) async {
    final rows = await _database
        .customSelect(
          r'''
          SELECT observer_user_id, subject_user_id,
                 array_agg(DISTINCT tag_slug ORDER BY tag_slug) AS slugs
          FROM public.person_capability_event
          WHERE beacon_id    = $1
            AND source_type  = $2
            AND deleted_at  IS NULL
            AND is_negative  = false
            AND (observer_user_id = $3 OR subject_user_id = $3)
          GROUP BY observer_user_id, subject_user_id
          ''',
          variables: [
            Variable.withString(beaconId),
            Variable.withInt(CapabilityEventSource.forwardReason.dbValue),
            Variable.withString(viewerId),
          ],
        )
        .get();

    return rows
        .map(
          (r) => ForwardReasonRow(
            observerId: r.read<String>('observer_user_id'),
            subjectId: r.read<String>('subject_user_id'),
            slugs: (r.read<List<dynamic>>('slugs')).cast<String>(),
          ),
        )
        .toList();
  }
}
