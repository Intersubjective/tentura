import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';
import 'package:tentura/features/people_tags/domain/port/people_tags_repository_port.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';

import '../../support/test_realtime_sync.dart';

const _tagA = PersonTag(
  id: 'Ta',
  name: 'Neighbours',
  glyph: 'N',
  color: 0,
  ord: 0,
);
const _tagB = PersonTag(
  id: 'Tb',
  name: 'Climbers',
  glyph: 'C',
  color: 1,
  ord: 1,
);

/// Only the calls B1 exercises are implemented; any other call fails loudly.
final class _FakePeopleTagsRepository implements PeopleTagsRepositoryPort {
  List<PersonTag> tagList = [_tagA, _tagB];
  List<PersonTagMembers> memberList = [
    const PersonTagMembers(tagId: 'Ta', personIds: ['Uann', 'Ubob']),
    const PersonTagMembers(tagId: 'Tb', personIds: ['Uann']),
  ];

  int tagsCalls = 0;
  int membershipsCalls = 0;
  final appliedOpIds = <String>[];
  final appliedOps = <List<PersonTagMemberOp>>[];

  /// Called for every apply; throw to simulate a failure.
  FutureOr<void> Function(int attempt)? onApply;

  @override
  Future<List<PersonTag>> personTags() async {
    tagsCalls++;
    return tagList;
  }

  @override
  Future<List<PersonTagMembers>> personTagMemberships() async {
    membershipsCalls++;
    return memberList;
  }

