@Tags(['pg', 'mr', 'repo-files'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/repository/trust_ledger_repository.dart';
import 'package:tentura_server/data/repository/trust_publish_repository.dart';
import 'package:tentura_server/domain/trust/ledger_evidence.dart';
import 'package:tentura_server/domain/trust/trust_evidence_kind.dart';

import '../../client/test/support/person_untrust_mutation_contract.dart';
import 'support/disposable_pg_target.dart';
import 'support/profile_trust_graph_pg_fixture.dart';

const _alice = ProfileTrustGraphPgFixture.alice;
const _bob = ProfileTrustGraphPgFixture.bob;

void main() {
  late ProfileTrustGraphPgFixture fixture;
  late TrustPublishRepository publisher;

  Future<void> publishPending() async {
    final token = await publisher.acquireLease('profile-trust-direction');
    expect(token, isNotNull);
    final batch = await publisher.readBatch(100);
    expect(batch, isNotEmpty);
    for (final row in batch) {
      await publisher.publish(row);
    }
    await publisher.sync();
    await publisher.ack(token!, batch);
    expect(await publisher.readBatch(100), isEmpty);
  }

  Future<Map<String, Set<(String, String)>>> readGraph(
    DisposablePgTarget target,
  ) async {
    // Independent connections also exercise the fresh-read behavior of reload.
    final connection = await Connection.open(
      target.databaseEnv.pgEndpoint,
      settings: target.databaseEnv.pgEndpointSettings,
    );
    try {
      // Selecting Bob requests his neighbourhood while Alice stays the viewer.
      final selectedPerson = await connection.execute('''
SELECT src, dst FROM public.graph(
  '$_bob', '', true, '{"x-hasura-user-id":"$_alice"}'::json)
WHERE src IN ('$_alice', '$_bob') AND dst IN ('$_alice', '$_bob')
''');
      final neighbourhood = await connection.execute('''
SELECT src, dst FROM public.graph(
  '$_alice', '', true, '{"x-hasura-user-id":"$_alice"}'::json)
WHERE src IN ('$_alice', '$_bob') AND dst IN ('$_alice', '$_bob')
''');
      final closure = await connection.execute(
        ProfileTrustGraphPgFixture.edgeQuery,
      );
      return {
        'selected person': {
          for (final row in selectedPerson)
            (row[0]! as String, row[1]! as String),
        },
        'graph': {
          for (final row in neighbourhood)
            (row[0]! as String, row[1]! as String),
        },
        'graph_edges_between': {
          for (final row in closure) (row[0]! as String, row[1]! as String),
        },
      };
    } finally {
      await connection.close();
    }
  }

  group('Profile trust withdrawal preserves the opposite graph direction', () {
    for (final priorHelp in [false, true]) {
      for (final (actor, person, description) in [
        (_alice, _bob, 'viewer withdrawal leaves only incoming trust'),
        (_bob, _alice, 'remote withdrawal leaves only outgoing trust'),
      ]) {
        test('$description${priorHelp ? ' after previous help' : ''}', () async {
          final target = DisposablePgTarget.fromNamedEnvironment(
            envVarName: 'TENTURA_PROFILE_TRUST_DIRECTION_TEST_DB',
            defaultNamePrefix: 'tentura_test_profile_trust_direction',
          );
          expect(
            await canReachPostgresAdmin(target),
            isTrue,
            reason: 'This acceptance test requires PostgreSQL with pgmer2.',
          );
          fixture = ProfileTrustGraphPgFixture(target);
          await fixture.open();
          publisher = TrustPublishRepository(fixture.db);
          addTearDown(fixture.close);
          await fixture.session.writer.execute(
            'CREATE EXTENSION IF NOT EXISTS pgmer2',
          );
          addTearDown(() async {
            for (final (src, dst) in [(_alice, _bob), (_bob, _alice)]) {
              await fixture.db.customStatement(
                "SELECT public.mr_delete_edge('$src', '$dst')",
              );
            }
            await publisher.sync();
          });
          if (priorHelp) {
            // Existing positive interaction history is normal for a trusted
            // pair. Record it through the production ledger, rather than
            // manufacturing a stale projection or changing a graph function.
            await TrustLedgerRepository(fixture.db).record([
              for (final (subject, object) in [(_alice, _bob), (_bob, _alice)])
                LedgerEvidence(
                  subjectId: subject,
                  objectId: object,
                  kind: TrustEvidenceKind.helped,
                  count: 1,
                  sourceKey: 'previous-help:$subject:$object',
                ),
            ]);
          }
          // Seed through production writes and publication, with no fabricated
          // projection rows or replacements for either graph reader.
          for (final (subject, object) in [(_alice, _bob), (_bob, _alice)]) {
            await fixture.votes.setVoteAmountAndApplyEvidence(
              subjectUserId: subject,
              objectUserId: object,
              newAmount: 1,
            );
          }
          await publishPending();
          expect(await readGraph(target), {
            'selected person': {(_alice, _bob), (_bob, _alice)},
            'graph': {(_alice, _bob), (_bob, _alice)},
            'graph_edges_between': {(_alice, _bob), (_bob, _alice)},
          });

          // The frozen production contract is shared with the client test that
          // checks the actual profile/People request serialization.
          expect(
            await fixture.executeMutation(
              personUntrustMutationRequest(person),
              actorId: actor,
            ),
            {'__typename': 'Mutation', 'userVote': 0},
          );
          expect(await fixture.voteAmount(actor, person), 0);
          expect(await fixture.voteAmount(person, actor), 1);

          final beforePublication = await readGraph(target);
          await publishPending();
          final afterPublication = await readGraph(target);
          final oneWay = {
            'selected person': {(person, actor)},
            'graph': {(person, actor)},
            'graph_edges_between': {(person, actor)},
          };
          expect(
            {'committed': beforePublication, 'published': afterPublication},
            {'committed': oneWay, 'published': oneWay},
            reason:
                'Alice must see exactly the remaining direction on fresh '
                'reads both immediately and after publication.',
          );
        });
      }
    }
  });
}
