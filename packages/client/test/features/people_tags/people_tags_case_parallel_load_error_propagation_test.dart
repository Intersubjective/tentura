// Pins error propagation and the stale-account guard of the parallel load in
// PeopleTagsCase.load: when one of the two parallel reads fails, the caller
// sees that read's original exception (not a wrapper such as
// ParallelWaitError), when both fail the first error to arrive wins, and a
// result that lands after an account switch is ignored.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/env.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';
import 'package:tentura/features/people_tags/domain/port/people_tags_repository_port.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';

import '../../support/test_realtime_sync.dart';

class _TagsBoom implements Exception {}

class _MembershipsBoom implements Exception {}

Future<T> _failAfter<T>(Exception error, Duration delay) =>
    Future<T>.delayed(delay, () => throw error);

const _tag = PersonTag(
  id: 'Ta',
  name: 'Neighbours',
  glyph: 'N',
  color: 0,
  ord: 0,
);

final class _FakeRepository implements PeopleTagsRepositoryPort {
  _FakeRepository({required this.tags, required this.memberships});

  final Future<List<PersonTag>> Function() tags;
  final Future<List<PersonTagMembers>> Function() memberships;

  @override
  Future<List<PersonTag>> personTags() => tags();

  @override
  Future<List<PersonTagMembers>> personTagMemberships() => memberships();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  final cleanups = <Future<void> Function()>[];

  tearDown(() async {
    for (final cleanup in cleanups.reversed) {
      await cleanup();
    }
    cleanups.clear();
  });

  PeopleTagsCase buildCase({
    required Future<List<PersonTag>> Function() tags,
    required Future<List<PersonTagMembers>> Function() memberships,
  }) {
    final realtime = buildTestRealtimeSync();
    final case_ = PeopleTagsCase(
      _FakeRepository(tags: tags, memberships: memberships),
      realtime.case_,
      env: const Env(),
      logger: Logger('test'),
    );
    cleanups
      ..add(realtime.port.dispose)
      ..add(case_.dispose);
    return case_;
  }

  group('PeopleTagsCase.load parallel error propagation', () {
    test('tags failure reaches the caller as the original error', () {
      final case_ = buildCase(
        tags: () => _failAfter(_TagsBoom(), Duration.zero),
        memberships: () async => const [],
      );

      expect(case_.load(), throwsA(isA<_TagsBoom>()));
    });

    test('memberships failure reaches the caller as the original error', () {
      final case_ = buildCase(
        tags: () async => const [_tag],
        memberships: () => _failAfter(_MembershipsBoom(), Duration.zero),
      );

      expect(case_.load(), throwsA(isA<_MembershipsBoom>()));
    });

    test('both fail: the first error to arrive wins', () async {
      final membershipsFirst = buildCase(
        tags: () => _failAfter(_TagsBoom(), const Duration(milliseconds: 20)),
        memberships: () => _failAfter(_MembershipsBoom(), Duration.zero),
      );
      await expectLater(
        membershipsFirst.load(),
        throwsA(isA<_MembershipsBoom>()),
      );

      final tagsFirst = buildCase(
        tags: () => _failAfter(_TagsBoom(), Duration.zero),
        memberships: () => _failAfter(
          _MembershipsBoom(),
          const Duration(milliseconds: 20),
        ),
      );
      await expectLater(tagsFirst.load(), throwsA(isA<_TagsBoom>()));
    });

    test(
      'ensureLoaded surfaces the original error and stays retryable',
      () async {
        var fail = true;
        final case_ = buildCase(
          tags: () async => const [_tag],
          memberships: () => fail
              ? _failAfter(_MembershipsBoom(), Duration.zero)
              : Future.value(const [
                  PersonTagMembers(tagId: 'Ta', personIds: ['Uann']),
                ]),
        );

        await expectLater(
          case_.ensureLoaded(),
          throwsA(isA<_MembershipsBoom>()),
        );
        expect(case_.hasLoaded, isFalse);

        fail = false;
        await case_.ensureLoaded();
        expect(case_.hasLoaded, isTrue);
        expect(case_.peopleInTag('Ta'), {'Uann'});
      },
    );
  });

  group('PeopleTagsCase.load stale account', () {
    test('a result that lands after an account switch is ignored', () async {
      final tags = Completer<List<PersonTag>>();
      final memberships = Completer<List<PersonTagMembers>>();
      final case_ = buildCase(
        tags: () => tags.future,
        memberships: () => memberships.future,
      );
      final accounts = StreamController<String>();
      cleanups.add(accounts.close);
      case_.bindAccountChanges(accounts.stream);
      accounts.add('Ufirst');
      await Future<void>.delayed(Duration.zero);

      final pending = case_.load();
      accounts.add('Usecond');
      await Future<void>.delayed(Duration.zero);
      tags.complete(const [_tag]);
      memberships.complete(const [
        PersonTagMembers(tagId: 'Ta', personIds: ['Uann']),
      ]);
      await pending;

      expect(case_.hasLoaded, isFalse);
      expect(case_.tags, isEmpty);
      expect(case_.peopleInTag('Ta'), isEmpty);
    });
  });
}
