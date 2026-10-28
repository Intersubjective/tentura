@Tags(['pg', 'mr', 'repo-files'])
library;

import 'dart:convert';

import 'package:test/test.dart';

import 'package:tentura_server/data/repository/trust_publish_repository.dart';

import '../../client/test/support/person_untrust_mutation_contract.dart';
import 'support/disposable_pg_target.dart';
import 'support/profile_trust_graph_pg_fixture.dart';

const _alice = ProfileTrustGraphPgFixture.alice;
const _bob = ProfileTrustGraphPgFixture.bob;

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_PUBLISHED_UNTRUST_TEST_DB',
    defaultNamePrefix: 'tentura_test_published_untrust',
  );
  var opened = false;
  late ProfileTrustGraphPgFixture fixture;
  late TrustPublishRepository publisher;

  Future<void> publishPending() async {
    final token = await publisher.acquireLease('published-untrust-test');
    expect(token, isNotNull);
    final rows = await publisher.readBatch(100);
    expect(rows, isNotEmpty);
    for (final row in rows) {
      await publisher.publish(row);
    }
    await publisher.sync();
    await publisher.ack(token!, rows);
    expect(await publisher.readBatch(100), isEmpty);
  }

  Future<Set<(String, String)>> focusedEdges({
    required String viewer,
    required String focus,
  }) async => {
    for (final row in await fixture.db.customSelect('''
SELECT src, dst FROM public.graph(
  '$focus', '', true, '{"x-hasura-user-id":"$viewer"}'::json)
WHERE src IN ('$_alice', '$_bob') AND dst IN ('$_alice', '$_bob')
''').get())
      (row.read<String>('src'), row.read<String>('dst')),
  };

  Future<Map<String, Object?>> diagnostics() async => {
    for (final (name, query) in <(String, String)>[
      ('votes', 'SELECT subject, object, amount FROM public.vote_user'),
      (
        'projection',
        'SELECT subject, object, target_w, prev_sent_weight '
            'FROM public.user_trust_edge',
      ),
      (
        'queue',
        'SELECT subject_user_id, object_user_id '
            'FROM public.trust_publish_queue',
      ),
      (
        'meritrank',
        'SELECT src, dst, weight FROM public.mr_edgelist() '
            "WHERE src IN ('$_alice', '$_bob') "
            "AND dst IN ('$_alice', '$_bob')",
      ),
    ])
      name: [
        for (final row in await fixture.db.customSelect(query).get()) row.data,
      ],
  };

  Future<Set<(String, String)>> publishedEdges() async => {
    for (final row in await fixture.db.customSelect('''
SELECT src, dst FROM public.mr_edgelist()
WHERE src IN ('$_alice', '$_bob') AND dst IN ('$_alice', '$_bob')
  AND weight > 0
''').get())
      (row.read<String>('src'), row.read<String>('dst')),
  };

  setUpAll(() async {
    if (!await canReachPostgresAdmin(target)) {
      fail(
        'This acceptance test requires PostgreSQL and real MeritRank; '
        'unavailable infrastructure must fail rather than skip.',
      );
    }
    fixture = ProfileTrustGraphPgFixture(target);
    await fixture.open();
    publisher = TrustPublishRepository(fixture.db);
    opened = true;
    await fixture.session.writer.execute(
      'CREATE EXTENSION IF NOT EXISTS pgmer2',
    );
  });

  setUp(() async {
    // Seed through the real vote repository and publish its queue to the
    // actual MeritRank service. Do not mark edges as sent by hand.
    for (final (subject, object) in [(_alice, _bob), (_bob, _alice)]) {
      await fixture.votes.setVoteAmountAndApplyEvidence(
        subjectUserId: subject,
        objectUserId: object,
        newAmount: 1,
      );
    }
    await publishPending();
    expect(
      await focusedEdges(viewer: _alice, focus: _alice),
      contains((_alice, _bob)),
    );
    expect(
      await focusedEdges(viewer: _bob, focus: _bob),
      contains((_bob, _alice)),
    );
    expect(await fixture.edges(), {(_alice, _bob), (_bob, _alice)});
  });

  tearDown(() async {
    for (final (subject, object) in [(_alice, _bob), (_bob, _alice)]) {
      await fixture.votes.setVoteAmountAndApplyEvidence(
        subjectUserId: subject,
        objectUserId: object,
        newAmount: 0,
      );
    }
    if ((await publisher.readBatch(100)).isNotEmpty) {
      await publishPending();
    }
  });

  tearDownAll(() async {
    if (!opened) return;
    try {
      for (final (src, dst) in [(_alice, _bob), (_bob, _alice)]) {
        await fixture.db.customStatement(
          "SELECT public.mr_delete_edge('$src', '$dst')",
        );
      }
      await publisher.sync();
    } finally {
      await fixture.close();
    }
  });

  group('Published trust withdrawal preserves the remaining direction', () {
    test('viewer and remote untrust leave only the opposite direction in '
        'both graph readers after publication', () async {
      final actual = <String, Object?>{};
      final expected = <String, Object?>{};
      final snapshots = <String, Object?>{};
      for (final (actor, person, description) in [
        (_alice, _bob, 'viewer untrust'),
        (_bob, _alice, 'remote untrust'),
      ]) {
        if (actor == _bob) {
          // Restore mutual trust through the production write and publisher
          // before testing Bob's independent withdrawal as seen by Alice.
          await fixture.votes.setVoteAmountAndApplyEvidence(
            subjectUserId: _alice,
            objectUserId: _bob,
            newAmount: 1,
          );
          await publishPending();
          expect(await fixture.edges(), {(_alice, _bob), (_bob, _alice)});
        }
        expect(
          await fixture.executeMutation(
            personUntrustMutationRequest(person),
            actorId: actor,
          ),
          {'__typename': 'Mutation', 'userVote': 0},
        );
        expect(await fixture.voteAmount(actor, person), 0);
        expect(await fixture.voteAmount(person, actor), 1);

        final beforePublication = {
          'Alice graph': await focusedEdges(viewer: _alice, focus: _alice),
          'Bob graph': await focusedEdges(viewer: _bob, focus: _bob),
          'graph_edges_between': await fixture.edges(),
        };
        final beforeDiagnostics = await diagnostics();
        await publishPending();
        final afterPublication = {
          'Alice graph': await focusedEdges(viewer: _alice, focus: _alice),
          'Bob graph': await focusedEdges(viewer: _bob, focus: _bob),
          'graph_edges_between': await fixture.edges(),
          'MeritRank edges': await publishedEdges(),
        };
        for (final reader in afterPublication.entries) {
          expect(
            reader.value,
            isNot(contains((actor, person))),
            reason:
                '${reader.key} must not return the direction withdrawn by $actor',
          );
        }
        final remaining = {
          'Alice graph': {(person, actor)},
          'Bob graph': {(person, actor)},
          'graph_edges_between': {(person, actor)},
          'MeritRank edges': {(person, actor)},
        };
        // Before publication the readers may already honor the committed
        // projection, or still reflect MeritRank's previous edge. Only the
        // post-publication read is the convergence contract asserted here.
        actual[description] = afterPublication;
        expected[description] = remaining;
        snapshots[description] = {
          'observed before publication': {
            'readers': beforePublication.toString(),
            'source': beforeDiagnostics,
          },
          'after publication': await diagnostics(),
        };
      }
      expect(actual, expected, reason: jsonEncode(snapshots));
    });
  });
}
