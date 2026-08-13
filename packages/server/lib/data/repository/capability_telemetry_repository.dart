import 'package:injectable/injectable.dart';
import 'package:postgres/postgres.dart' show Type, TypedValue;

import 'package:tentura_server/domain/capability/capability_consts.dart';
import 'package:tentura_server/domain/capability/capability_event_source.dart';
import 'package:tentura_server/domain/capability/capability_evidence_models.dart';
import 'package:tentura_server/domain/capability/witness_window_policy.dart';
import 'package:tentura_server/domain/port/capability_telemetry_port.dart';

import '../database/tentura_db.dart';

@Injectable(
  as: CapabilityTelemetryPort,
  env: [Environment.dev, Environment.prod],
  order: 1,
)
class CapabilityTelemetryRepository implements CapabilityTelemetryPort {
  const CapabilityTelemetryRepository(this._database);

  final TenturaDb _database;

  static final _seedSourceTypes = [
    CapabilityEventSource.forwardReason.dbValue,
    CapabilityEventSource.seedRoutingAttestation.dbValue,
  ];

  static const _twoHopEgoSampleLimit = 50;
  static const _twoHopScoreLimit = 500;
  static const _coverageEgoSampleLimit = 30;
  static const _coveragePairSampleLimit = 50;
  static const _coverageTripleLimit = 200;

  static final _hlOut = kCapHalfLifeOutSeconds.toDouble();
  static final _hlSeed = kCapHalfLifeSeedSeconds.toDouble();

  @override
  Future<({int seedTriples, int renewed})> countSeedRenewal() async {
    final seedTypes = _seedSourceTypes.join(',');
    final forwardReason = CapabilityEventSource.forwardReason.dbValue;

    final row = await _database
        .customSelect(
          '''
WITH seed_triples AS (
  SELECT
    observer_user_id,
    subject_user_id,
    tag_slug,
    MIN(created_at) AS earliest_seed_at
  FROM public.person_capability_event
  WHERE deleted_at IS NULL
    AND is_negative = false
    AND source_type IN ($seedTypes)
  GROUP BY observer_user_id, subject_user_id, tag_slug
),
with_expiry AS (
  SELECT
    st.observer_user_id,
    st.subject_user_id,
    st.tag_slug,
    st.earliest_seed_at,
    cee.next_expiry_at
  FROM seed_triples st
  LEFT JOIN public.capability_evidence_edge cee
    ON cee.observer_user_id = st.observer_user_id
    AND cee.subject_user_id = st.subject_user_id
    AND cee.tag_slug = st.tag_slug
),
renewed AS (
  SELECT DISTINCT
    wt.observer_user_id,
    wt.subject_user_id,
    wt.tag_slug
  FROM with_expiry wt
  WHERE EXISTS (
    SELECT 1
    FROM public.person_capability_event pce
    WHERE pce.observer_user_id = wt.observer_user_id
      AND pce.subject_user_id = wt.subject_user_id
      AND pce.tag_slug = wt.tag_slug
      AND pce.source_type = $forwardReason
      AND pce.deleted_at IS NULL
      AND pce.is_negative = false
      AND pce.created_at > wt.earliest_seed_at
      AND (
        wt.next_expiry_at IS NULL
        OR pce.created_at < wt.next_expiry_at
      )
  )
)
SELECT
  (SELECT COUNT(*)::int FROM seed_triples) AS seed_triples,
  (SELECT COUNT(*)::int FROM renewed) AS renewed
''',
          readsFrom: {
            _database.personCapabilityEvents,
            _database.capabilityEvidenceEdges,
          },
        )
        .getSingle();

    return (
      seedTriples: row.read<int>('seed_triples'),
      renewed: row.read<int>('renewed'),
    );
  }

