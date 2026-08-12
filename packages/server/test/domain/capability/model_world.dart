import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura_server/domain/capability/capability_consts.dart';
import 'package:tentura_server/domain/capability/capability_evidence_models.dart';
import 'package:tentura_server/domain/capability/witness_window_policy.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/use_case/capability_projection_case.dart';
import 'package:tentura_server/domain/use_case/forward_band_case.dart';
import 'package:tentura_server/env.dart';

import '../use_case/capability_projection_case_mocks.mocks.dart';
import '../use_case/forward_band_case_mocks.mocks.dart';
import 'cap_strength_fixture.dart';
import 'projection_standing.dart';

/// Fluent fixture wiring [CapabilityProjectionCase] and optionally
/// [ForwardBandCase] through the same Mockito port doubles as D1/D2 tests.
final class ModelWorld {
  ModelWorld({this.normalizedContext = ''});

  static const transport = 'transport';
  static const manualWork = 'manual_work';
  static const pets = 'pets';
  static const tools = 'tools';
  static const legalNavigation = 'legal_navigation';

  final String normalizedContext;

  final _egos = <String>{};
  final _peerFactsByEgo = <String, List<RawPeerFact>>{};
  final _witnessOverrides = <String, Map<String, WitnessWeight>>{};
  final _cellAccums = <_CellKey, _CellAccumulator>{};
  final _ownEvidence = <String, List<OwnEvidenceRow>>{};
  final _tombstones = <String, List<TombstoneRef>>{};
  final _mutes = <String, Set<String>>{};
  final _blocks = <(String, String)>{};
  final _witnessMOverrides = <_CellKey, double>{};

  String? _bandBeaconId;
  BeaconEntity? _beacon;
  final _bandCandidates = <BandCandidate>[];
  final _recentlyForwarded = <String>{};

  late final MockWitnessWindowPort _witnessWindow = MockWitnessWindowPort();
  late final MockCapabilityCellPort _cellPort = MockCapabilityCellPort();
  late final MockCapabilityOwnEvidencePort _ownEvidencePort =
      MockCapabilityOwnEvidencePort();
  late final MockRoutingMutePort _routingMute = MockRoutingMutePort();
  late final MockPairBlockQueryPort _pairBlockQuery = MockPairBlockQueryPort();
  late final MockBandCandidatePort _bandCandidatePort =
      MockBandCandidatePort();
  late final MockBeaconRepositoryPort _beaconRepositoryPort =
      MockBeaconRepositoryPort();

  late final CapabilityProjectionCase _projectionCase = CapabilityProjectionCase(
    _witnessWindow,
    _cellPort,
    _ownEvidencePort,
    _routingMute,
    _pairBlockQuery,
    env: Env(environment: Environment.test),
    logger: Logger('ModelWorldProjection'),
  );

  late final ForwardBandCase _forwardBandCase = ForwardBandCase(
    _bandCandidatePort,
    _beaconRepositoryPort,
    _projectionCase,
    env: Env(environment: Environment.test),
    logger: Logger('ModelWorldBand'),
  );

  final _tagSlugs = <String>{};

  void ego(String egoId) {
    _egos.add(egoId);
    _peerFactsByEgo.putIfAbsent(egoId, () => []);
    _witnessOverrides.putIfAbsent(egoId, () => {});
    _ownEvidence.putIfAbsent(egoId, () => []);
    _tombstones.putIfAbsent(egoId, () => []);
  }

  /// Explicit `vote_user` trust → admitted via [computeWitnessWeights].
  ModelWorld vouches(
    String egoId,
    String witnessId, {
    double forwardMr = 1.0,
  }) {
    ego(egoId);
    _peerFactsByEgo[egoId]!.add(
      RawPeerFact(
        peerId: witnessId,
        forwardMr: forwardMr,
        explicitlyTrusted: true,
      ),
    );
    return this;
  }

  /// MR-reachable peer; admission computed from [witness_window_policy].
  ModelWorld reaches(
    String egoId,
    String witnessId, {
    required double mr,
    bool explicitlyTrusted = false,
  }) {
    ego(egoId);
    _peerFactsByEgo[egoId]!.add(
      RawPeerFact(
        peerId: witnessId,
        forwardMr: mr,
        explicitlyTrusted: explicitlyTrusted,
      ),
    );
    return this;
  }

  /// Direct window override for invariants that only need a witness slot, not
  /// admission policy itself (W/C/A/T). Overrides beat computed weights.
  ModelWorld witnessWeight(
    String egoId,
    String witnessId, {
    required double m,
    required bool admitted,
  }) {
    ego(egoId);
    _witnessOverrides[egoId]![witnessId] = WitnessWeight(
      witnessUserId: witnessId,
      m: m,
      admitted: admitted,
    );
    return this;
  }

