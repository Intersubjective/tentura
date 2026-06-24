import 'package:test/test.dart';

import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/lineage_memory_fact.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/lineage_memory_read_port.dart';
import 'package:tentura_server/domain/use_case/beacon_lineage_suggestions_case.dart';
import 'package:tentura_server/env.dart';
import 'package:logging/logging.dart';

import '../../support/fake_beacon_access_guard.dart';

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

BeaconLineageSuggestionsCase _caseFor({
  required BeaconEntity beacon,
  required _FakeLineageMemoryReadPort memory,
}) =>
    BeaconLineageSuggestionsCase(
      _FakeBeaconRepo(beacon),
      memory,
      FakeBeaconAccessGuard(),
      env: Env.test(),
      logger: Logger('test'),
    );

BeaconEntity _forkedBeacon({String id = 'b-src', String parentId = 'b-parent'}) =>
    BeaconEntity(
      id: id,
      title: 't',
      author: const UserEntity(id: 'author'),
      createdAt: DateTime.utc(2024),
      updatedAt: DateTime.utc(2024),
      lineageParentBeaconId: parentId,
      lineageRootBeaconId: parentId,
    );

void main() {
  test('policy: classify, auto-select G1+G3, note selection', () async {
    final case_ = _caseFor(
      beacon: _forkedBeacon(),
      memory: _FakeLineageMemoryReadPort(
        edges: [
          LineageForwardEdgeFact(
            recipientId: 'u-helped',
            note: 'older note',
            createdAt: DateTime.utc(2024),
            beaconId: 'b1',
            rejected: false,
          ),
          LineageForwardEdgeFact(
            recipientId: 'u-routed',
            note: 'newest note',
            createdAt: DateTime.utc(2024, 6),
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
    );

    final result = await case_.load(beaconId: 'b-src', userId: 'me');
    expect(result.suggestedNote, 'newest note');
    final byUser = {for (final s in result.suggestions) s.userId: s};
    expect(byUser['u-helped']!.autoSelect, isTrue);
    expect(byUser['u-routed']!.autoSelect, isTrue);
    expect(byUser['u-reviewed']!.autoSelect, isFalse);
    expect(byUser['u-reviewed']!.group, LineageSuggestionGroup.reviewedPositive);
    expect(byUser.containsKey('u-tagged'), isFalse);
  });

  test('non-fork beacon returns empty suggestions even with private tags', () async {
    final beacon = BeaconEntity(
      id: 'b-new',
      title: 't',
      author: const UserEntity(id: 'author'),
      createdAt: DateTime.utc(2024),
      updatedAt: DateTime.utc(2024),
    );
    final case_ = _caseFor(
      beacon: beacon,
      memory: _FakeLineageMemoryReadPort(
        edges: const [],
        whoHelped: const {},
        tags: const [
          LineagePrivateTagFact(subjectUserId: 'u-tagged', slug: 'driver'),
        ],
      ),
    );

    final result = await case_.load(beaconId: 'b-new', userId: 'me');
    expect(result.suggestions, isEmpty);
    expect(result.suggestedNote, isEmpty);
  });

  test('private tag only suggests lineage forward recipients', () async {
    final case_ = _caseFor(
      beacon: _forkedBeacon(),
      memory: _FakeLineageMemoryReadPort(
        edges: [
          LineageForwardEdgeFact(
            recipientId: 'u-forwarded',
            note: '',
            createdAt: DateTime.utc(2024),
            beaconId: 'b1',
            rejected: false,
          ),
        ],
        whoHelped: const {},
        tags: const [
          LineagePrivateTagFact(subjectUserId: 'u-forwarded', slug: 'driver'),
          LineagePrivateTagFact(subjectUserId: 'u-stranger', slug: 'cook'),
        ],
      ),
    );

    final result = await case_.load(beaconId: 'b-src', userId: 'me');
    final ids = result.suggestions.map((s) => s.userId).toSet();
    expect(ids, contains('u-forwarded'));
    expect(ids, isNot(contains('u-stranger')));
  });
}
