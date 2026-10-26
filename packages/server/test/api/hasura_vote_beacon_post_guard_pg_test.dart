@Tags(['pg', 'repo-files'])
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_server/domain/port/invitation_repository_port.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/use_case/auth_case.dart';
import 'package:tentura_server/env.dart';

import '../support/disposable_pg_target.dart';
import '../support/hasura_pg_jwt_keys.dart';
import '../support/isolated_hasura_session.dart';
import '../support/post_write_guard_fixture.dart';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_HASURA_VOTE_BEACON_POST_GUARD_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_hasura_post_vote',
  );
  final skip = await pgSkipReason(target);
  if (skip != null) {
    test('Postgres unavailable', () {}, skip: skip);
    return;
  }
  if (!await IsolatedHasuraSession.isDockerAvailable()) {
    test('Docker unavailable', () {}, skip: 'Docker not available');
    return;
  }

  group('Hasura user voting respects the Post archive', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late IsolatedHasuraSession hasura;
    late String jwt;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      addTearDown(() => tearDownDisposablePgWriter(session: session));
      writer = session.writer;
      final keys = loadJwtKeysForHasuraPgTests();
      final base = target.databaseEnv;
      final auth = AuthCase(
        _UnusedUserRepository(),
        _UnusedInvitationRepository(),
        env: Env(
          environment: base.environment,
          pgHost: base.pgHost,
          pgPort: base.pgPort,
          pgDatabase: base.pgDatabase,
          pgUsername: base.pgUsername,
          pgPassword: base.pgPassword,
          printEnv: false,
          isDebugModeOn: false,
          publicKey: keys.publicKey,
          privateKey: keys.privateKey,
        ),
        logger: Logger('HasuraVoteBeaconPostGuardPgTest'),
      );
      jwt = auth.issueAccessToken(guardMember).rawToken;
      hasura = await IsolatedHasuraSession.start(
        databaseEnv: target.databaseEnv,
        jwtPublicPem: keys.publicKey,
      );
      addTearDown(hasura.stop);
      await hasura.applyRepoMetadata();
      await hasura.assertMetadataConsistent();
    });
    setUp(() => seedPostWriteGuard(writer));

    Future<Map<String, dynamic>> vote({
      required int amount,
      required bool upsert,
    }) async {
      final conflict = upsert
          ? ', on_conflict: {constraint: vote_beacon_pkey, update_columns: [amount]}'
          : '';
      final response = await http.post(
        Uri.parse('${hasura.baseUrl}/v1/graphql'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $jwt',
          'X-Hasura-Role': 'user',
        },
        body: jsonEncode({
          'query':
              '''
mutation {
  insert_vote_beacon_one(object: {object: "$guardPost", amount: $amount}$conflict) {
    object subject amount
  }
}
''',
        }),
      );
      expect(response.statusCode, 200);
      return jsonDecode(response.body) as Map<String, dynamic>;
    }

    Future<int?> storedAmount() async {
      final rows = await writer.execute(
        'SELECT amount FROM public.vote_beacon '
        "WHERE subject = '$guardMember' AND object = '$guardPost'",
      );
      return rows.isEmpty ? null : rows.single.single! as int;
    }

    test('role user inserts and upserts its own vote on a live Post', () async {
      for (final (amount, upsert) in [(1, false), (2, true)]) {
        final result = await vote(amount: amount, upsert: upsert);
        expect(result['errors'], isNull, reason: result.toString());
        final data = result['data']! as Map<String, dynamic>;
        expect(data['insert_vote_beacon_one'], {
          'object': guardPost,
          'subject': guardMember,
          'amount': amount,
        });
        expect(await storedAmount(), amount);
      }
    });

    test('role user cannot insert a vote on an expired Post', () async {
      await archiveGuardPost(writer, 'expired');
      final result = await vote(amount: 1, upsert: false);
      expect(result['errors'], isNotEmpty, reason: result.toString());
      expect(jsonEncode(result['errors']), contains('post_archived'));
      expect(await storedAmount(), isNull);
    });

    test(
      'role user cannot upsert an existing vote on an expired Post',
      () async {
        final inserted = await vote(amount: 1, upsert: false);
        expect(inserted['errors'], isNull, reason: inserted.toString());
        expect(await storedAmount(), 1);
        await archiveGuardPost(writer, 'expired');
        final result = await vote(amount: 2, upsert: true);
        expect(result['errors'], isNotEmpty, reason: result.toString());
        expect(jsonEncode(result['errors']), contains('post_archived'));
        expect(await storedAmount(), 1);
      },
    );
  });
}

final class _UnusedUserRepository implements UserRepositoryPort {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _UnusedInvitationRepository implements InvitationRepositoryPort {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
