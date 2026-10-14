import 'package:tentura_server/data/database/tentura_db.dart';
import 'package:test/test.dart';

void main() {
  test(
    'batch fails before invoking the callback or touching the executor',
    () async {
      final executor = _UnusedExecutor();
      final db = TenturaDb.forTest(database: executor);
      addTearDown(db.close);
      var callbackInvoked = false;

      // Exercise dynamic dispatch through Drift's public database API as well.
      final DatabaseConnectionUser database = db;
      await expectLater(
        database.batch((batch) {
          callbackInvoked = true;
          batch.customStatement('SELECT 1');
        }),
        throwsA(
          isA<UnsupportedError>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('TenturaDb.batch() is forbidden'),
              contains('scoped connection'),
              contains('withTransaction()'),
            ),
          ),
        ),
      );

      expect(callbackInvoked, isFalse);
      expect(executor.calls, isEmpty);
    },
  );
}

/// Any attempt to open, transact, prepare or execute SQL fails this test.
class _UnusedExecutor implements QueryExecutor {
  final List<Symbol> calls = [];

  @override
  SqlDialect get dialect => SqlDialect.postgres;

  @override
  Future<void> close() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation.memberName);
    throw StateError('Unexpected executor call: ${invocation.memberName}');
  }
}
