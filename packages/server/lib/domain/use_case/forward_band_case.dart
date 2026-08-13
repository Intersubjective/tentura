import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/capability/capability_consts.dart';
import 'package:tentura_server/domain/capability/capability_evidence_models.dart';
import 'package:tentura_server/domain/capability/context_normalization.dart';
import 'package:tentura_server/domain/capability/fnv1a64.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/band_candidate_port.dart';
import 'package:tentura_server/domain/port/beacon_access_guard.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/use_case/capability_projection_case.dart';

import '_use_case_base.dart';

const int _kCapBandLabelSlots = 2;

@Singleton(order: 2)
final class ForwardBandCase extends UseCaseBase {
  ForwardBandCase(
    this._bandCandidatePort,
    this._beaconRepositoryPort,
    this._capabilityProjectionCase,
    this._guard, {
    required super.env,
    required super.logger,
  });

  final BandCandidatePort _bandCandidatePort;
  final BeaconRepositoryPort _beaconRepositoryPort;
  final CapabilityProjectionCase _capabilityProjectionCase;
  final BeaconAccessGuard _guard;

  /// Composed forward band for an authorized viewer (§16.1).
  Future<List<ForwardBandRow>> forwardContext({
    required String actorId,
    required String beaconId,
    required String rawContext,
  }) async {
    if (!await _guard.canReadContent(
      beaconId: beaconId,
      viewerId: actorId,
    )) {
      throw const UnauthorizedException(
        description: 'Viewer cannot read request content',
      );
    }
    return composeBand(
      egoId: actorId,
      beaconId: beaconId,
      normalizedContext: capNormalizeContext(rawContext),
    );
  }

  Future<List<ForwardBandRow>> composeBand({
    required String egoId,
    required String beaconId,
    required String normalizedContext,
  }) async {
    final beacon = await _beaconRepositoryPort.getBeaconById(
      beaconId: beaconId,
    );
    final tagSlugs = beacon.needs.toList(growable: false);
    if (tagSlugs.isEmpty) {
      return const [];
    }

    final candidates = await _bandCandidatePort.candidatesFor(
      egoId: egoId,
      beaconId: beaconId,
      normalizedContext: normalizedContext,
    );
    final forwardableCandidates = candidates
        .where((candidate) => candidate.canForwardTo)
        .toList(growable: false);
    if (forwardableCandidates.isEmpty) {
      return const [];
    }

    final projections = await _capabilityProjectionCase.project(
      egoId: egoId,
      subjectIds: forwardableCandidates.map((c) => c.userId).toList(),
      tagSlugs: tagSlugs,
      normalizedContext: normalizedContext,
      surface: ProjectionSurface.forwardBand,
    );

    final projectionsBySubject = _groupProjectionsBySubject(projections);
    final forwardMrByUserId = {
      for (final candidate in forwardableCandidates)
        candidate.userId: candidate.forwardMr,
    };
    final evidencedUserIds = projectionsBySubject.keys.toSet();

    final evidenceRows = _buildEvidenceRows(
      forwardableCandidates: forwardableCandidates,
      projectionsBySubject: projectionsBySubject,
      forwardMrByUserId: forwardMrByUserId,
      primaryNeedSlug: beacon.primaryNeedSlug,
    );
    if (evidenceRows.isEmpty) {
      return const [];
    }

    final explorationRows = await _buildExplorationRows(
      egoId: egoId,
      beaconId: beaconId,
      forwardableCandidates: forwardableCandidates,
      evidencedUserIds: evidencedUserIds,
      startingRank: evidenceRows.length,
    );

    final band = [...evidenceRows, ...explorationRows];
    _logBandComposed(beaconId: beaconId, band: band);
    return band;
  }

  /// §21 telemetry: band fill rate and slot occupancy by tier. Counts only
  /// — never candidate/recipient user ids.
  void _logBandComposed({
    required String beaconId,
    required List<ForwardBandRow> band,
  }) {
    if (band.isEmpty) {
      logger.info('forward_band_composed beacon=$beaconId filled=false');
      return;
    }
    final tierCounts = <ProjectionTier, int>{};
    var explorationCount = 0;
    for (final row in band) {
      if (row.isExploration) {
        explorationCount++;
      } else if (row.rowTier != null) {
        tierCounts[row.rowTier!] = (tierCounts[row.rowTier!] ?? 0) + 1;
      }
    }
    final tierSummary = [
      for (final tier in ProjectionTier.values)
        '${tier.name}=${tierCounts[tier] ?? 0}',
    ].join(' ');
    logger.info(
      'forward_band_composed beacon=$beaconId filled=true '
      'total=${band.length} $tierSummary exploration=$explorationCount',
    );
  }

  Map<String, List<ScoredProjection>> _groupProjectionsBySubject(
    List<ScoredProjection> projections,
  ) {
    final grouped = <String, List<ScoredProjection>>{};
    for (final projection in projections) {
      grouped
          .putIfAbsent(projection.subjectUserId, () => [])
          .add(projection);
    }
    return grouped;
  }

