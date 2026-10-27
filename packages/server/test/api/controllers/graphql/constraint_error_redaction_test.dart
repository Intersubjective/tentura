@Tags(['pg'])
library;

import 'dart:convert';

import 'package:shelf_plus/shelf_plus.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/schema.dart';
import 'package:tentura_server/api/controllers/graphql/unmapped_graphql_error.dart';
import 'package:tentura_server/api/controllers/graphql_controller.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNull, isNotNull;
import 'package:tentura_server/data/repository/witness_window_repository.dart';
import 'package:tentura_server/domain/capability/capability_evidence_models.dart';

import '../../../support/disposable_pg_target.dart';

const _ego = 'Uprivateego';
const _witness = 'Uprivatewitness';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_WRAPPED_CONSTRAINT_TEST_DB',
    defaultNamePrefix: 'tentura_test_wrapped_constraint',
  );
  final skip = await pgSkipReason(target);
  if (skip != null) {
    test('Postgres unavailable', () {}, skip: skip);
    return;
  }

  test(
    'GraphQL hides a constraint failure when witness-window rollback also fails',
    () async {
      final session = await setUpDisposablePgWriter(target: target);
      addTearDown(() => tearDownDisposablePgWriter(session: session));
      final writer = session.writer;
      for (final id in [_ego, _witness]) {
        await writer.execute(
          'INSERT INTO public."user" (id, display_name, public_key) '
          "VALUES ('$id', '$id', '$id-key')",
        );
      }
      // Inject an independent storage failure. It must keep failing even when
      // storeWindow gains an upsert for its own primary key. PostgreSQL, rather
      // than a stub resolver, creates the original 23505 and aborts the real tx.
      await writer.execute('''
CREATE TABLE public.private_constraint_probe (
  id text CONSTRAINT private_constraint_probe_pkey PRIMARY KEY
)
''');
      await writer.execute(
        "INSERT INTO public.private_constraint_probe VALUES ('$_ego:$_witness')",
      );
      await writer.execute('''
CREATE FUNCTION public.fail_witness_storage() RETURNS trigger
LANGUAGE plpgsql AS \$\$
BEGIN
  INSERT INTO public.private_constraint_probe VALUES ('$_ego:$_witness');
  RETURN NEW;
END;
\$\$
''');
      await writer.execute('''
CREATE TRIGGER fail_witness_storage BEFORE INSERT ON public.ego_witness_window
FOR EACH ROW EXECUTE FUNCTION public.fail_witness_storage()
''');
      final database = TenturaDb(
        target.databaseEnv,
        scopeInterceptor: _ProbeAbortedRollback.new,
      );
      addTearDown(database.close);
      final repository = WitnessWindowRepository(database);
      Object? observed;
      final controller = GraphqlController(
        target.databaseEnv,
        schema: TenturaGraphQL(
          GraphQLSchema(
            queryType: GraphQLObjectType('Query', 'Query root')
              ..fields.add(
                GraphQLObjectField<String, Object?>(
                  'refreshWindow',
                  graphQLString,
                  resolve: (_, _) async {
                    try {
                      await repository.storeWindow(
                        egoId: _ego,
                        normalizedContext: '',
                        weights: const [
                          WitnessWeight(
                            witnessUserId: _witness,
                            m: 1,
                            admitted: true,
                          ),
                        ],
                      );
                      return 'stored';
                    } on Object catch (error) {
                      observed = error;
                      rethrow;
                    }
                  },
                ),
              ),
          ),
        ),
      );
      final response = await controller.handler(
        Request(
          'POST',
          Uri.parse('http://localhost/api/v2/graphql'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'query': 'query { refreshWindow }'}),
        ),
      );
      // Prove this exercised Drift's abort wrapper, not merely a bare PgException.
      expect(observed, isA<CouldNotRollBackException>());
      final wrapped = observed! as CouldNotRollBackException;
      expect(
        wrapped.cause,
        isA<ServerException>().having(
          (error) => error.code,
          'root SQLSTATE',
          '23505',
        ),
      );
      expect(
        wrapped.exception,
        isA<ServerException>().having(
          (error) => error.code,
          'rollback SQLSTATE',
          '25P02',
        ),
      );
      expect(response.statusCode, 200);
      final wire = await response.readAsString();
      final body = jsonDecode(wire) as Map<String, dynamic>;
      final entry = (body['errors'] as List).single as Map<String, dynamic>;
      expect(entry['message'], kUnmappedDatabaseErrorMessage);
      expect(entry['extensions'], containsPair('code', '1000'));
      expect(body.containsKey('data'), isFalse);
      for (final detail in [
        '23505',
        '25P02',
        'CouldNotRollBackException',
        'private_constraint_probe',
        'ego_witness_window',
        _ego,
        _witness,
        'duplicate key',
      ]) {
        expect(wire, isNot(contains(detail)));
      }
      expect(
        await writer.execute('SELECT 1 FROM public.ego_witness_window'),
        isEmpty,
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

/// Fault-inject the rollback failure reported by Sentry: querying the aborted
/// backend really yields 25P02. Clean up with ROLLBACK before propagating it so
/// this test leaves no poisoned pooled session. Drift creates its own wrapper.
final class _ProbeAbortedRollback extends QueryInterceptor {
  @override
  Future<void> rollbackTransaction(TransactionExecutor inner) async {
    try {
      await inner.runSelect('SELECT 1', const []);
    } on ServerException catch (error, stack) {
      await super.rollbackTransaction(inner);
      Error.throwWithStackTrace(error, stack);
    }
    await super.rollbackTransaction(inner);
    fail('Expected a PostgreSQL transaction aborted by the storage constraint');
  }
}
