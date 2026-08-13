import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/capability/capability_consts.dart';
import 'package:tentura_server/domain/capability/capability_evidence_models.dart';
import 'package:tentura_server/domain/capability/capability_tag.dart';
import 'package:tentura_server/domain/capability/witness_window_policy.dart';
import 'package:tentura_server/domain/port/capability_cell_port.dart';
import 'package:tentura_server/domain/port/capability_own_evidence_port.dart';
import 'package:tentura_server/domain/port/pair_block_query_port.dart';
import 'package:tentura_server/domain/port/person_visibility_repository_port.dart';
import 'package:tentura_server/domain/port/routing_mute_port.dart';
import 'package:tentura_server/domain/port/user_block_repository_port.dart';
import 'package:tentura_server/domain/port/witness_window_port.dart';

import '_use_case_base.dart';

/// Tier-A evidence sorts above any finite network score (architecture §5.5 ∞).
const double kCapOwnEvidenceScore = double.infinity;

@Singleton(order: 2)
final class CapabilityProjectionCase extends UseCaseBase {
  CapabilityProjectionCase(
    this._witnessWindow,
    this._cellPort,
    this._ownEvidencePort,
    this._routingMute,
    this._pairBlockQuery,
    this._personVisibility,
    this._userBlock, {
    required super.env,
    required super.logger,
  });

  final WitnessWindowPort _witnessWindow;
  final CapabilityCellPort _cellPort;
  final CapabilityOwnEvidencePort _ownEvidencePort;
  final RoutingMutePort _routingMute;
  final PairBlockQueryPort _pairBlockQuery;
  final PersonVisibilityRepositoryPort _personVisibility;
  final UserBlockRepositoryPort _userBlock;

  Future<List<ScoredProjection>> project({
    required String egoId,
    required List<String> subjectIds,
    required List<String> tagSlugs,
    required String normalizedContext,
    required ProjectionSurface surface,
  }) async {
    if (subjectIds.isEmpty || tagSlugs.isEmpty) {
      return const [];
    }

    final window = await _loadWitnessWindow(
      egoId: egoId,
      normalizedContext: normalizedContext,
    );

    final admittedWitnesses = window
        .where((w) => w.admitted)
        .toList(growable: false);

    final witnessIds = admittedWitnesses
        .map((w) => w.witnessUserId)
        .toList(growable: false);

    final blockUserIds = <String>{
      egoId,
      ...subjectIds,
      ...witnessIds,
    };
    final blockedPairs = await _pairBlockQuery.blockedPairsAmong(
      userIds: blockUserIds,
    );

    final eligibleWitnesses = admittedWitnesses
        .where(
          (w) => !_isBlocked(blockedPairs, egoId, w.witnessUserId),
        )
        .toList(growable: false);

    final cells = await _cellPort.fetchCells(
      subjectIds: subjectIds,
      tagSlugs: tagSlugs,
      admittedWitnesses: eligibleWitnesses,
    );

    final mutedBySubject = await _routingMute.mutedSlugsFor(
      subjectIds: subjectIds,
    );

    final networkByPair = _aggregateNetworkProjections(
      egoId: egoId,
      cells: cells,
      blockedPairs: blockedPairs,
      mutedBySubject: mutedBySubject,
    );

    final tombstones = await _ownEvidencePort.fetchTombstones(
      egoId: egoId,
      subjectIds: subjectIds,
    );
    final tombstonedPairs = {
      for (final t in tombstones) (t.subjectUserId, t.tagSlug),
    };

    final ownRows = await _ownEvidencePort.fetchOwnEvidence(
      egoId: egoId,
      subjectIds: subjectIds,
      tagSlugs: tagSlugs,
    );

    final merged = <(String, String), ScoredProjection>{};

    for (final entry in networkByPair.entries) {
      if (tombstonedPairs.contains(entry.key)) {
        continue;
      }
      merged[entry.key] = entry.value;
    }

    for (final own in ownRows) {
      final key = (own.subjectUserId, own.tagSlug);
      if (tombstonedPairs.contains(key)) {
        continue;
      }
      final (tier, channel) = switch (own.channel) {
        EvidenceChannel.outcome => (
            ProjectionTier.ownOutcome,
            EvidenceChannel.outcome,
          ),
        EvidenceChannel.seed => (
            ProjectionTier.ownRouting,
            EvidenceChannel.seed,
          ),
      };
      merged[key] = ScoredProjection(
        subjectUserId: own.subjectUserId,
        tagSlug: own.tagSlug,
        tier: tier,
        channel: channel,
        score: kCapOwnEvidenceScore,
      );
    }

    var results = merged.values.toList(growable: false);
    results = _applySurfaceFilter(results, surface);
    return results;
  }

  /// Profile projection for a single target (§16.1 / D24 default context).
  Future<List<TagProjection>> subjectiveTags({
    required String actorId,
    required String targetId,
  }) async {
    if (!await _canViewSubject(actorId: actorId, targetId: targetId)) {
      return const [];
    }
    final scored = await project(
      egoId: actorId,
      subjectIds: [targetId],
      tagSlugs: kCapabilitySlugOrder,
      normalizedContext: '',
      surface: ProjectionSurface.profile,
    );
    return scored
        .map(
          (row) => TagProjection(
            subjectUserId: row.subjectUserId,
            tagSlug: row.tagSlug,
            tier: row.tier,
          ),
        )
        .toList(growable: false);
  }

