import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/env.dart';
import 'package:tentura/features/polling/data/repository/polling_repository.dart';
import 'package:tentura/features/polling/domain/use_case/polling_case.dart';

void main() {
  late FakePollingRepository repository;
  late PollingCase case_;

  const pollingId = 'poll-1';

  setUp(() {
    repository = FakePollingRepository();
    case_ = PollingCase(
      repository,
      env: const Env(),
      logger: Logger('test'),
    );
  });

  group('vote', () {
    test('forwards pollingId, variantIds, and score to repository', () async {
      const variantIds = ['variant-a', 'variant-b'];

      await case_.vote(
        pollingId: pollingId,
        variantIds: variantIds,
        score: 4,
      );

      expect(repository.voteCalls, 1);
      expect(repository.lastVote?.pollingId, pollingId);
      expect(repository.lastVote?.variantIds, variantIds);
      expect(repository.lastVote?.score, 4);
    });

    test('forwards null score when omitted', () async {
      await case_.vote(
        pollingId: pollingId,
        variantIds: const ['variant-a'],
      );

      expect(repository.voteCalls, 1);
      expect(repository.lastVote?.pollingId, pollingId);
      expect(repository.lastVote?.variantIds, ['variant-a']);
      expect(repository.lastVote?.score, isNull);
    });

    test('propagates repository errors', () async {
      repository.voteError = StateError('vote failed');

      expect(
        () => case_.vote(
          pollingId: pollingId,
          variantIds: const ['variant-a'],
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}

class FakePollingRepository implements PollingRepository {
  int voteCalls = 0;
  ({String pollingId, List<String> variantIds, int? score})? lastVote;
  Object? voteError;

  @override
  Future<void> vote({
    required String pollingId,
    required List<String> variantIds,
    int? score,
  }) async {
    voteCalls++;
    lastVote = (
      pollingId: pollingId,
      variantIds: List<String>.from(variantIds),
      score: score,
    );
    if (voteError != null) {
      throw voteError!;
    }
  }
}