  @override
  Future<({int n, double? p33, double? p50, double? p75})>
  twoHopSponsoredForwardMrPercentiles() async {
    final row = await _database
        .customSelect(
          '''
WITH sampled_egos AS (
  SELECT DISTINCT observer_user_id AS ego_id
  FROM public.person_capability_event
  WHERE deleted_at IS NULL
    AND is_negative = false
  LIMIT $_twoHopEgoSampleLimit
),
hop1 AS (
  SELECT ig.ancestor_user_id AS ego_id, ig.descendant_user_id AS hop1_id
  FROM public.invite_genealogy ig
  INNER JOIN sampled_egos se ON se.ego_id = ig.ancestor_user_id
  WHERE ig.descendant_user_id IS NOT NULL
),
hop2 AS (
  SELECT h1.ego_id, ig.descendant_user_id AS sponsored_user_id
  FROM hop1 h1
  INNER JOIN public.invite_genealogy ig ON ig.ancestor_user_id = h1.hop1_id
  WHERE ig.descendant_user_id IS NOT NULL
),
scores AS (
  SELECT DISTINCT h2.ego_id, p.forward_mr
  FROM hop2 h2
  INNER JOIN LATERAL (
    SELECT forward_mr
    FROM public.person_visibility_peers(h2.ego_id, '')
    WHERE peer_id = h2.sponsored_user_id
      AND forward_mr > 0
  ) p ON true
  LIMIT $_twoHopScoreLimit
)
SELECT
  COUNT(*)::int AS n,
  percentile_cont(0.33) WITHIN GROUP (ORDER BY forward_mr) AS p33,
  percentile_cont(0.50) WITHIN GROUP (ORDER BY forward_mr) AS p50,
  percentile_cont(0.75) WITHIN GROUP (ORDER BY forward_mr) AS p75
FROM scores
''',
          readsFrom: {
            _database.personCapabilityEvents,
            _database.inviteGenealogy,
          },
        )
        .getSingle();

    final n = row.read<int>('n');
    if (n == 0) {
      return (n: 0, p33: null, p50: null, p75: null);
    }
    return (
      n: n,
      p33: row.read<double?>('p33'),
      p50: row.read<double?>('p50'),
      p75: row.read<double?>('p75'),
    );
  }

  @override
  Future<({int eligibleClearing, int ineligibleOnly})>
  countEligibleWitnessCoverage() async {
    final tripleRows = await _database
        .customSelect(
          '''
WITH sampled_egos AS (
  SELECT DISTINCT observer_user_id AS ego_id
  FROM public.person_capability_event
  WHERE deleted_at IS NULL
    AND is_negative = false
  LIMIT $_coverageEgoSampleLimit
),
active_pairs AS (
  SELECT DISTINCT subject_user_id, tag_slug
  FROM public.capability_evidence_edge
  WHERE s_out > 0 OR s_seed > 0
  LIMIT $_coveragePairSampleLimit
)
SELECT se.ego_id, ap.subject_user_id, ap.tag_slug
FROM sampled_egos se
CROSS JOIN active_pairs ap
LIMIT $_coverageTripleLimit
''',
          readsFrom: {
            _database.personCapabilityEvents,
            _database.capabilityEvidenceEdges,
          },
        )
        .get();

    if (tripleRows.isEmpty) {
      return (eligibleClearing: 0, ineligibleOnly: 0);
    }

    final egoIds = tripleRows.map((r) => r.read<String>('ego_id')).toSet().toList();
    final factsByEgo = await _fetchWindowFactsByEgo(egoIds);

    final cellRows = await _database
        .customSelect(
          '''
WITH sampled_egos AS (
  SELECT DISTINCT observer_user_id AS ego_id
  FROM public.person_capability_event
  WHERE deleted_at IS NULL
    AND is_negative = false
  LIMIT $_coverageEgoSampleLimit
),
active_pairs AS (
  SELECT DISTINCT subject_user_id, tag_slug
  FROM public.capability_evidence_edge
  WHERE s_out > 0 OR s_seed > 0
  LIMIT $_coveragePairSampleLimit
),
samples AS (
  SELECT se.ego_id, ap.subject_user_id, ap.tag_slug
  FROM sampled_egos se
  CROSS JOIN active_pairs ap
  LIMIT $_coverageTripleLimit
)
SELECT
  s.ego_id,
  s.subject_user_id,
  s.tag_slug,
  c.observer_user_id,
  public.cap_strength(c.s_out, \$1::double precision, c.anchor_at, \$2::double precision)
    AS e_out,
  public.cap_strength(c.s_seed, \$3::double precision, c.anchor_at, \$4::double precision)
    AS e_seed
FROM samples s
INNER JOIN public.capability_evidence_edge c
  ON c.subject_user_id = s.subject_user_id
 AND c.tag_slug = s.tag_slug
''',
          variables: [
            Variable<double>(kCapKOut),
            Variable<double>(_hlOut),
            Variable<double>(kCapKSeed),
            Variable<double>(_hlSeed),
          ],
          readsFrom: {_database.capabilityEvidenceEdges},
        )
        .get();

    final cellsByTriple = <String, List<({String observerId, double eOut, double eSeed})>>{};
    for (final row in cellRows) {
      final key =
          '${row.read<String>('ego_id')}|${row.read<String>('subject_user_id')}|${row.read<String>('tag_slug')}';
      cellsByTriple.putIfAbsent(key, () => []).add(
        (
          observerId: row.read<String>('observer_user_id'),
          eOut: row.read<double>('e_out'),
          eSeed: row.read<double>('e_seed'),
        ),
      );
    }

    var eligibleClearing = 0;
    var ineligibleOnly = 0;

    for (final triple in tripleRows) {
      final egoId = triple.read<String>('ego_id');
      final subjectId = triple.read<String>('subject_user_id');
      final tagSlug = triple.read<String>('tag_slug');
      final key = '$egoId|$subjectId|$tagSlug';
      final cells = cellsByTriple[key];
      if (cells == null || cells.isEmpty) {
        continue;
      }

      final facts = factsByEgo[egoId];
      if (facts == null) {
        continue;
      }

      final weights = {
        for (final w in computeWitnessWeights(facts)) w.witnessUserId: w,
      };

      var sOutEligible = 0.0;
      var sSeedEligible = 0.0;
      var sOutAll = 0.0;
      var sSeedAll = 0.0;

      for (final cell in cells) {
        final weight = weights[cell.observerId];
        if (weight == null) {
          continue;
        }
        sOutAll += weight.m * cell.eOut;
        sSeedAll += weight.m * cell.eSeed;
        if (weight.admitted) {
          sOutEligible += weight.m * cell.eOut;
          sSeedEligible += weight.m * cell.eSeed;
        }
      }

      final clearsEligible =
          sOutEligible >= kCapThetaOut || sSeedEligible >= kCapThetaSeed;
      final clearsAll = sOutAll >= kCapThetaOut || sSeedAll >= kCapThetaSeed;

      if (clearsEligible) {
        eligibleClearing++;
      } else if (clearsAll) {
        ineligibleOnly++;
      }
    }

    return (eligibleClearing: eligibleClearing, ineligibleOnly: ineligibleOnly);
  }

