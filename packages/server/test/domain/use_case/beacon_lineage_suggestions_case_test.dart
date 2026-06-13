import 'package:test/test.dart';

import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/lineage_memory_fact.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/lineage_memory_read_port.dart';
import 'package:tentura_server/domain/use_case/beacon_lineage_suggestions_case.dart';
import 'package:tentura_server/env.dart';
import 'package:logging/logging.dart';

class _FakeLineageMemoryReadPort implements LineageMemoryReadPort {
  _FakeLineageMemoryReadPort({
    required this.edges,
    required this.whoHelped,
    this.whoRouted = const {},
    this.evaluations = const [],
    this.tags = const [],
  });

  final List<LineageForwardEdgeFact> edges;
  final Set<String> whoHelped;
  final Set<String> whoRouted;
  final List<LineageEvaluationFact> evaluations;
  final List<LineagePrivateTagFact> tags;

  @override
  Future<Set<String>> fetchAuthorBeaconIdsInSet({
    required String userId,
    required Set<String> beaconIds,
  }) async =>
      {};

  @override
  Future<List<String>> fetchLineageBeaconIds({
    required String rootBeaconId,
  }) async =>
      [rootBeaconId];

  @override
  Future<List<LineageForwardEdgeFact>> fetchMyLineageForwardEdges({
    required String userId,
    required Set<String> beaconIds,
  }) async =>
      edges;

  @override
  Future<List<LineageEvaluationFact>> fetchMyEvaluationsOnLineage({
    required String userId,
    required Set<String> beaconIds,
  }) async =>
      evaluations;

  @override
  Future<List<LineagePrivateTagFact>> fetchMyPrivateTags({
    required String userId,
  }) async =>
      tags;

  @override
  Future<Set<String>> fetchRecipientsWhoHelped({
    required Set<String> myTouchedBeaconIds,
    required Set<String> recipientIds,
  }) async =>
      whoHelped;

  @override
  Future<Set<String>> fetchRecipientsWhoRoutedToHelp({
    required String userId,
    required Set<String> myTouchedBeaconIds,
    required Set<String> recipientIds,
  }) async =>
      whoRouted;
}

class _FakeBeaconRepo implements BeaconRepositoryPort {
  _FakeBeaconRepo(this.beacon);

  final BeaconEntity beacon;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<BeaconEntity> getBeaconById({
    required String beaconId,
    String? filterByUserId,
  }) async =>
      beacon;
}

void main() {
  test('policy: classify, auto-select G1+G3, note selection', () async {
    final beacon = BeaconEntity(
      id: 'b-src',
      title: 't',
      author: UserEntity(id: 'author'),
      createdAt: DateTime.utc(2024),
      updatedAt: DateTime.utc(2024),
      state: 0,
    );
    final case_ = BeaconLineageSuggestionsCase(
      _FakeBeaconRepo(beacon),
      _FakeLineageMemoryReadPort(
        edges: [
          LineageForwardEdgeFact(
            recipientId: 'u-helped',
            note: 'older note',
            createdAt: DateTime.utc(2024, 1, 1),
            beaconId: 'b1',
            rejected: false,
          ),
          LineageForwardEdgeFact(
            recipientId: 'u-routed',
            note: 'newest note',
            createdAt: DateTime.utc(2024, 6, 1),
            beaconId: 'b1',
            rejected: false,
          ),
        ],
        whoHelped: {'u-helped'},
        whoRouted: {'u-routed'},
        evaluations: [
          const LineageEvaluationFact(
            evaluatedUserId: 'u-reviewed',
            value: 4,
            reasonTags: 'coordination',
          ),
        ],
        tags: [
          const LineagePrivateTagFact(subjectUserId: 'u-tagged', slug: 'driver'),
        ],
      ),
      env: Env.test(),
      logger: Logger('test'),
    );

    final result = await case_.load(beaconId: 'b-src', userId: 'me');
    expect(result.suggestedNote, 'newest note');
    final byUser = {for (final s in result.suggestions) s.userId: s};
    expect(byUser['u-helped']!.autoSelect, isTrue);
    expect(byUser['u-routed']!.autoSelect, isTrue);
    expect(byUser['u-reviewed']!.autoSelect, isFalse);
    expect(byUser['u-reviewed']!.group, LineageSuggestionGroup.reviewedPositive);
  });
}