  @override
  Future<void> personTagMembersApply({
    required List<PersonTagMemberOp> ops,
    required String clientOpId,
  }) async {
    appliedOpIds.add(clientOpId);
    appliedOps.add(ops);
    await onApply?.call(appliedOpIds.length);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  late _FakePeopleTagsRepository repository;
  late TestRealtimeSyncPort realtimePort;
  late PeopleTagsCase case_;

  PeopleTagsCase build() {
    final realtime = buildTestRealtimeSync();
    realtimePort = realtime.port;
    return PeopleTagsCase(
      repository,
      realtime.case_,
      env: const Env(),
      logger: Logger('test'),
    );
  }

  RealtimeEntityChange tagChange(int revision) => RealtimeEntityChange(
    kind: RealtimeEntityKind.personTag,
    aggregateId: 'Uowner',
    operation: RealtimeOperation.update,
    source: RealtimeChangeSource.serverInvalidation,
    revision: BigInt.from(revision),
  );

  setUp(() => repository = _FakePeopleTagsRepository());

  group('people tags membership index', () {
    setUp(() async {
      case_ = build();
      await case_.load();
    });

    tearDown(() async {
      await case_.dispose();
      await realtimePort.dispose();
    });

    test('is seeded from the memberships query and lists tags in order', () {
      expect(case_.tags.map((t) => t.id), ['Ta', 'Tb']);
      expect(repository.membershipsCalls, 1);
    });

    test('answers who is in a tag', () {
      expect(case_.peopleInTag('Ta'), {'Uann', 'Ubob'});
      expect(case_.peopleInTag('Tb'), {'Uann'});
      expect(case_.peopleInTag('Tunknown'), isEmpty);
    });

    test('answers which tags a person has', () {
      expect(case_.tagsOfPerson('Uann'), {'Ta', 'Tb'});
      expect(case_.tagsOfPerson('Ubob'), {'Ta'});
      expect(case_.tagsOfPerson('Unobody'), isEmpty);
    });
  });

  group('people tags optimistic membership edits', () {
    setUp(() async {
      case_ = build();
      await case_.load();
    });

    tearDown(() async {
      await case_.dispose();
      await realtimePort.dispose();
    });

    test(
      'adding a person shows in the index before the server answers',
      () async {
        final gate = Completer<void>();
        repository.onApply = (_) => gate.future;

        final pending = case_.addToTag(personId: 'Ubob', tagId: 'Tb');
        await Future<void>.delayed(Duration.zero);

        expect(case_.tagsOfPerson('Ubob'), {'Ta', 'Tb'});
        expect(case_.peopleInTag('Tb'), {'Uann', 'Ubob'});

        gate.complete();
        await pending;
        expect(case_.tagsOfPerson('Ubob'), {'Ta', 'Tb'});
        expect(repository.appliedOps.single.single.add, isTrue);
      },
    );

    test(
      'removing a person is applied to the index and sent as a remove',
      () async {
        await case_.removeFromTag(personId: 'Uann', tagId: 'Ta');

        expect(case_.peopleInTag('Ta'), {'Ubob'});
        expect(case_.tagsOfPerson('Uann'), {'Tb'});
        final op = repository.appliedOps.single.single;
        expect(
          (op.tagId, op.personId, op.add),
          ('Ta', 'Uann', false),
        );
      },
    );

    test('a failed add is rolled back and the error is surfaced', () async {
      repository.onApply = (_) => throw StateError('offline');

      await expectLater(
        case_.addToTag(personId: 'Ubob', tagId: 'Tb'),
        throwsA(anything),
      );

      expect(case_.tagsOfPerson('Ubob'), {'Ta'});
      expect(case_.peopleInTag('Tb'), {'Uann'});
    });

    test('a failed remove is rolled back and the error is surfaced', () async {
      repository.onApply = (_) => throw StateError('offline');

      await expectLater(
        case_.removeFromTag(personId: 'Uann', tagId: 'Ta'),
        throwsA(anything),
      );

      expect(case_.peopleInTag('Ta'), {'Uann', 'Ubob'});
      expect(case_.tagsOfPerson('Uann'), {'Ta', 'Tb'});
    });

    test(
      'a retry after a transient failure reuses the same clientOpId',
      () async {
        repository.onApply = (attempt) {
          if (attempt == 1) throw StateError('timeout');
        };

        await case_.addToTag(personId: 'Ubob', tagId: 'Tb');

        expect(repository.appliedOpIds, hasLength(2));
        expect(repository.appliedOpIds.first, repository.appliedOpIds.last);
        expect(repository.appliedOpIds.first, isNotEmpty);
        expect(case_.tagsOfPerson('Ubob'), {'Ta', 'Tb'});
      },
    );

    test('two separate edits get different clientOpIds', () async {
      await case_.addToTag(personId: 'Ubob', tagId: 'Tb');
      await case_.removeFromTag(personId: 'Ubob', tagId: 'Tb');

      expect(repository.appliedOpIds.toSet(), hasLength(2));
    });
  });

  group('people tags realtime refresh', () {
    test('a change of another kind does not refetch anything', () {
      fakeAsync((async) {
        case_ = build();
        unawaited(case_.load());
        async.flushMicrotasks();
        final tags = repository.tagsCalls;
        final memberships = repository.membershipsCalls;

        realtimePort.emitChange(
          RealtimeEntityChange(
            kind: RealtimeEntityKind.contact,
            aggregateId: 'Uowner',
            operation: RealtimeOperation.update,
            source: RealtimeChangeSource.serverInvalidation,
            revision: BigInt.from(50),
          ),
        );
        async.elapse(const Duration(seconds: 5));

        expect(repository.tagsCalls, tags);
        expect(repository.membershipsCalls, memberships);

        unawaited(case_.dispose());
        unawaited(realtimePort.dispose());
        async.flushMicrotasks();
      });
    });

    test('a burst of person_tag changes triggers one debounced refetch', () {
      fakeAsync((async) {
        case_ = build();
        unawaited(case_.load());
        async.flushMicrotasks();
        final tagsBefore = repository.tagsCalls;
        final membershipsBefore = repository.membershipsCalls;

        repository.memberList = const [
          PersonTagMembers(tagId: 'Ta', personIds: ['Ubob']),
        ];
        realtimePort
          ..emitChange(tagChange(5))
          ..emitChange(tagChange(6))
          ..emitChange(tagChange(7));
        async.elapse(const Duration(seconds: 5));

        expect(repository.tagsCalls - tagsBefore, 1);
        expect(repository.membershipsCalls - membershipsBefore, 1);
        expect(case_.peopleInTag('Ta'), {'Ubob'});

        unawaited(case_.dispose());
        unawaited(realtimePort.dispose());
        async.flushMicrotasks();
      });
    });

    test('a change with a revision older than one already seen is ignored', () {
      fakeAsync((async) {
        case_ = build();
        unawaited(case_.load());
        async.flushMicrotasks();

        realtimePort.emitChange(tagChange(9));
        async.elapse(const Duration(seconds: 5));
        final membershipsAfterFresh = repository.membershipsCalls;

        realtimePort.emitChange(tagChange(8));
        async.elapse(const Duration(seconds: 5));

        expect(repository.membershipsCalls, membershipsAfterFresh);

        realtimePort.emitChange(tagChange(10));
        async.elapse(const Duration(seconds: 5));
        expect(repository.membershipsCalls, membershipsAfterFresh + 1);

        unawaited(case_.dispose());
        unawaited(realtimePort.dispose());
        async.flushMicrotasks();
      });
    });
  });
}
