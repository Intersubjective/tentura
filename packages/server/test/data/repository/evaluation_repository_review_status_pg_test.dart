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
/// stub is the contract: every review-package entry point must fail loudly
/// instead of touching the dropped schema. No database is needed — the stub
/// throws before any query.
void main() {
  group(
    'EvaluationRepository review package sent_at (post-m0203 contract)',
    () {
      final repo = EvaluationRepository(
        TenturaDb(Env(environment: Environment.test)),
      );

      test('getReviewWindow fails loudly on the dropped review schema', () {
        expect(
          () => repo.getReviewWindow('Bcrvst1abcn01'),
          throwsA(isA<UnimplementedError>()),
        );
      });

      test('getReviewUserStatus fails loudly on the dropped review schema', () {
        expect(
          () => repo.getReviewUserStatus('Bcrvst1abcn01', 'Ucrvst1arevw01'),
          throwsA(isA<UnimplementedError>()),
        );
      });

      test('setReviewUserStatus fails loudly on the dropped review schema', () {
        expect(
          () => repo.setReviewUserStatus(
            beaconId: 'Bcrvst1abcn01',
            userId: 'Ucrvst1arevw01',
            status: 2,
            markSent: true,
          ),
          throwsA(isA<UnimplementedError>()),
        );
      });

      test(
        'submitEvaluationAtomic fails loudly on the dropped review schema',
        () {
          expect(
            () => repo.submitEvaluationAtomic(
              beaconId: 'Bcrvst1abcn01',
              evaluatorId: 'Ucrvst1aauth01',
              evaluatedUserId: 'Ucrvst1arevw01',
              value: 4,
              reasonTags: const [],
              note: 'edited',
              ackTags: const [],
            ),
            throwsA(isA<UnimplementedError>()),
          );
        },
      );

      test(
        'deleteReviewScaffoldingForBeacon fails loudly on the dropped review '
        'schema',
        () {
          expect(
            () => repo.deleteReviewScaffoldingForBeacon('Bcrvst1abcn01'),
            throwsA(isA<UnimplementedError>()),
          );
        },
      );

      test('closeReviewWindow fails loudly on the dropped review schema', () {
        expect(
          () => repo.closeReviewWindow(
            'Bcrvst1abcn01',
            reason: 'test',
            actorUserId: 'Ucrvst1aauth01',
            requireAllRequiredPackagesSent: true,
          ),
          throwsA(isA<UnimplementedError>()),
        );
      });
    },
  );
}
