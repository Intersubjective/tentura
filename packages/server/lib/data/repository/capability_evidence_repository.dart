import 'package:drift/drift.dart' show Variable;
import 'package:injectable/injectable.dart';
import 'package:postgres/postgres.dart' show Type, TypedValue;

import 'package:tentura_server/domain/capability/capability_consts.dart';
import 'package:tentura_server/domain/capability/capability_event_source.dart';
import 'package:tentura_server/domain/capability/capability_event_visibility.dart';
import 'package:tentura_server/domain/capability/capability_evidence_models.dart';
import 'package:tentura_server/domain/port/capability_evidence_port.dart';
import 'package:tentura_server/utils/id.dart';

import '../database/tentura_db.dart';

@Injectable(
  as: CapabilityEvidencePort,
  env: [Environment.dev, Environment.prod],
  order: 1,
)
class CapabilityEvidenceRepository implements CapabilityEvidencePort {
  const CapabilityEvidenceRepository(this._database);

  final TenturaDb _database;

  static final _hlOut = kCapHalfLifeOutSeconds.toDouble();
  static final _hlSeed = kCapHalfLifeSeedSeconds.toDouble();

  @override
  Future<void> reconcileForwardReasons({
    required String forwardEdgeId,
    required String observerId,
    required String subjectId,
    required List<String> slugs,
  }) => _database.withMutatingUser(observerId, () async {
    await _lockForwardEdge(forwardEdgeId);

    final currentSlugs = await _activeForwardSlugs(forwardEdgeId);
    final desiredSlugs = slugs.toSet();
    final affectedSlugs = {...currentSlugs, ...desiredSlugs};

    final triples = _sortedUniqueTriples(
      affectedSlugs.map(
        (slug) => (observer: observerId, subject: subjectId, tag: slug),
      ),
    );
    if (triples.isEmpty) {
      return;
    }

    final beaconId = await _forwardEdgeBeaconId(forwardEdgeId);

    await _withCellWriteDiscipline(
      triples,
      () => _forwardChangingTriples(
        forwardEdgeId: forwardEdgeId,
        observerId: observerId,
        subjectId: subjectId,
        currentSlugs: currentSlugs,
        desiredSlugs: desiredSlugs,
      ),
      () async {
        await _database.customStatement(
          r'''
          UPDATE public.person_capability_event
          SET deleted_at = now()
          WHERE forward_edge_id = $1
            AND source_type = $2
            AND deleted_at IS NULL
            AND NOT (tag_slug = ANY($3::text[]))
          ''',
          [
            forwardEdgeId,
            CapabilityEventSource.forwardReason.dbValue,
            TypedValue(Type.textArray, slugs),
          ],
        );

        for (final slug in slugs) {
          await _database.customStatement(
            r'''
            INSERT INTO public.person_capability_event (
              id, subject_user_id, observer_user_id, tag_slug, source_type,
              forward_edge_id, beacon_id, visibility
            ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
            ON CONFLICT DO NOTHING
            ''',
            [
              generateId('CE'),
              subjectId,
              observerId,
              slug,
              CapabilityEventSource.forwardReason.dbValue,
              forwardEdgeId,
              beaconId,
              CapabilityEventVisibility.private.dbValue,
            ],
          );
          await _liftTombstone(
            observerId: observerId,
            subjectId: subjectId,
            slug: slug,
          );
        }
      },
    );
  });

  @override
  Future<void> emitOutcomeEvidenceBatch({
    required String beaconId,
    required List<OutcomeEmission> emissions,
  }) async {
    if (emissions.isEmpty) {
      return;
    }
    if (!_database.isInAmbientMutatingTransaction) {
      throw StateError(
        'emitOutcomeEvidenceBatch requires an ambient mutating unit of work',
      );
    }

    final triples = _sortedUniqueTriples(
      emissions.map(
        (e) => (
          observer: e.observerUserId,
          subject: e.subjectUserId,
          tag: e.tagSlug,
        ),
      ),
    );

    await _withCellWriteDiscipline(
      triples,
      () => _outcomeChangingTriples(beaconId: beaconId, emissions: emissions),
      () async {
        for (final emission in emissions) {
          await _database.customStatement(
            r'''
            INSERT INTO public.person_capability_event (
              id, subject_user_id, observer_user_id, tag_slug, source_type,
              beacon_id, visibility
            ) VALUES ($1, $2, $3, $4, $5, $6, $7)
            ON CONFLICT DO NOTHING
            ''',
            [
              generateId('CE'),
              emission.subjectUserId,
              emission.observerUserId,
              emission.tagSlug,
              CapabilityEventSource.closeAcknowledgement.dbValue,
              beaconId,
              CapabilityEventVisibility.beaconScoped.dbValue,
            ],
          );
        }
      },
    );
  }

