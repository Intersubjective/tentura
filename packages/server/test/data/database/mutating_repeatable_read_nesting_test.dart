import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;

import '../../support/transaction_statement_recorder.dart';

void main() {
  group('withMutatingRepeatableRead transaction nesting', () {
    late TransactionStatementRecorder recorder;
    late TenturaDb db;

    setUp(() {
      recorder = TransactionStatementRecorder(select: (_, _) => []);
      db = TenturaDb.forTest(database: recorder);
      addTearDown(db.close);
    });

    Future<void> expectNestingRejected() async {
      final statementsBefore = recorder.statements.length;
      var callbackInvoked = false;
      final sleeps = <Duration>[];
      Object? error;

      try {
        await db.withMutatingRepeatableRead<void>(
          'Umutrractor01',
          () async {
            callbackInvoked = true;
          },
          sleep: (duration) async => sleeps.add(duration),
        );
      } catch (caught) {
        error = caught;
      }

      expect(
        error,
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('transaction'),
        ),
        reason: 'An open transaction must be rejected explicitly.',
      );
      expect(
        recorder.statements.skip(statementsBefore),
        isEmpty,
        reason:
            'Reject nesting before issuing any SQL in the outer transaction.',
      );
      expect(callbackInvoked, isFalse);
      expect(sleeps, isEmpty);
    }

    test('rejects an open Drift transaction before issuing SQL', () async {
      await db.transaction(expectNestingRejected);
    });

    test('rejects a read snapshot before issuing SQL', () async {
      await db.withReadSnapshot(expectNestingRejected);
    });
  });
}