  ModelWorld outcome({
    required String witness,
    required String subject,
    required String tag,
    int daysAgo = 0,
    int count = 1,
    double? strengthOverride,
  }) {
    _tagSlugs.add(tag);
    final key = _CellKey(witness, subject, tag);
    if (strengthOverride != null) {
      _cellAccums[key] ??= _CellAccumulator();
      _cellAccums[key]!.eOutOverride = strengthOverride;
    } else {
      _cellAccums.putIfAbsent(key, () => _CellAccumulator())
        ..addOutcome(daysAgo: daysAgo, count: count);
    }
    return this;
  }

  ModelWorld seed({
    required String witness,
    required String subject,
    required String tag,
    int daysAgo = 0,
    int count = 1,
    double? strengthOverride,
  }) {
    _tagSlugs.add(tag);
    final key = _CellKey(witness, subject, tag);
    if (strengthOverride != null) {
      _cellAccums[key] ??= _CellAccumulator();
      _cellAccums[key]!.eSeedOverride = strengthOverride;
    } else {
      _cellAccums.putIfAbsent(key, () => _CellAccumulator())
        ..addSeed(daysAgo: daysAgo, count: count);
    }
    return this;
  }

  ModelWorld ownOutcome({
    required String egoId,
    required String subject,
    required String tag,
  }) {
    ego(egoId);
    _tagSlugs.add(tag);
    _ownEvidence[egoId]!.add(
      OwnEvidenceRow(
        subjectUserId: subject,
        tagSlug: tag,
        channel: EvidenceChannel.outcome,
      ),
    );
    return this;
  }

  ModelWorld ownRouting({
    required String egoId,
    required String subject,
    required String tag,
  }) {
    ego(egoId);
    _tagSlugs.add(tag);
    _ownEvidence[egoId]!.add(
      OwnEvidenceRow(
        subjectUserId: subject,
        tagSlug: tag,
        channel: EvidenceChannel.seed,
      ),
    );
    return this;
  }

  ModelWorld mute(String subjectId, String tagSlug) {
    _tagSlugs.add(tagSlug);
    _mutes.putIfAbsent(subjectId, () => {}).add(tagSlug);
    return this;
  }

  ModelWorld tombstone({
    required String egoId,
    required String subject,
    required String tag,
  }) {
    ego(egoId);
    _tagSlugs.add(tag);
    _tombstones[egoId]!.add(
      TombstoneRef(subjectUserId: subject, tagSlug: tag),
    );
    return this;
  }

  ModelWorld block(String a, String b) {
    final pair = _canonicalPair(a, b);
    _blocks.add(pair);
    return this;
  }

  ModelWorld cellWitnessM({
    required String witness,
    required String subject,
    required String tag,
    required double m,
  }) {
    _witnessMOverrides[_CellKey(witness, subject, tag)] = m;
    return this;
  }

  ModelWorld bandBeacon({
    required String beaconId,
    Set<String>? needs,
    String? primaryNeedSlug,
    DateTime? now,
  }) {
    _bandBeaconId = beaconId;
    final needSet = needs ?? {transport, tools, legalNavigation};
    _tagSlugs.addAll(needSet);
    final timestamp = now ?? DateTime.utc(2026);
    _beacon = BeaconEntity(
      id: beaconId,
      title: 'Model world beacon',
      author: const UserEntity(id: 'author'),
      createdAt: timestamp,
      updatedAt: timestamp,
      needs: needSet,
      primaryNeedSlug: primaryNeedSlug ?? transport,
    );
    return this;
  }

  ModelWorld bandCandidate({
    required String userId,
    double forwardMr = 0.5,
    bool canForwardTo = true,
    bool alreadyForwarded = false,
  }) {
    _bandCandidates.add(
      BandCandidate(
        userId: userId,
        forwardMr: forwardMr,
        canForwardTo: canForwardTo,
        alreadyForwarded: alreadyForwarded,
      ),
    );
    return this;
  }

  ModelWorld recentlyForwarded(String userId) {
    _recentlyForwarded.add(userId);
    return this;
  }

  Future<ProjectionStanding> standing(
    String egoId,
    String subjectId,
    String tagSlug, {
    ProjectionSurface surface = ProjectionSurface.forwardBand,
  }) async {
    final rows = await project(
      egoId: egoId,
      subjectIds: _subjectsForQuery(subjectId),
      tagSlugs: _tagsForQuery(tagSlug),
      surface: surface,
    );
    final match = rows
        .where(
          (row) =>
              row.subjectUserId == subjectId && row.tagSlug == tagSlug,
        )
        .firstOrNull;
    return ProjectionStanding.fromProjection(match);
  }