  @override
  Future<void> revokeOutcomeEvidence({
    required String beaconId,
    required String observerId,
    required String subjectId,
    required String slug,
  }) => _database.withMutatingUser(observerId, () async {
    final triple = (observer: observerId, subject: subjectId, tag: slug);
    await _withCellWriteDiscipline(
      [triple],
      () async {
        final hasActive = await _hasActiveOutcomeEvidence(
          beaconId: beaconId,
          observerId: observerId,
          subjectId: subjectId,
          slug: slug,
        );
        return hasActive ? {triple} : <({String observer, String subject, String tag})>{};
      },
      () => _database.customStatement(
        r'''
        UPDATE public.person_capability_event
        SET deleted_at = now()
        WHERE observer_user_id = $1
          AND subject_user_id = $2
          AND tag_slug = $3
          AND beacon_id = $4
          AND source_type = $5
          AND deleted_at IS NULL
        ''',
        [
          observerId,
          subjectId,
          slug,
          beaconId,
          CapabilityEventSource.closeAcknowledgement.dbValue,
        ],
      ),
    );
  });

  @override
  Future<void> upsertSeedAttestation({
    required String observerId,
    required String subjectId,
    required List<String> slugs,
  }) => _database.withMutatingUser(observerId, () async {
    // Serialize complete seed replacements for one (observer, subject) pair
    // before reading active rows; per-cell locks alone cannot guard disjoint sets.
    await _lockSeedAttestationPair(observerId, subjectId);

    final currentSlugs = await _activeSeedSlugs(
      observerId: observerId,
      subjectId: subjectId,
    );
    final desiredSlugs = slugs.toSet();
    final affectedSlugs = {...currentSlugs, ...desiredSlugs};

    final triples = _sortedUniqueTriples(
      affectedSlugs.map(
        (slug) => (observer: observerId, subject: subjectId, tag: slug),
      ),
    );
    if (triples.isEmpty) {
      return;
    }

    await _withCellWriteDiscipline(
      triples,
      () => _seedChangingTriples(
        observerId: observerId,
        subjectId: subjectId,
        currentSlugs: currentSlugs,
        desiredSlugs: desiredSlugs,
      ),
      () async {
        await _database.customStatement(
          r'''
          UPDATE public.person_capability_event
          SET deleted_at = now()
          WHERE observer_user_id = $1
            AND subject_user_id = $2
            AND source_type = $3
            AND deleted_at IS NULL
            AND NOT (tag_slug = ANY($4::text[]))
          ''',
          [
            observerId,
            subjectId,
            CapabilityEventSource.seedRoutingAttestation.dbValue,
            TypedValue(Type.textArray, slugs),
          ],
        );

        for (final slug in slugs) {
          await _database.customStatement(
            r'''
            INSERT INTO public.person_capability_event (
              id, subject_user_id, observer_user_id, tag_slug, source_type,
              visibility
            ) VALUES ($1, $2, $3, $4, $5, $6)
            ON CONFLICT DO NOTHING
            ''',
            [
              generateId('CE'),
              subjectId,
              observerId,
              slug,
              CapabilityEventSource.seedRoutingAttestation.dbValue,
              CapabilityEventVisibility.private.dbValue,
            ],
          );
          await _liftTombstone(
            observerId: observerId,
            subjectId: subjectId,
            slug: slug,
          );
        }
      },
    );
  });

