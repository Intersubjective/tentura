import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/beacon_lineage_visibility.dart';
import 'package:tentura_server/domain/evaluation/beacon_evaluation_value.dart';
import 'package:tentura_server/domain/entity/lineage_memory_fact.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/lineage_memory_read_port.dart';

import '_use_case_base.dart';

@Singleton(order: 2)
final class BeaconLineageSuggestionsCase extends UseCaseBase {
  BeaconLineageSuggestionsCase(
    this._beaconRepository,
    this._lineageMemoryReadPort, {
    required super.env,
    required super.logger,
  });

  final BeaconRepositoryPort _beaconRepository;
  final LineageMemoryReadPort _lineageMemoryReadPort;

  Future<LineageForwardSuggestions> load({
    required String beaconId,
    required String userId,
  }) async {
    final source = await _beaconRepository.getBeaconById(beaconId: beaconId);
    assertBeaconLineageSourceVisible(beacon: source, userId: userId);

    final rootBeaconId =
        source.lineageRootBeaconId ?? source.lineageParentBeaconId ?? source.id;
    final lineageBeaconIds =
        await _lineageMemoryReadPort.fetchLineageBeaconIds(
          rootBeaconId: rootBeaconId,
        );
    final lineageSet = lineageBeaconIds.toSet();

    final myEdges = await _lineageMemoryReadPort.fetchMyLineageForwardEdges(
      userId: userId,
      beaconIds: lineageSet,
    );
    final authoredIds = await _lineageMemoryReadPort.fetchAuthorBeaconIdsInSet(
      userId: userId,
      beaconIds: lineageSet,
    );
    final myTouchedBeaconIds = {
      ...myEdges.map((e) => e.beaconId),
      ...authoredIds,
    };

    final candidateRecipientIds = {
      ...myEdges.map((e) => e.recipientId),
    };

    final whoHelped = candidateRecipientIds.isEmpty || myTouchedBeaconIds.isEmpty
        ? <String>{}
        : await _lineageMemoryReadPort.fetchRecipientsWhoHelped(
            myTouchedBeaconIds: myTouchedBeaconIds,
            recipientIds: candidateRecipientIds,
          );

    final whoRouted = candidateRecipientIds.isEmpty || myTouchedBeaconIds.isEmpty
        ? <String>{}
        : await _lineageMemoryReadPort.fetchRecipientsWhoRoutedToHelp(
            userId: userId,
            myTouchedBeaconIds: myTouchedBeaconIds,
            recipientIds: candidateRecipientIds,
          );

    final evaluations =
        await _lineageMemoryReadPort.fetchMyEvaluationsOnLineage(
          userId: userId,
          beaconIds: lineageSet,
        );

    final privateTags = await _lineageMemoryReadPort.fetchMyPrivateTags(
      userId: userId,
    );

    final pushbackCounts = _pushbackCountsByRecipient(myEdges);
    final suggestedNote = _selectSuggestedNote(myEdges);

    final classified = <String, _ClassifiedSuggestion>{};

    for (final recipientId in whoHelped) {
      if (_isPushbackSuppressed(recipientId, pushbackCounts)) continue;
      if (_hasSinglePushback(recipientId, pushbackCounts)) continue;
      classified[recipientId] = _ClassifiedSuggestion(
        group: LineageSuggestionGroup.involved,
        reasonCode: LineageSuggestionReasonCodes.helpedBefore,
      );
    }

    for (final eval in evaluations) {
      if (!BeaconEvaluationValue.isPositive(eval.value)) continue;
      final uid = eval.evaluatedUserId;
      if (_isPushbackSuppressed(uid, pushbackCounts)) continue;
      if (_hasSinglePushback(uid, pushbackCounts)) continue;
      if (classified.containsKey(uid)) continue;
      final tagArg = eval.reasonTags.trim().isEmpty
          ? null
          : eval.reasonTags.split(',').first.trim();
      classified[uid] = _ClassifiedSuggestion(
        group: LineageSuggestionGroup.reviewedPositive,
        reasonCode: LineageSuggestionReasonCodes.reviewedHelpful,
        reasonArg: tagArg,
      );
    }

    for (final recipientId in whoRouted) {
      if (_isPushbackSuppressed(recipientId, pushbackCounts)) continue;
      if (_hasSinglePushback(recipientId, pushbackCounts)) continue;
      if (classified.containsKey(recipientId)) continue;
      classified[recipientId] = _ClassifiedSuggestion(
        group: LineageSuggestionGroup.routedHelp,
        reasonCode: LineageSuggestionReasonCodes.routedHelp,
      );
    }

    for (final tag in privateTags) {
      final uid = tag.subjectUserId;
      if (_isPushbackSuppressed(uid, pushbackCounts)) continue;
      if (_hasSinglePushback(uid, pushbackCounts)) continue;
      if (classified.containsKey(uid)) continue;
      classified[uid] = _ClassifiedSuggestion(
        group: LineageSuggestionGroup.privateTag,
        reasonCode: LineageSuggestionReasonCodes.privateTag,
        reasonArg: tag.slug,
      );
    }

    const groupOrder = {
      LineageSuggestionGroup.involved: 0,
      LineageSuggestionGroup.reviewedPositive: 1,
      LineageSuggestionGroup.routedHelp: 2,
      LineageSuggestionGroup.privateTag: 3,
    };

    final suggestions = classified.entries
        .map(
          (e) => LineageForwardSuggestion(
            userId: e.key,
            group: e.value.group,
            reasonCode: e.value.reasonCode,
            reasonArg: e.value.reasonArg,
            autoSelect: e.value.group == LineageSuggestionGroup.involved ||
                e.value.group == LineageSuggestionGroup.routedHelp,
          ),
        )
        .toList()
      ..sort(
        (a, b) => groupOrder[a.group]!.compareTo(groupOrder[b.group]!),
      );

    return LineageForwardSuggestions(
      sourceBeaconId: source.id,
      rootBeaconId: rootBeaconId,
      suggestedNote: suggestedNote,
      suggestions: suggestions,
    );
  }

  Map<String, int> _pushbackCountsByRecipient(
    List<LineageForwardEdgeFact> edges,
  ) {
    final counts = <String, Set<String>>{};
    for (final edge in edges.where((e) => e.rejected)) {
      counts.putIfAbsent(edge.recipientId, () => {}).add(edge.beaconId);
    }
    return counts.map((k, v) => MapEntry(k, v.length));
  }

  bool _hasSinglePushback(String userId, Map<String, int> counts) =>
      counts[userId] == 1;

  bool _isPushbackSuppressed(String userId, Map<String, int> counts) =>
      (counts[userId] ?? 0) >= 2;

  String _selectSuggestedNote(List<LineageForwardEdgeFact> edges) {
    final withNote = edges.where((e) => e.note.trim().isNotEmpty).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return withNote.isEmpty ? '' : withNote.first.note;
  }
}

class _ClassifiedSuggestion {
  const _ClassifiedSuggestion({
    required this.group,
    required this.reasonCode,
    this.reasonArg,
  });

  final LineageSuggestionGroup group;
  final String reasonCode;
  final String? reasonArg;
}