  Future<bool> hasProjection(
    String egoId,
    String subjectId,
    String tagSlug, {
    ProjectionSurface surface = ProjectionSurface.forwardBand,
  }) async {
    final s = await standing(
      egoId,
      subjectId,
      tagSlug,
      surface: surface,
    );
    return s.isPresent;
  }

  Future<List<ScoredProjection>> project({
    required String egoId,
    required List<String> subjectIds,
    required List<String> tagSlugs,
    ProjectionSurface surface = ProjectionSurface.forwardBand,
  }) async {
    _wireMocks(egoId: egoId, subjectIds: subjectIds, tagSlugs: tagSlugs);
    return _projectionCase.project(
      egoId: egoId,
      subjectIds: subjectIds,
      tagSlugs: tagSlugs,
      normalizedContext: normalizedContext,
      surface: surface,
    );
  }

  Future<List<ForwardBandRow>> composeBand({
    required String egoId,
    String? beaconId,
  }) async {
    final id = beaconId ?? _bandBeaconId;
    if (id == null || _beacon == null) {
      throw StateError('Call bandBeacon() before composeBand()');
    }
    final subjectIds = _bandCandidates.map((c) => c.userId).toList();
    _wireMocks(
      egoId: egoId,
      subjectIds: subjectIds,
      tagSlugs: _beacon!.needs.toList(),
      forBand: true,
      beaconId: id,
    );
    return _forwardBandCase.composeBand(
      egoId: egoId,
      beaconId: id,
      normalizedContext: normalizedContext,
    );
  }

  List<String> _subjectsForQuery(String subjectId) {
    final subjects = <String>{
      ..._cellAccums.keys.map((k) => k.subject),
      subjectId,
    };
    for (final rows in _ownEvidence.values) {
      subjects.addAll(rows.map((r) => r.subjectUserId));
    }
    return subjects.toList();
  }

  List<String> _tagsForQuery(String tagSlug) {
    return {..._tagSlugs, tagSlug}.toList();
  }

  List<WitnessWeight> _windowFor(String egoId) {
    final overrides = _witnessOverrides[egoId] ?? {};
    final facts = _peerFactsByEgo[egoId] ?? [];
    if (facts.isEmpty && overrides.isEmpty) {
      return const [];
    }

    final trustedScores = [
      for (final peer in facts)
        if (peer.explicitlyTrusted && peer.forwardMr > 0) peer.forwardMr,
    ];

    final computed = computeWitnessWeights(
      RawWindowFacts(topPeers: facts, trustedScores: trustedScores),
    );

    final byId = {for (final w in computed) w.witnessUserId: w};
    byId.addAll(overrides);
    return byId.values.toList();
  }

  List<WitnessCellRow> _cellsFor({
    required List<String> subjectIds,
    required List<String> tagSlugs,
    required List<WitnessWeight> admitted,
  }) {
    final admittedIds = admitted.map((w) => w.witnessUserId).toSet();
    final mByWitness = {for (final w in admitted) w.witnessUserId: w.m};

    final rows = <WitnessCellRow>[];
    for (final entry in _cellAccums.entries) {
      final key = entry.key;
      if (!subjectIds.contains(key.subject) || !tagSlugs.contains(key.tag)) {
        continue;
      }
      if (!admittedIds.contains(key.witness)) {
        continue;
      }
      final accum = entry.value;
      final m = _witnessMOverrides[key] ?? mByWitness[key.witness] ?? 0;
      rows.add(
        WitnessCellRow(
          observerUserId: key.witness,
          subjectUserId: key.subject,
          tagSlug: key.tag,
          eOut: accum.effectiveOut,
          eSeed: accum.effectiveSeed,
          m: m,
        ),
      );
    }
    return rows;
  }