  Future<void> _withCellWriteDiscipline(
    List<({String observer, String subject, String tag})> lockTriples,
    Future<Set<({String observer, String subject, String tag})>> Function()
    resolveChangingTriples,
    Future<void> Function() mutateLedger,
  ) async {
    for (final triple in lockTriples) {
      await _lockCell(triple.observer, triple.subject, triple.tag);
    }

    final changing = _sortedUniqueTriples(await resolveChangingTriples());
    if (changing.isEmpty) {
      return;
    }

    for (final triple in changing) {
      await _bumpGeneration(triple.observer, triple.subject, triple.tag);
    }
    await mutateLedger();
    for (final triple in changing) {
      await _rebuildCell(triple.observer, triple.subject, triple.tag);
    }
  }

  Future<void> _lockForwardEdge(String forwardEdgeId) => _database.customStatement(
    r"SELECT pg_advisory_xact_lock(hashtextextended('cap:forward:' || $1, 4242))",
    [forwardEdgeId],
  );

  Future<void> _lockSeedAttestationPair(String observerId, String subjectId) =>
      _database.customStatement(
        r"SELECT pg_advisory_xact_lock(hashtextextended('cap:seed:' || $1 || chr(31) || $2, 4242))",
        [observerId, subjectId],
      );

  Future<void> _lockCell(String observer, String subject, String tag) =>
      _database.customStatement(
        r'SELECT public.cap_cell_lock($1, $2, $3)',
        [observer, subject, tag],
      );

  Future<void> _bumpGeneration(String observer, String subject, String tag) =>
      _database.customStatement(
        r'SELECT public.cap_generation_bump($1, $2, $3)',
        [observer, subject, tag],
      );

  Future<void> _rebuildCell(String observer, String subject, String tag) =>
      _database.customStatement(
        r'''
        SELECT public.cap_cell_rebuild(
          $1, $2, $3, $4::integer, $5::double precision, $6::double precision
        )
        ''',
        [observer, subject, tag, kCapWindowMonths, _hlOut, _hlSeed],
      );

  Future<Set<String>> _activeForwardSlugs(String forwardEdgeId) async {
    final rows = await _database
        .customSelect(
          r'''
          SELECT tag_slug
          FROM public.person_capability_event
          WHERE forward_edge_id = $1
            AND source_type = $2
            AND deleted_at IS NULL
          ''',
          variables: [
            Variable.withString(forwardEdgeId),
            Variable.withInt(CapabilityEventSource.forwardReason.dbValue),
          ],
        )
        .get();
    return rows.map((row) => row.read<String>('tag_slug')).toSet();
  }

  Future<Set<String>> _activeSeedSlugs({
    required String observerId,
    required String subjectId,
  }) async {
    final rows = await _database
        .customSelect(
          r'''
          SELECT tag_slug
          FROM public.person_capability_event
          WHERE observer_user_id = $1
            AND subject_user_id = $2
            AND source_type = $3
            AND deleted_at IS NULL
          ''',
          variables: [
            Variable.withString(observerId),
            Variable.withString(subjectId),
            Variable.withInt(CapabilityEventSource.seedRoutingAttestation.dbValue),
          ],
        )
        .get();
    return rows.map((row) => row.read<String>('tag_slug')).toSet();
  }

  Future<bool> _hasActiveOutcomeEvidence({
    required String beaconId,
    required String observerId,
    required String subjectId,
    required String slug,
  }) async {
    final row = await _database
        .customSelect(
          r'''
          SELECT 1
          FROM public.person_capability_event
          WHERE observer_user_id = $1
            AND subject_user_id = $2
            AND tag_slug = $3
            AND beacon_id = $4
            AND source_type = $5
            AND deleted_at IS NULL
          LIMIT 1
          ''',
          variables: [
            Variable.withString(observerId),
            Variable.withString(subjectId),
            Variable.withString(slug),
            Variable.withString(beaconId),
            Variable.withInt(CapabilityEventSource.closeAcknowledgement.dbValue),
          ],
        )
        .getSingleOrNull();
    return row != null;
  }

