import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

Future<void> requireSchemaVersionAtOrPastM0202(Connection writer) async {
  final version = await writer.execute(
    'SELECT max(version) FROM public.schema_version',
  );
  expect(
    (version.single.single! as String).compareTo('0202'),
    greaterThanOrEqualTo(0),
    reason: 'fixture requires disposable DB migrated through m0202',
  );
}

Future<void> requireM0202DroppedTrustLedgerObjectsAbsent(
  Connection writer,
) async {
  final ledger = await writer.execute(
    r"SELECT to_regclass('public.trust_evidence') IS NOT NULL AS ledger_ready",
  );
  expect(
    ledger.single.single,
    true,
    reason:
        'm0202+ disposable DB must expose trust_evidence (post-ledger-cutover)',
  );
}