  void _wireMocks({
    required String egoId,
    required List<String> subjectIds,
    required List<String> tagSlugs,
    bool forBand = false,
    String? beaconId,
  }) {
    final window = _windowFor(egoId);

    when(
      _witnessWindow.cachedWindow(
        egoId: egoId,
        normalizedContext: normalizedContext,
      ),
    ).thenAnswer((_) async => window);

    when(
      _cellPort.fetchCells(
        subjectIds: anyNamed('subjectIds'),
        tagSlugs: anyNamed('tagSlugs'),
        admittedWitnesses: anyNamed('admittedWitnesses'),
      ),
    ).thenAnswer((invocation) async {
      final admitted = List<WitnessWeight>.from(
        invocation.namedArguments[#admittedWitnesses] as List<WitnessWeight>,
      );
      final subjects = List<String>.from(
        invocation.namedArguments[#subjectIds] as List<String>,
      );
      final tags = List<String>.from(
        invocation.namedArguments[#tagSlugs] as List<String>,
      );
      return _cellsFor(
        subjectIds: subjects,
        tagSlugs: tags,
        admitted: admitted,
      );
    });

    when(
      _ownEvidencePort.fetchOwnEvidence(
        egoId: egoId,
        subjectIds: anyNamed('subjectIds'),
        tagSlugs: anyNamed('tagSlugs'),
      ),
    ).thenAnswer((invocation) async {
      final subjects = invocation.namedArguments[#subjectIds] as List<String>;
      final tags = invocation.namedArguments[#tagSlugs] as List<String>;
      return (_ownEvidence[egoId] ?? const [])
          .where(
            (row) =>
                subjects.contains(row.subjectUserId) &&
                tags.contains(row.tagSlug),
          )
          .toList();
    });

    when(
      _ownEvidencePort.fetchTombstones(
        egoId: egoId,
        subjectIds: anyNamed('subjectIds'),
      ),
    ).thenAnswer((invocation) async {
      final subjects = invocation.namedArguments[#subjectIds] as List<String>;
      return (_tombstones[egoId] ?? const [])
          .where((row) => subjects.contains(row.subjectUserId))
          .toList();
    });

    when(
      _pairBlockQuery.blockedPairsAmong(userIds: anyNamed('userIds')),
    ).thenAnswer((_) async => _blocks);

    when(
      _routingMute.mutedSlugsFor(subjectIds: anyNamed('subjectIds')),
    ).thenAnswer((invocation) async {
      final subjects = invocation.namedArguments[#subjectIds] as List<String>;
      return {
        for (final subject in subjects)
          if (_mutes.containsKey(subject)) subject: _mutes[subject]!,
      };
    });

    if (forBand && beaconId != null && _beacon != null) {
      when(
        _beaconRepositoryPort.getBeaconById(beaconId: beaconId),
      ).thenAnswer((_) async => _beacon!);
      when(
        _bandCandidatePort.candidatesFor(
          egoId: egoId,
          beaconId: beaconId,
          normalizedContext: normalizedContext,
        ),
      ).thenAnswer((_) async => List<BandCandidate>.from(_bandCandidates));
      when(
        _bandCandidatePort.recentlyForwardedTo(
          egoId: egoId,
          withinDays: kCapExplorationRecentForwardDays,
        ),
      ).thenAnswer((_) async => Set<String>.from(_recentlyForwarded));
    }
  }

  static (String, String) _canonicalPair(String a, String b) =>
      a.compareTo(b) <= 0 ? (a, b) : (b, a);
}

final class _CellKey {
  const _CellKey(this.witness, this.subject, this.tag);

  final String witness;
  final String subject;
  final String tag;

  @override
  bool operator ==(Object other) =>
      other is _CellKey &&
      witness == other.witness &&
      subject == other.subject &&
      tag == other.tag;

  @override
  int get hashCode => Object.hash(witness, subject, tag);
}

final class _CellAccumulator {
  double eOutOverride = -1;
  double eSeedOverride = -1;
  double _rawOut = 0;
  double _rawSeed = 0;

  void addOutcome({required int daysAgo, required int count}) {
    if (!isWithinEvidenceWindow(daysAgo)) {
      return;
    }
    _rawOut += count *
        capDecayFactor(
          daysAgo: daysAgo,
          halfLifeSeconds: kCapHalfLifeOutSeconds,
        );
  }

  void addSeed({required int daysAgo, required int count}) {
    if (!isWithinEvidenceWindow(daysAgo)) {
      return;
    }
    _rawSeed += count *
        capDecayFactor(
          daysAgo: daysAgo,
          halfLifeSeconds: kCapHalfLifeSeedSeconds,
        );
  }

  double get effectiveOut =>
      eOutOverride >= 0
          ? eOutOverride
          : capStrengthAtNow(rawSum: _rawOut, k: kCapKOut);

  double get effectiveSeed =>
      eSeedOverride >= 0
          ? eSeedOverride
          : capStrengthAtNow(rawSum: _rawSeed, k: kCapKSeed);
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    if (!iterator.moveNext()) {
      return null;
    }
    return iterator.current;
  }
}
