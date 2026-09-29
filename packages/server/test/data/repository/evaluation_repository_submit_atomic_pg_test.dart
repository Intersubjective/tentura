@Tags(['pg'])
library;

import 'package:injectable/injectable.dart' show Environment;
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/evaluation_repository.dart';
import 'package:tentura_server/env.dart';

/// m0203 (A6) dropped the six review-era tables and stubbed every
/// EvaluationRepository method; A18 deletes these call paths. Until then the
/// stub is the contract: the atomic submit path must fail loudly instead of
/// touching the dropped schema. No database is needed — the stub throws
/// before any query.
void main() {
  group('EvaluationRepository.submitEvaluationAtomic (A18 stub)', () {
    final repo = EvaluationRepository(
      TenturaDb(Env(environment: Environment.test)),
    );

    test('submitEvaluationAtomic is stubbed', () {
      expect(
        () => repo.submitEvaluationAtomic(
          beaconId: 'Bcapc1abcn01',
          evaluatorId: 'Ucapc1aeval01',
          evaluatedUserId: 'Ucapc1asubj01',
          value: 4,
          reasonTags: const ['quality', 'speed'],
          note: 'solid help',
          ackTags: const ['transport', 'pets'],
        ),
        throwsA(isA<UnimplementedError>()),
      );
    });

    test('getEvaluation is stubbed', () {
      expect(
        () => repo.getEvaluation(
          beaconId: 'Bcapc1abcn01',
          evaluatorId: 'Ucapc1aeval01',
          evaluatedUserId: 'Ucapc1asubj01',
        ),
        throwsA(isA<UnimplementedError>()),
      );
    });

    test('upsertEvaluation is stubbed', () {
      expect(
        () => repo.upsertEvaluation(
          beaconId: 'Bcapc1abcn01',
          evaluatorId: 'Ucapc1aeval01',
          evaluatedUserId: 'Ucapc1asubj01',
          value: 4,
          reasonTagsCsv: 'quality',
          note: 'draft',
        ),
        throwsA(isA<UnimplementedError>()),
      );
    });
  });
}