  /// Tier-only explanation for one tag (forwardBand surface — all four tiers).
  Future<String?> tagExplanation({
    required String actorId,
    required String targetId,
    required String slug,
  }) async {
    if (!await _canViewSubject(actorId: actorId, targetId: targetId)) {
      return null;
    }
    if (!kAllowedCapabilitySlugs.contains(slug)) {
      return null;
    }
    final scored = await project(
      egoId: actorId,
      subjectIds: [targetId],
      tagSlugs: [slug],
      normalizedContext: '',
      surface: ProjectionSurface.forwardBand,
    );
    if (scored.isEmpty) {
      return null;
    }
    return scored.first.tier.name;
  }

  /// Read-through witness window (architecture §15): use cached rows when
  /// present; otherwise compute from raw facts, persist, and use for this
  /// request.
  Future<List<WitnessWeight>> _loadWitnessWindow({
    required String egoId,
    required String normalizedContext,
  }) async {
    final cached = await _witnessWindow.cachedWindow(
      egoId: egoId,
      normalizedContext: normalizedContext,
    );
    if (cached.isNotEmpty) {
      return cached;
    }

    final facts = await _witnessWindow.rawWindowFacts(
      egoId: egoId,
      normalizedContext: normalizedContext,
      topK: kCapWitnessWindowK,
    );
    final computed = computeWitnessWeights(facts);
    await _witnessWindow.storeWindow(
      egoId: egoId,
      normalizedContext: normalizedContext,
      weights: computed,
    );
    return computed;
  }

  Future<bool> _canViewSubject({
    required String actorId,
    required String targetId,
  }) async {
    if (await _userBlock.isBlockedPair(a: actorId, b: targetId)) {
      return false;
    }
    if (actorId == targetId) {
      return true;
    }
    final visible = await _personVisibility.mutuallyVisiblePeerIds(
      viewerId: actorId,
      peerIds: [targetId],
      context: '',
    );
    return visible.contains(targetId);
  }

  Map<(String, String), ScoredProjection> _aggregateNetworkProjections({
    required String egoId,
    required List<WitnessCellRow> cells,
    required Set<(String, String)> blockedPairs,
    required Map<String, Set<String>> mutedBySubject,
  }) {
    final outSums = <(String, String), double>{};
    final seedSums = <(String, String), double>{};

    for (final cell in cells) {
      if (cell.observerUserId == egoId ||
          cell.observerUserId == cell.subjectUserId) {
        continue;
      }
      if (_isBlocked(
        blockedPairs,
        cell.observerUserId,
        cell.subjectUserId,
      )) {
        continue;
      }

      final mutedSlugs = mutedBySubject[cell.subjectUserId];
      if (mutedSlugs != null && mutedSlugs.contains(cell.tagSlug)) {
        // Architecture D4 / §5.5 / §12.2 / §14: a routing mute anti-joins the
        // cell out of the SAME row set that feeds both S_out and S_seed — it
        // suppresses all third-party (network) projection for the pair, not
        // only the seed channel. Only the ego's own Tier A survives a mute.
        continue;
      }

      final key = (cell.subjectUserId, cell.tagSlug);
      outSums[key] = (outSums[key] ?? 0) + cell.m * cell.eOut;
      seedSums[key] = (seedSums[key] ?? 0) + cell.m * cell.eSeed;
    }

    final projections = <(String, String), ScoredProjection>{};
    final keys = {...outSums.keys, ...seedSums.keys};
    for (final key in keys) {
      final sOut = outSums[key] ?? 0;
      final sSeed = seedSums[key] ?? 0;

      if (sOut >= kCapThetaOut) {
        projections[key] = ScoredProjection(
          subjectUserId: key.$1,
          tagSlug: key.$2,
          tier: ProjectionTier.networkOutcome,
          channel: EvidenceChannel.outcome,
          score: sOut,
        );
      } else if (sSeed >= kCapThetaSeed) {
        projections[key] = ScoredProjection(
          subjectUserId: key.$1,
          tagSlug: key.$2,
          tier: ProjectionTier.networkSeed,
          channel: EvidenceChannel.seed,
          score: sSeed,
        );
      }
    }
    return projections;
  }

  List<ScoredProjection> _applySurfaceFilter(
    List<ScoredProjection> rows,
    ProjectionSurface surface,
  ) {
    return switch (surface) {
      ProjectionSurface.forwardBand => rows,
      ProjectionSurface.profile => _applyProfileCap(rows),
    };
  }

  List<ScoredProjection> _applyProfileCap(List<ScoredProjection> rows) {
    final outcomeRows = rows
        .where(
          (r) =>
              r.tier == ProjectionTier.ownOutcome ||
              r.tier == ProjectionTier.networkOutcome,
        )
        .toList(growable: false);

    final bySubject = <String, List<ScoredProjection>>{};
    for (final row in outcomeRows) {
      bySubject.putIfAbsent(row.subjectUserId, () => []).add(row);
    }

    final capped = <ScoredProjection>[];
    for (final subjectRows in bySubject.values) {
      subjectRows.sort(_profileRowOrder);
      capped.addAll(
        subjectRows.take(kCapMaxTagsPerSubjectBeacon),
      );
    }
    return capped;
  }

  static int _profileRowOrder(ScoredProjection a, ScoredProjection b) {
    final tierCmp = ProjectionTier.values
        .indexOf(a.tier)
        .compareTo(ProjectionTier.values.indexOf(b.tier));
    if (tierCmp != 0) {
      return tierCmp;
    }
    if (a.tier == ProjectionTier.networkOutcome) {
      final scoreCmp = b.score.compareTo(a.score);
      if (scoreCmp != 0) {
        return scoreCmp;
      }
    }
    return a.tagSlug.compareTo(b.tagSlug);
  }

  static (String, String) _canonicalPair(String a, String b) =>
      a.compareTo(b) <= 0 ? (a, b) : (b, a);

  static bool _isBlocked(
    Set<(String, String)> blockedPairs,
    String a,
    String b,
  ) =>
      blockedPairs.contains(_canonicalPair(a, b));
}
