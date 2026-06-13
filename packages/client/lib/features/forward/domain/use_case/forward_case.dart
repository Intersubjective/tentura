import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/port/capability_repository_port.dart';
import 'package:tentura/domain/use_case/use_case_base.dart';
import 'package:tentura/features/auth/domain/port/auth_local_repository_port.dart';
import 'package:tentura/features/beacon_room/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';

import '../../data/repository/forward_repository.dart';
import '../entity/candidate_involvement.dart';
import '../entity/forward_candidate.dart';
import '../entity/forward_load.dart';
import '../entity/lineage_suggestion_group.dart';

@singleton
final class ForwardCase extends UseCaseBase {
  ForwardCase(
    this._forwardRepository,
    this._authLocalRepository,
    this._factCards,
    this._profileRepository, {
    required super.env,
    required super.logger,
  });

  final ForwardRepository _forwardRepository;

  final AuthLocalRepositoryPort _authLocalRepository;

  final BeaconFactCardRepository _factCards;

  final ProfileRepositoryPort _profileRepository;

  Future<Iterable<Profile>> fetchForwardCandidates({String context = ''}) =>
      _forwardRepository.fetchForwardCandidates(context: context);

  Future<BeaconInvolvementData> fetchBeaconInvolvement({
    required String beaconId,
  }) =>
      _forwardRepository.fetchBeaconInvolvement(beaconId: beaconId);

  Future<String> getCurrentAccountId() =>
      _authLocalRepository.getCurrentAccountId();

  Future<ForwardLoad> loadForwardCandidates({
    required String beaconId,
    String context = '',
  }) async {
    final results = await Future.wait([
      _forwardRepository.fetchForwardCandidates(context: context),
      _forwardRepository.fetchBeaconInvolvement(beaconId: beaconId),
      _forwardRepository.fetchLineageForwardSuggestions(beaconId: beaconId),
    ]);
    final profiles = results[0] as Iterable<Profile>;
    final involvement = results[1] as BeaconInvolvementData;
    final lineage = results[2] as LineageForwardSuggestions;
    final myId = await getCurrentAccountId();

    var candidates = profiles
        .where((p) => p.id != myId)
        .map(
          (p) => ForwardCandidate(
            profile: p,
            involvement: computeInvolvement(p.id, involvement),
            myForwardNote: involvement.myForwardedRecipientNotes[p.id],
            forwardEdgeId: involvement.myForwardedRecipientEdgeIds[p.id],
            recipientReadAt: involvement.myForwardedRecipientReadAts[p.id],
          ),
        )
        .toList()
      ..sort((a, b) => b.mrScore.compareTo(a.mrScore));

    final ids = candidates.map((c) => c.id).toList();
    if (ids.isNotEmpty) {
      try {
        final needs = involvement.beacon.needs;
        final prioritizeList = needs
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList()
          ..sort();
        final topCaps = await fetchTopCapabilitiesForCandidates(
          ids,
          prioritizeSlugs: prioritizeList,
        );
        candidates = candidates
            .map(
              (c) => c.copyWith(topCapabilities: topCaps[c.id] ?? []),
            )
            .toList();
      } catch (_) {
        // Non-critical: capability hints are best-effort.
      }
    }

    final profileById = {
      for (final c in candidates) c.id: c.profile,
    };
    final missingIds = lineage.suggestions
        .map((s) => s.userId)
        .where((id) => !profileById.containsKey(id))
        .toSet();
    if (missingIds.isNotEmpty) {
      final extras = await _profileRepository.fetchProfilesByIds(missingIds);
      for (final p in extras) {
        profileById[p.id] = p;
      }
    }

    const groupOrder = {
      LineageSuggestionGroup.involved: 0,
      LineageSuggestionGroup.reviewedPositive: 1,
      LineageSuggestionGroup.routedHelp: 2,
      LineageSuggestionGroup.privateTag: 3,
    };

    final lineageSuggestions = <ForwardCandidate>[];
    for (final s in lineage.suggestions) {
      final profile = profileById[s.userId];
      if (profile == null || !profile.isSeeingMe) continue;
      lineageSuggestions.add(
        ForwardCandidate(
          profile: profile,
          involvement: computeInvolvement(s.userId, involvement),
          lineageGroup: s.group,
          lineageReasonCode: s.reasonCode,
          lineageReasonArg: s.reasonArg,
          lineageAutoSelect: s.autoSelect,
        ),
      );
    }
    lineageSuggestions.sort(
      (a, b) => groupOrder[a.lineageGroup]!.compareTo(groupOrder[b.lineageGroup]!),
    );

    final autoSelectIds = lineageSuggestions
        .where((c) => c.lineageAutoSelect)
        .map((c) => c.id)
        .toSet();

    return ForwardLoad(
      candidates: candidates,
      lineageSuggestions: lineageSuggestions,
      suggestedNote: lineage.suggestedNote,
      autoSelectIds: autoSelectIds,
      beacon: involvement.beacon,
    );
  }