  Future<Map<String, RawWindowFacts>> _fetchWindowFactsByEgo(
    List<String> egoIds,
  ) async {
    if (egoIds.isEmpty) {
      return const {};
    }

    final peerRows = await _database
        .customSelect(
          r'''
SELECT e.ego_id, p.peer_id, p.forward_mr, p.viewer_explicitly_trusts_subject
FROM unnest($1::text[]) AS e(ego_id)
CROSS JOIN LATERAL (
  SELECT peer_id, forward_mr, viewer_explicitly_trusts_subject
  FROM public.person_visibility_peers(e.ego_id, '')
  WHERE forward_mr > 0
  ORDER BY forward_mr DESC, peer_id ASC
  LIMIT $2
) p
''',
          variables: [
            Variable(TypedValue(Type.textArray, egoIds)),
            Variable<int>(kCapWitnessWindowK),
          ],
          readsFrom: {},
        )
        .get();

    final trustedRows = await _database
        .customSelect(
          r'''
SELECT e.ego_id, p.forward_mr
FROM unnest($1::text[]) AS e(ego_id)
CROSS JOIN LATERAL (
  SELECT forward_mr
  FROM public.person_visibility_peers(e.ego_id, '')
  WHERE viewer_explicitly_trusts_subject
    AND forward_mr > 0
) p
''',
          variables: [
            Variable(TypedValue(Type.textArray, egoIds)),
          ],
          readsFrom: {},
        )
        .get();

    final topPeersByEgo = <String, List<RawPeerFact>>{};
    for (final row in peerRows) {
      final egoId = row.read<String>('ego_id');
      topPeersByEgo.putIfAbsent(egoId, () => []).add(
        RawPeerFact(
          peerId: row.read<String>('peer_id'),
          forwardMr: row.read<double>('forward_mr'),
          explicitlyTrusted: row.read<bool>('viewer_explicitly_trusts_subject'),
        ),
      );
    }

    final trustedByEgo = <String, List<double>>{};
    for (final row in trustedRows) {
      final egoId = row.read<String>('ego_id');
      trustedByEgo.putIfAbsent(egoId, () => []).add(row.read<double>('forward_mr'));
    }

    return {
      for (final egoId in egoIds)
        egoId: RawWindowFacts(
          topPeers: topPeersByEgo[egoId] ?? const [],
          trustedScores: trustedByEgo[egoId] ?? const [],
        ),
    };
  }
}