  List<ForwardBandRow> _buildEvidenceRows({
    required List<BandCandidate> forwardableCandidates,
    required Map<String, List<ScoredProjection>> projectionsBySubject,
    required Map<String, double> forwardMrByUserId,
    required String? primaryNeedSlug,
  }) {
    final ranked = <_RankedEvidenceCandidate>[];
    for (final candidate in forwardableCandidates) {
      final subjectProjections = projectionsBySubject[candidate.userId];
      if (subjectProjections == null || subjectProjections.isEmpty) {
        continue;
      }

      final rowTier = _strongestTier(subjectProjections);
      final tierScore = _maxScoreAtTier(
        subjectProjections,
        rowTier: rowTier,
      );
      ranked.add(
        _RankedEvidenceCandidate(
          userId: candidate.userId,
          rowTier: rowTier,
          tierScore: tierScore,
          forwardMr: forwardMrByUserId[candidate.userId] ?? 0,
          labels: _buildLabels(
            projections: subjectProjections,
            rowTier: rowTier,
            primaryNeedSlug: primaryNeedSlug,
          ),
        ),
      );
    }

    ranked.sort(_compareEvidenceCandidates);

    return [
      for (var index = 0; index < ranked.length; index++)
        if (index < kCapBandEvidenceSlots)
          ForwardBandRow(
            userId: ranked[index].userId,
            rowTier: ranked[index].rowTier,
            labels: ranked[index].labels,
            rank: index,
            isExploration: false,
          ),
    ];
  }

  Future<List<ForwardBandRow>> _buildExplorationRows({
    required String egoId,
    required String beaconId,
    required List<BandCandidate> forwardableCandidates,
    required Set<String> evidencedUserIds,
    required int startingRank,
  }) async {
    final recentlyForwarded = await _bandCandidatePort.recentlyForwardedTo(
      egoId: egoId,
      withinDays: kCapExplorationRecentForwardDays,
    );

    final pool = forwardableCandidates
        .where(
          (candidate) =>
              !evidencedUserIds.contains(candidate.userId) &&
              !recentlyForwarded.contains(candidate.userId),
        )
        .toList(growable: false)
      ..sort(_compareExplorationCandidates);

    if (pool.isEmpty) {
      return const [];
    }

    final picks = pool.length == 1
        ? [pool.single]
        : [
            pool[fnv1a64Mod(beaconId, pool.length)],
            pool[(fnv1a64Mod(beaconId, pool.length) + 1) % pool.length],
          ];

    return [
      for (var index = 0; index < picks.length; index++)
        ForwardBandRow(
          userId: picks[index].userId,
          rowTier: null,
          labels: const [],
          rank: startingRank + index,
          isExploration: true,
        ),
    ];
  }

  ProjectionTier _strongestTier(List<ScoredProjection> projections) {
    return projections
        .map((projection) => projection.tier)
        .reduce(
          (stronger, candidate) =>
              _tierStrength(candidate) < _tierStrength(stronger)
              ? candidate
              : stronger,
        );
  }

  double _maxScoreAtTier(
    List<ScoredProjection> projections, {
    required ProjectionTier rowTier,
  }) {
    return projections
        .where((projection) => projection.tier == rowTier)
        .map((projection) => projection.score)
        .reduce((a, b) => a > b ? a : b);
  }

  List<TagProjection> _buildLabels({
    required List<ScoredProjection> projections,
    required ProjectionTier rowTier,
    required String? primaryNeedSlug,
  }) {
    final sameTier = projections
        .where((projection) => projection.tier == rowTier)
        .toList(growable: false)
      ..sort((a, b) => _compareLabelProjections(a, b, primaryNeedSlug));

    return sameTier
        .take(_kCapBandLabelSlots)
        .map(
          (projection) => TagProjection(
            subjectUserId: projection.subjectUserId,
            tagSlug: projection.tagSlug,
            tier: projection.tier,
          ),
        )
        .toList(growable: false);
  }

  int _tierStrength(ProjectionTier tier) =>
      ProjectionTier.values.indexOf(tier);

  int _compareEvidenceCandidates(
    _RankedEvidenceCandidate a,
    _RankedEvidenceCandidate b,
  ) {
    final tierCompare = _tierStrength(
      a.rowTier,
    ).compareTo(_tierStrength(b.rowTier));
    if (tierCompare != 0) {
      return tierCompare;
    }

    final scoreCompare = b.tierScore.compareTo(a.tierScore);
    if (scoreCompare != 0) {
      return scoreCompare;
    }

    final mrCompare = b.forwardMr.compareTo(a.forwardMr);
    if (mrCompare != 0) {
      return mrCompare;
    }

    return a.userId.compareTo(b.userId);
  }

  int _compareLabelProjections(
    ScoredProjection a,
    ScoredProjection b,
    String? primaryNeedSlug,
  ) {
    if (primaryNeedSlug != null) {
      final aPrimary = a.tagSlug == primaryNeedSlug;
      final bPrimary = b.tagSlug == primaryNeedSlug;
      if (aPrimary != bPrimary) {
        return aPrimary ? -1 : 1;
      }
    }

    final scoreCompare = b.score.compareTo(a.score);
    if (scoreCompare != 0) {
      return scoreCompare;
    }

    return a.tagSlug.compareTo(b.tagSlug);
  }

  int _compareExplorationCandidates(BandCandidate a, BandCandidate b) {
    final mrCompare = b.forwardMr.compareTo(a.forwardMr);
    if (mrCompare != 0) {
      return mrCompare;
    }
    return a.userId.compareTo(b.userId);
  }
}

final class _RankedEvidenceCandidate {
  const _RankedEvidenceCandidate({
    required this.userId,
    required this.rowTier,
    required this.tierScore,
    required this.forwardMr,
    required this.labels,
  });

  final String userId;
  final ProjectionTier rowTier;
  final double tierScore;
  final double forwardMr;
  final List<TagProjection> labels;
}
