import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/domain/entity/beacon_room_record.dart';
import 'package:tentura_server/domain/use_case/polling_case.dart';
import 'package:tentura_server/env.dart';

import 'polling_case_mocks.mocks.dart';

void main() {
  late MockPollingActRepositoryPort actRepo;
  late MockPollingRepositoryPort pollingRepo;
  late PollingCase case_;

  const authorId = 'Uauthor000001';
  const pollingId = 'Poll000000001';
  const variantId = 'Var0000000001';

  PollingVotePolicy poll({
    String pollType = 'single',
    bool allowRevote = true,
  }) =>
      PollingVotePolicy(
        pollType: pollType,
        allowRevote: allowRevote,
      );

  setUp(() {
    actRepo = MockPollingActRepositoryPort();
    pollingRepo = MockPollingRepositoryPort();
    case_ = PollingCase(
      actRepo,
      pollingRepo,
      env: Env(environment: Environment.test),
      logger: Logger('PollingCaseTest'),
    );

    when(pollingRepo.findById(any)).thenAnswer((_) async => poll());
    when(
      actRepo.upsert(
        authorId: anyNamed('authorId'),
        pollingId: anyNamed('pollingId'),
        variantIds: anyNamed('variantIds'),
        pollType: anyNamed('pollType'),
        allowRevote: anyNamed('allowRevote'),
        score: anyNamed('score'),
      ),
    ).thenAnswer((_) async {});
  });

  group('create', () {
    test('throws when poll not found', () async {
      when(pollingRepo.findById(pollingId)).thenAnswer((_) async => null);

      await expectLater(
        case_.create(
          authorId: authorId,
          pollingId: pollingId,
          variantIds: [variantId],
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            'Poll not found: $pollingId',
          ),
        ),
      );
      verifyNever(
        actRepo.upsert(
          authorId: anyNamed('authorId'),
          pollingId: anyNamed('pollingId'),
          variantIds: anyNamed('variantIds'),
          pollType: anyNamed('pollType'),
          allowRevote: anyNamed('allowRevote'),
          score: anyNamed('score'),
        ),
      );
    });

    test('rejects score on non-range poll', () async {
      when(pollingRepo.findById(pollingId))
          .thenAnswer((_) async => poll(pollType: 'single'));

      await expectLater(
        case_.create(
          authorId: authorId,
          pollingId: pollingId,
          variantIds: [variantId],
          score: 3,
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            'score only valid for range polls',
          ),
        ),
      );
      verifyNever(
        actRepo.upsert(
          authorId: anyNamed('authorId'),
          pollingId: anyNamed('pollingId'),
          variantIds: anyNamed('variantIds'),
          pollType: anyNamed('pollType'),
          allowRevote: anyNamed('allowRevote'),
          score: anyNamed('score'),
        ),
      );
    });

    test('rejects score below 0', () async {
      when(pollingRepo.findById(pollingId))
          .thenAnswer((_) async => poll(pollType: 'range'));

      await expectLater(
        case_.create(
          authorId: authorId,
          pollingId: pollingId,
          variantIds: [variantId],
          score: -1,
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            'score must be 0–5',
          ),
        ),
      );
    });

    test('rejects score above 5', () async {
      when(pollingRepo.findById(pollingId))
          .thenAnswer((_) async => poll(pollType: 'range'));

      await expectLater(
        case_.create(
          authorId: authorId,
          pollingId: pollingId,
          variantIds: [variantId],
          score: 6,
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            'score must be 0–5',
          ),
        ),
      );
    });

    test('rejects multiple variantIds on single poll', () async {
      when(pollingRepo.findById(pollingId))
          .thenAnswer((_) async => poll(pollType: 'single'));

      await expectLater(
        case_.create(
          authorId: authorId,
          pollingId: pollingId,
          variantIds: [variantId, 'Var0000000002'],
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            'single polls accept exactly one variantId',
          ),
        ),
      );
      verifyNever(
        actRepo.upsert(
          authorId: anyNamed('authorId'),
          pollingId: anyNamed('pollingId'),
          variantIds: anyNamed('variantIds'),
          pollType: anyNamed('pollType'),
          allowRevote: anyNamed('allowRevote'),
          score: anyNamed('score'),
        ),
      );
    });

    test('delegates single poll vote to act repository', () async {
      when(pollingRepo.findById(pollingId)).thenAnswer(
        (_) async => poll(pollType: 'single', allowRevote: false),
      );

      final result = await case_.create(
        authorId: authorId,
        pollingId: pollingId,
        variantIds: [variantId],
      );

      expect(result, isTrue);
      verify(
        actRepo.upsert(
          authorId: authorId,
          pollingId: pollingId,
          variantIds: [variantId],
          pollType: 'single',
          allowRevote: false,
          score: null,
        ),
      ).called(1);
    });

    test('delegates multiple poll vote to act repository', () async {
      const variantIds = [variantId, 'Var0000000002'];
      when(pollingRepo.findById(pollingId))
          .thenAnswer((_) async => poll(pollType: 'multiple'));

      final result = await case_.create(
        authorId: authorId,
        pollingId: pollingId,
        variantIds: variantIds,
      );

      expect(result, isTrue);
      verify(
        actRepo.upsert(
          authorId: authorId,
          pollingId: pollingId,
          variantIds: variantIds,
          pollType: 'multiple',
          allowRevote: true,
          score: null,
        ),
      ).called(1);
    });

    test('delegates range poll vote with score to act repository', () async {
      when(pollingRepo.findById(pollingId))
          .thenAnswer((_) async => poll(pollType: 'range'));

      final result = await case_.create(
        authorId: authorId,
        pollingId: pollingId,
        variantIds: [variantId],
        score: 5,
      );

      expect(result, isTrue);
      verify(
        actRepo.upsert(
          authorId: authorId,
          pollingId: pollingId,
          variantIds: [variantId],
          pollType: 'range',
          allowRevote: true,
          score: 5,
        ),
      ).called(1);
    });

    test('accepts boundary scores 0 and 5 on range poll', () async {
      when(pollingRepo.findById(pollingId))
          .thenAnswer((_) async => poll(pollType: 'range'));

      for (final score in [0, 5]) {
        await case_.create(
          authorId: authorId,
          pollingId: pollingId,
          variantIds: [variantId],
          score: score,
        );
      }

      verify(
        actRepo.upsert(
          authorId: authorId,
          pollingId: pollingId,
          variantIds: [variantId],
          pollType: 'range',
          allowRevote: true,
          score: 0,
        ),
      ).called(1);
      verify(
        actRepo.upsert(
          authorId: authorId,
          pollingId: pollingId,
          variantIds: [variantId],
          pollType: 'range',
          allowRevote: true,
          score: 5,
        ),
      ).called(1);
    });
  });
}
