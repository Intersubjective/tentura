import 'package:test/test.dart';

import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/lineage_memory_fact.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/evaluation/beacon_evaluation_value.dart';
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

LineageForwardEdgeFact _edge({
  required String recipientId,
  String note = '',
  DateTime? createdAt,
  String beaconId = 'b1',
  bool rejected = false,
}) =>
    LineageForwardEdgeFact(
      recipientId: recipientId,
      note: note,
      createdAt: createdAt ?? DateTime.utc(2024),
      beaconId: beaconId,
      rejected: rejected,
    );

Future<LineageForwardSuggestions> _load(
  _FakeLineageMemoryReadPort memory, {
  BeaconEntity? beacon,
}) =>
    _caseFor(beacon: beacon ?? _forkedBeacon(), memory: memory).load(
      beaconId: (beacon ?? _forkedBeacon()).id,
      userId: 'me',
    );

void main() {
  group('policy classification (ADR 0004)', () {
    test('classify G1–G4, auto-select G1+G3 only, newest note', () async {
      final result = await _load(
        _FakeLineageMemoryReadPort(
          edges: [
            _edge(recipientId: 'u-helped', note: 'older note'),
            _edge(
              recipientId: 'u-routed',
              note: 'newest note',
              createdAt: DateTime.utc(2024, 6),
            ),
            _edge(recipientId: 'u-tagged'),
          ],
          whoHelped: {'u-helped'},
          whoRouted: {'u-routed'},
          evaluations: const [
            LineageEvaluationFact(
              evaluatedUserId: 'u-reviewed',
              value: BeaconEvaluationValue.pos1,
              reasonTags: 'coordination',
            ),
          ],
          tags: const [
            LineagePrivateTagFact(subjectUserId: 'u-tagged', slug: 'driver'),
          ],
        ),
      );

      expect(result.suggestedNote, 'newest note');
      final byUser = {for (final s in result.suggestions) s.userId: s};
      expect(byUser.keys, containsAll(['u-helped', 'u-reviewed', 'u-routed', 'u-tagged']));

      expect(byUser['u-helped']!.group, LineageSuggestionGroup.involved);
      expect(byUser['u-helped']!.reasonCode, LineageSuggestionReasonCodes.helpedBefore);
      expect(byUser['u-helped']!.autoSelect, isTrue);

      expect(byUser['u-reviewed']!.group, LineageSuggestionGroup.reviewedPositive);
      expect(byUser['u-reviewed']!.reasonCode, LineageSuggestionReasonCodes.reviewedHelpful);
      expect(byUser['u-reviewed']!.reasonArg, 'coordination');
      expect(byUser['u-reviewed']!.autoSelect, isFalse);

      expect(byUser['u-routed']!.group, LineageSuggestionGroup.routedHelp);
      expect(byUser['u-routed']!.reasonCode, LineageSuggestionReasonCodes.routedHelp);
      expect(byUser['u-routed']!.autoSelect, isTrue);

      expect(byUser['u-tagged']!.group, LineageSuggestionGroup.privateTag);
      expect(byUser['u-tagged']!.reasonCode, LineageSuggestionReasonCodes.privateTag);
      expect(byUser['u-tagged']!.reasonArg, 'driver');
      expect(byUser['u-tagged']!.autoSelect, isFalse);
    });

    test('sorts suggestions G1 → G2 → G3 → G4', () async {
      final result = await _load(
        _FakeLineageMemoryReadPort(
          edges: [
            _edge(recipientId: 'u-g1'),
            _edge(recipientId: 'u-g3'),
            _edge(recipientId: 'u-g4'),
          ],
          whoHelped: {'u-g1'},
          whoRouted: {'u-g3'},
          evaluations: const [
            LineageEvaluationFact(
              evaluatedUserId: 'u-g2',
              value: BeaconEvaluationValue.pos2,
              reasonTags: '',
            ),
          ],
          tags: const [
            LineagePrivateTagFact(subjectUserId: 'u-g4', slug: 'cook'),
          ],
        ),
      );

      expect(
        result.suggestions.map((s) => s.group).toList(),
        [
          LineageSuggestionGroup.involved,
          LineageSuggestionGroup.reviewedPositive,
          LineageSuggestionGroup.routedHelp,
          LineageSuggestionGroup.privateTag,
        ],
      );
    });

    test('higher-priority group wins when the same user matches multiple facts', () async {
      final result = await _load(
        _FakeLineageMemoryReadPort(
          edges: [_edge(recipientId: 'u-dup')],
          whoHelped: {'u-dup'},
          whoRouted: {'u-dup'},
          evaluations: const [
            LineageEvaluationFact(
              evaluatedUserId: 'u-dup',
              value: BeaconEvaluationValue.pos1,
              reasonTags: 'ignored',
            ),
          ],
          tags: const [
            LineagePrivateTagFact(subjectUserId: 'u-dup', slug: 'ignored'),
          ],
        ),
      );

      expect(result.suggestions, hasLength(1));
      expect(result.suggestions.single.group, LineageSuggestionGroup.involved);
      expect(result.suggestions.single.autoSelect, isTrue);
    });

    for (final row in <({int value, String label})>[
      (value: BeaconEvaluationValue.neg1, label: 'negative'),
      (value: BeaconEvaluationValue.zero, label: 'neutral'),
      (value: BeaconEvaluationValue.noBasis, label: 'no basis'),
    ]) {
      test('G2 excludes ${row.label} evaluations', () async {
        final result = await _load(
          _FakeLineageMemoryReadPort(
            edges: const [],
            whoHelped: const {},
            evaluations: [
              LineageEvaluationFact(
                evaluatedUserId: 'u-eval',
                value: row.value,
                reasonTags: 'tag',
              ),
            ],
          ),
        );

        expect(result.suggestions, isEmpty);
      });
    }
  });

  group('pushback de-prioritize and suppress (ADR 0004)', () {
    for (final row in <({
      String label,
      List<LineageForwardEdgeFact> edges,
      bool expectSuggested,
    })>[
      (
        label: 'G1 without pushback is suggested',
        edges: [_edge(recipientId: 'u1')],
        expectSuggested: true,
      ),
      (
        label: 'G1 single pushback de-prioritizes (one beacon)',
        edges: [
          _edge(recipientId: 'u1'),
          _edge(recipientId: 'u1', beaconId: 'b1', rejected: true),
        ],
        expectSuggested: false,
      ),
      (
        label: 'G1 double pushback suppresses (two beacons)',
        edges: [
          _edge(recipientId: 'u1'),
          _edge(recipientId: 'u1', beaconId: 'b1', rejected: true),
          _edge(recipientId: 'u1', beaconId: 'b2', rejected: true),
        ],
        expectSuggested: false,
      ),
    ]) {
      test(row.label, () async {
        final result = await _load(
          _FakeLineageMemoryReadPort(
            edges: row.edges,
            whoHelped: {'u1'},
          ),
        );

        final ids = result.suggestions.map((s) => s.userId).toSet();
        expect(ids.contains('u1'), row.expectSuggested);
      });
    }

    test('G2 single pushback de-prioritizes reviewed user', () async {
      final result = await _load(
        _FakeLineageMemoryReadPort(
          edges: [_edge(recipientId: 'u-reviewed', beaconId: 'b1', rejected: true)],
          whoHelped: const {},
          evaluations: const [
            LineageEvaluationFact(
              evaluatedUserId: 'u-reviewed',
              value: BeaconEvaluationValue.pos1,
              reasonTags: 'coordination',
            ),
          ],
        ),
      );

      expect(result.suggestions, isEmpty);
    });

    test('G3 single pushback de-prioritizes routed user', () async {
      final result = await _load(
        _FakeLineageMemoryReadPort(
          edges: [
            _edge(recipientId: 'u-routed'),
            _edge(recipientId: 'u-routed', beaconId: 'b1', rejected: true),
          ],
          whoHelped: const {},
          whoRouted: {'u-routed'},
        ),
      );

      expect(result.suggestions, isEmpty);
    });

    test('G4 single pushback de-prioritizes private-tag recipient', () async {
      final result = await _load(
        _FakeLineageMemoryReadPort(
          edges: [
            _edge(recipientId: 'u-tagged'),
            _edge(recipientId: 'u-tagged', beaconId: 'b1', rejected: true),
          ],
          whoHelped: const {},
          tags: const [
            LineagePrivateTagFact(subjectUserId: 'u-tagged', slug: 'driver'),
          ],
        ),
      );

      expect(result.suggestions, isEmpty);
    });
  });

  group('non-fork beacon', () {
    test('returns empty suggestions even with private tags', () async {
      final beacon = BeaconEntity(
        id: 'b-new',
        title: 't',
        author: const UserEntity(id: 'author'),
        createdAt: DateTime.utc(2024),
        updatedAt: DateTime.utc(2024),
      );
      final result = await _load(
        _FakeLineageMemoryReadPort(
          edges: const [],
          whoHelped: const {},
          tags: const [
            LineagePrivateTagFact(subjectUserId: 'u-tagged', slug: 'driver'),
          ],
        ),
        beacon: beacon,
      );

      expect(result.suggestions, isEmpty);
      expect(result.suggestedNote, isEmpty);
      expect(result.rootBeaconId, beacon.id);
    });
  });

  group('private tag scope', () {
    test('G4 only suggests lineage forward recipients', () async {
      final result = await _load(
        _FakeLineageMemoryReadPort(
          edges: [_edge(recipientId: 'u-forwarded')],
          whoHelped: const {},
          tags: const [
            LineagePrivateTagFact(subjectUserId: 'u-forwarded', slug: 'driver'),
            LineagePrivateTagFact(subjectUserId: 'u-stranger', slug: 'cook'),
          ],
        ),
      );

      final ids = result.suggestions.map((s) => s.userId).toSet();
      expect(ids, {'u-forwarded'});
      expect(result.suggestions.single.group, LineageSuggestionGroup.privateTag);
    });
  });
}