  Future<List<LineagePreviewRow>> loadLineageSuggestionsPreview({
    required String beaconId,
  }) async {
    final lineage = await _forwardRepository.fetchLineageForwardSuggestions(
      beaconId: beaconId,
    );
    if (lineage.suggestions.isEmpty) return const [];
    final ids = lineage.suggestions.map((s) => s.userId).toSet();
    final profiles = await _profileRepository.fetchProfilesByIds(ids);
    final byId = {for (final p in profiles) p.id: p};
    final rows = <LineagePreviewRow>[];
    for (final s in lineage.suggestions) {
      final profile = byId[s.userId];
      if (profile == null) continue;
      rows.add(
        LineagePreviewRow(
          profile: profile,
          group: s.group,
          reasonCode: s.reasonCode,
          reasonArg: s.reasonArg,
        ),
      );
    }
    return rows;
  }

  static CandidateInvolvement computeInvolvement(
    String userId,
    BeaconInvolvementData inv,
  ) {
    if (userId == inv.beacon.author.id) {
      return CandidateInvolvement.author;
    }
    if (inv.helpOfferedIds.contains(userId)) {
      return CandidateInvolvement.helpOffered;
    }
    if (inv.withdrawnIds.contains(userId)) {
      return CandidateInvolvement.withdrawn;
    }
    if (inv.myForwardedRecipientNotes.containsKey(userId)) {
      return CandidateInvolvement.forwardedByMe;
    }
    if (inv.rejectedIds.contains(userId)) {
      return CandidateInvolvement.declined;
    }
    if (inv.onwardForwarderIds.contains(userId)) {
      return CandidateInvolvement.forwarded;
    }
    if (inv.watchingIds.contains(userId)) {
      return CandidateInvolvement.watching;
    }
    if (inv.forwardedToIds.contains(userId)) {
      return CandidateInvolvement.forwarded;
    }
    return CandidateInvolvement.unseen;
  }

  Future<List<BeaconFactCard>> fetchPublicFactCards(String beaconId) async {
    final rows = await _factCards.list(beaconId: beaconId);
    return [
      for (final f in rows)
        if (f.visibility == BeaconFactCardVisibilityBits.public) f,
    ];
  }

  Future<Map<String, List<String>>> fetchTopCapabilitiesForCandidates(
    List<String> subjectIds, {
    int limit = 2,
    List<String> prioritizeSlugs = const [],
  }) => GetIt.I<CapabilityRepositoryPort>().fetchTopCapabilitiesBatch(
    subjectIds: subjectIds,
    limit: limit,
    prioritizeSlugs: prioritizeSlugs,
  );

  Future<String> forwardBeacon({
    required String beaconId,
    required List<String> recipientIds,
    String? note,
    Map<String, String>? perRecipientNotes,
    Map<String, List<String>>? recipientReasons,
    String? context,
    String? parentEdgeId,
  }) =>
      _forwardRepository.forwardBeacon(
        beaconId: beaconId,
        recipientIds: recipientIds,
        note: note,
        perRecipientNotes: perRecipientNotes,
        recipientReasons: recipientReasons,
        context: context,
        parentEdgeId: parentEdgeId,
      );

  Future<bool> cancelForward(String edgeId) =>
      _forwardRepository.cancelForward(edgeId);

  Future<bool> updateForward({
    required String edgeId,
    String? note,
    List<String>? reasonSlugs,
  }) =>
      _forwardRepository.updateForward(
        edgeId: edgeId,
        note: note,
        reasonSlugs: reasonSlugs,
      );
}
