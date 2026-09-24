@Tags(['pg'])
library;


import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/domain/capability/context_normalization.dart';

import '../../support/disposable_pg_target.dart';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_M0142_CONTEXT_TEST_DB',
    defaultNamePrefix: 'tentura_test_m0142_ctx',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('cap_normalize_context SQL parity', () {
    late Connection writer;

    setUpAll(() async {
      await target.recreate();
      writer = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await writer.execute('SET check_function_bodies = false');
      await migrateDbSchema(writer);
    });

    tearDownAll(() async {
      await writer.close();
      await target.drop();
    });

    Future<String> sqlNormalize(String? input) async {
      final Result result;
      if (input == null) {
        result = await writer.execute(
          'SELECT public.cap_normalize_context(NULL)',
        );
      } else {
        result = await writer.execute(
          Sql.named('SELECT public.cap_normalize_context(@input)'),
          parameters: {'input': input},
        );
      }
      return result.single.single! as String;
    }

    for (final case_ in _parityCases) {
      test('parity for ${case_.label}', () async {
        final dart = capNormalizeContext(case_.input);
        final sql = await sqlNormalize(case_.input);
        expect(dart, case_.expected);
        expect(sql, case_.expected);
      }, skip: skipReason);
    }
  });
}

class _ParityCase {
  const _ParityCase(this.label, this.input, this.expected);

  final String label;
  final String? input;
  final String expected;
}

const _parityCases = [
  _ParityCase('null', null, ''),
  _ParityCase('empty', '', ''),
  _ParityCase('whitespace', '  ', ''),
  _ParityCase('two chars', 'ab', ''),
  _ParityCase('trimmed case', ' AbC ', 'AbC'),
  _ParityCase('tab delimiters', '\tAbC\t', '\tAbC\t'),
  _ParityCase('32 chars', 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'),
  _ParityCase('33 chars', 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', ''),
];