  Future<bool> _hasActiveTombstone({
    required String observerId,
    required String subjectId,
    required String slug,
  }) async {
    final row = await _database
        .customSelect(
          r'''
          SELECT 1
          FROM public.person_capability_event
          WHERE observer_user_id = $1
            AND subject_user_id = $2
            AND tag_slug = $3
            AND is_negative = true
            AND deleted_at IS NULL
          LIMIT 1
          ''',
          variables: [
            Variable.withString(observerId),
            Variable.withString(subjectId),
            Variable.withString(slug),
          ],
        )
        .getSingleOrNull();
    return row != null;
  }

  Future<Set<({String observer, String subject, String tag})>>
  _forwardChangingTriples({
    required String forwardEdgeId,
    required String observerId,
    required String subjectId,
    required Set<String> currentSlugs,
    required Set<String> desiredSlugs,
  }) async {
    final changing = <({String observer, String subject, String tag})>{};
    for (final slug in {...currentSlugs, ...desiredSlugs}) {
      final triple = (observer: observerId, subject: subjectId, tag: slug);
      final inCurrent = currentSlugs.contains(slug);
      final inDesired = desiredSlugs.contains(slug);
      if (inCurrent != inDesired) {
        changing.add(triple);
        continue;
      }
      if (inDesired &&
          await _hasActiveTombstone(
            observerId: observerId,
            subjectId: subjectId,
            slug: slug,
          )) {
        changing.add(triple);
      }
    }
    return changing;
  }

  Future<Set<({String observer, String subject, String tag})>>
  _seedChangingTriples({
    required String observerId,
    required String subjectId,
    required Set<String> currentSlugs,
    required Set<String> desiredSlugs,
  }) async {
    final changing = <({String observer, String subject, String tag})>{};
    for (final slug in {...currentSlugs, ...desiredSlugs}) {
      final triple = (observer: observerId, subject: subjectId, tag: slug);
      final inCurrent = currentSlugs.contains(slug);
      final inDesired = desiredSlugs.contains(slug);
      if (inCurrent != inDesired) {
        changing.add(triple);
        continue;
      }
      if (inDesired &&
          await _hasActiveTombstone(
            observerId: observerId,
            subjectId: subjectId,
            slug: slug,
          )) {
        changing.add(triple);
      }
    }
    return changing;
  }

  Future<Set<({String observer, String subject, String tag})>>
  _outcomeChangingTriples({
    required String beaconId,
    required List<OutcomeEmission> emissions,
  }) async {
    final changing = <({String observer, String subject, String tag})>{};
    for (final emission in emissions) {
      final triple = (
        observer: emission.observerUserId,
        subject: emission.subjectUserId,
        tag: emission.tagSlug,
      );
      if (!await _hasActiveOutcomeEvidence(
        beaconId: beaconId,
        observerId: emission.observerUserId,
        subjectId: emission.subjectUserId,
        slug: emission.tagSlug,
      )) {
        changing.add(triple);
      }
    }
    return changing;
  }

  Future<String?> _forwardEdgeBeaconId(String forwardEdgeId) async {
    final row = await _database
        .customSelect(
          r'''
          SELECT beacon_id
          FROM public.beacon_forward_edge
          WHERE id = $1
          ''',
          variables: [Variable.withString(forwardEdgeId)],
        )
        .getSingleOrNull();
    return row?.read<String?>('beacon_id');
  }

  Future<void> _liftTombstone({
    required String observerId,
    required String subjectId,
    required String slug,
  }) => _database.customStatement(
    r'''
    UPDATE public.person_capability_event
    SET deleted_at = now()
    WHERE observer_user_id = $1
      AND subject_user_id = $2
      AND tag_slug = $3
      AND is_negative = true
      AND deleted_at IS NULL
    ''',
    [observerId, subjectId, slug],
  );

  static List<({String observer, String subject, String tag})> _sortedUniqueTriples(
    Iterable<({String observer, String subject, String tag})> triples,
  ) {
    final unique = triples.toSet().toList()
      ..sort((a, b) {
        final byObserver = a.observer.compareTo(b.observer);
        if (byObserver != 0) {
          return byObserver;
        }
        final bySubject = a.subject.compareTo(b.subject);
        if (bySubject != 0) {
          return bySubject;
        }
        return a.tag.compareTo(b.tag);
      });
    return unique;
  }
}
