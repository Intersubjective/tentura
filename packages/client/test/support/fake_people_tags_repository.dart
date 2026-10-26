import 'dart:async';

import 'package:logging/logging.dart';

import 'package:tentura/env.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';
import 'package:tentura/features/people_tags/domain/port/people_tags_repository_port.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';

import 'test_realtime_sync.dart';

/// In-memory people-tags repository for widget tests of surfaces that show a
/// person's tags.
final class FakePeopleTagsRepository implements PeopleTagsRepositoryPort {
  FakePeopleTagsRepository({
    this.tagList = const [],
    this.memberList = const [],
    this.autoByPerson = const {},
  });

  List<PersonTag> tagList;
  List<PersonTagMembers> memberList;

  /// Automatic tags per person id, as the server reports them.
  Map<String, List<PersonAutoTagOf>> autoByPerson;

  final appliedOps = <List<PersonTagMemberOp>>[];

  @override
  Future<List<PersonTag>> personTags() async => tagList;

  @override
  Future<List<PersonTagMembers>> personTagMemberships() async => memberList;

  @override
  Future<List<PersonAutoTag>> personAutoTags() async => const [];

  @override
  Future<PersonTagSuggestionState> personTagSuggestionState() async =>
      const PersonTagSuggestionState(canSuggest: false, disabled: false);

  @override
  Future<PersonTagsOf> personTagsOf(String personId) async => PersonTagsOf(
    own: [
      for (final m in memberList)
        if (m.personIds.contains(personId)) m.tagId,
    ],
    auto: autoByPerson[personId] ?? const [],
  );

  @override
  Future<void> personTagMembersApply({
    required List<PersonTagMemberOp> ops,
    required String clientOpId,
  }) async {
    appliedOps.add(ops);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// A loaded [PeopleTagsCase] over [repository], with what it needs to be
/// disposed.
final class PeopleTagsTestRig {
  PeopleTagsTestRig._(this.repository, this.peopleTags, this._realtimePort);

  static Future<PeopleTagsTestRig> create(
    FakePeopleTagsRepository repository,
  ) async {
    final realtime = buildTestRealtimeSync();
    final peopleTags = PeopleTagsCase(
      repository,
      realtime.case_,
      env: const Env(),
      logger: Logger('test'),
    );
    await peopleTags.load();
    return PeopleTagsTestRig._(repository, peopleTags, realtime.port);
  }

  final FakePeopleTagsRepository repository;
  final PeopleTagsCase peopleTags;
  final TestRealtimeSyncPort _realtimePort;

  Future<void> dispose() async {
    await peopleTags.dispose();
    await _realtimePort.dispose();
  }
}
