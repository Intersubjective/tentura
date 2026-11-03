@Tags(['pg', 'mr'])
library;

import 'package:graphql_schema2/graphql_schema2.dart';
import 'package:graphql_server2/graphql_server2.dart';
import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/query/query_forward_candidates.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/forward_candidates_repository.dart';
import 'package:tentura_server/data/repository/meritrank_repository.dart';
import 'package:tentura_server/data/repository/person_visibility_repository.dart';
import 'package:tentura_server/data/repository/user_availability_repository.dart';
import 'package:tentura_server/data/repository/user_profile_batch_lookup.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/use_case/forward_candidates_case.dart';
import 'package:tentura_server/env.dart';

import '../../../support/disposable_pg_target.dart';
import '../../../support/pg_test_public_keys.dart';

const _viewer = 'Ufcsviewer';
const _peer = 'Ufcspeer';
final _early = DateTime.utc(2026, 1, 2, 3, 4, 5);
final _late = DateTime.utc(2026, 2, 3, 4, 5, 6);
final _renewed = DateTime.utc(2026, 3, 4, 5, 6, 7);

// Coverage: either one-way direction, either ordering of mutual edge times,
// withdrawal and re-creation of either edge, and shared-context projection.
// Candidate visibility comes from real MR scores independently of trust, so
// one-way and withdrawn peers remain in the picker. No vote_user seeds.
// Input, locale, viewport and UI lifecycle are n/a for this server response.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_FORWARD_CANDIDATES_MUTUAL_SINCE_TEST_DB',
    defaultNamePrefix: 'tentura_test_forward_mutual_since',
  );
  final skip = await pgSkipReason(target);
  if (skip != null) {
    test('Postgres unavailable', () {}, skip: skip);
    return;
  }

  late DisposablePgWriterSession session;
  late TenturaDb db;
  late MeritrankRepository meritRank;
  late GraphQL graphQL;
  late ForwardCandidatesCase candidatesCase;

  setUpAll(() async {
    GetIt.I.registerSingleton<Env>(Env(environment: Environment.test));
    session = await setUpDisposablePgWriter(
      target: target,
      createPgmer2Extension: true,
    );
    db = openDisposablePgDatabase(target);
    meritRank = MeritrankRepository(db);
    candidatesCase = ForwardCandidatesCase(
      ForwardCandidatesRepository(db),
      DriftUserProfileBatchLookup(db, UserAvailabilityRepository(db)),
      PersonVisibilityRepository(db),
      env: Env(environment: Environment.test),
      logger: Logger('ForwardCandidatesMutualSince'),
    );
    final query = QueryForwardCandidates(forwardCandidatesCase: candidatesCase);
    graphQL = GraphQL(
      GraphQLSchema(
        queryType: GraphQLObjectType('Query', 'Query root')
          ..fields.addAll(query.all),
      ),
    );
  });

  tearDownAll(() async {
    await meritRank.reset();
    await tearDownDisposablePgWriter(session: session, drift: db);
    await GetIt.I.reset();
  });

  setUp(() async {
    await meritRank.reset();
    await session.writer.execute('TRUNCATE public."user" CASCADE');
    for (final (i, id) in [_viewer, _peer].indexed) {
      await session.writer.execute(
        Sql.named(
          'INSERT INTO public."user" (id, display_name, public_key) '
          'VALUES (@id, @id, @key)',
        ),
        parameters: {'id': id, 'key': pgTestPublicKey('forward-since', i + 1)},
      );
    }
    await meritRank.putEdge(nodeA: _viewer, nodeB: _peer);
    await meritRank.putEdge(nodeA: _peer, nodeB: _viewer);
    await meritRank.calculate();
  });

  Future<void> edge(String subject, String object, DateTime at) async {
    await session.writer.execute(
      Sql.named('''
INSERT INTO public.user_trust_edge
  (subject, object, trust_w, target_w, created_at, updated_at)
VALUES (@subject, @object, 1, 1, @at, @updated)
'''),
      parameters: {
        'subject': subject,
        'object': object,
        'at': at,
        // Distinguish creation time from last update time.
        'updated': DateTime.utc(2026, 4, 5),
      },
    );
  }

  Future<Map<String, dynamic>> candidate({bool withSince = true}) async {
    final result =
        await graphQL.parseAndExecute(
              'query { forwardCandidates(context: "") '
              '{ id shares_active_context ${withSince ? 'mutual_since' : ''} } }',
              globalVariables: {
                kGlobalInputQueryJwt: const JwtEntity(sub: _viewer),
              },
            )
            as Map<String, dynamic>;
    final rows = (result['forwardCandidates'] as List)
        .cast<Map<String, dynamic>>();
    expect(rows.map((row) => row['id']), contains(_peer));
    final row = rows.singleWhere((row) => row['id'] == _peer);
    if (withSince) expect(row, contains('mutual_since'));
    return row;
  }

  Future<DateTime?> mutualSince() async {
    // Prove the existing picker works with the fixture before requesting the
    // new field: a red test must not hide broken visibility or missing users.
    await candidate(withSince: false);
    final value = (await candidate())['mutual_since'];
    if (value == null) return null;
    return (value is DateTime ? value : DateTime.parse(value as String))
        .toUtc();
  }

  Future<DateTime?> caseMutualSince() async {
    final rows = await candidatesCase.fetch(viewerId: _viewer, context: '');
    expect(rows.map((row) => row.id), contains(_peer));
    final record = rows.singleWhere((row) => row.id == _peer);
    return record.mutualSince;
  }

  test('user schema advertises a nullable mutual_since scalar', () async {
    final result =
        await graphQL.parseAndExecute(
              'query { __type(name: "user") { fields { name type { kind name } } } }',
            )
            as Map<String, dynamic>;
    final type = result['__type'] as Map<String, dynamic>;
    final fields = (type['fields'] as List).cast<Map<String, dynamic>>();
    // Confirm introspection itself works before checking the missing field.
    expect(
      fields.map((field) => field['name']),
      contains('shares_active_context'),
    );
    expect(fields.map((field) => field['name']), contains('mutual_since'));
    final field = fields.singleWhere(
      (field) => field['name'] == 'mutual_since',
    );
    expect(
      (field['type'] as Map<String, dynamic>)['kind'],
      'SCALAR',
      reason: 'The timestamp must be a nullable scalar, not NON_NULL',
    );
  });

  group('Candidate use case current trust edge timestamps', () {
    for (final outgoing in [true, false]) {
      test(
        outgoing
            ? 'uses viewer edge creation independently of update time and votes'
            : 'uses peer edge creation independently of update time and votes',
        () async {
          final newer = outgoing
              ? DateTime.utc(2025, 7, 8, 9, 10, 11)
              : DateTime.utc(2025, 9, 10, 11, 12, 13);
          final older = newer.subtract(const Duration(days: 17));
          await edge(_viewer, _peer, outgoing ? newer : older);
          await edge(_peer, _viewer, outgoing ? older : newer);
          expect(await caseMutualSince(), newer);
          // A mere update must not restart the mutual relationship.
          await session.writer.execute(
            'UPDATE public.user_trust_edge '
            "SET updated_at = '2026-10-01T00:00:00Z'",
          );
          expect(await caseMutualSince(), newer);
          final subject = outgoing ? _viewer : _peer;
          final object = outgoing ? _peer : _viewer;
          await session.writer.execute(
            Sql.named(
              'DELETE FROM public.user_trust_edge '
              'WHERE subject = @subject AND object = @object',
            ),
            parameters: {'subject': subject, 'object': object},
          );
          expect(await caseMutualSince(), isNull);
          final replacement = newer.add(const Duration(days: 37));
          await edge(subject, object, replacement);
          expect(await caseMutualSince(), replacement);
        },
      );
    }
  });

  group('Forward candidate mutual trust start time', () {
    for (final outgoing in [true, false]) {
      test(
        outgoing
            ? 'viewer-only trust returns a nullable mutual_since'
            : 'peer-only trust returns a nullable mutual_since',
        () async {
          await edge(
            outgoing ? _viewer : _peer,
            outgoing ? _peer : _viewer,
            _early,
          );
          expect(await mutualSince(), isNull);
        },
      );

      test(
        outgoing
            ? 'mutual_since uses the newer viewer-to-peer edge creation time'
            : 'mutual_since uses the newer peer-to-viewer edge creation time',
        () async {
          await edge(_viewer, _peer, outgoing ? _late : _early);
          await edge(_peer, _viewer, outgoing ? _early : _late);
          expect(await mutualSince(), _late);
        },
      );

      test(
        outgoing
            ? 're-creating viewer trust restarts mutual_since after withdrawal'
            : 're-creating peer trust restarts mutual_since after withdrawal',
        () async {
          await edge(_viewer, _peer, _early);
          await edge(_peer, _viewer, _late);
          expect(await mutualSince(), _late);
          final subject = outgoing ? _viewer : _peer;
          final object = outgoing ? _peer : _viewer;
          await session.writer.execute(
            Sql.named(
              'DELETE FROM public.user_trust_edge '
              'WHERE subject = @subject AND object = @object',
            ),
            parameters: {'subject': subject, 'object': object},
          );
          expect(await mutualSince(), isNull);
          await edge(subject, object, _renewed);
          expect(await mutualSince(), _renewed);
        },
      );
    }

    test(
      'shared active context preserves the mutual trust start time',
      () async {
        await edge(_viewer, _peer, _early);
        await edge(_peer, _viewer, _late);
        await session.writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, kind, status, published_at)
VALUES ('Bfcsshared', '$_viewer', 'Shared request', '', 0, 0, now())
''');
        await session.writer.execute('''
INSERT INTO public.beacon_participant (beacon_id, user_id, role, room_access)
VALUES ('Bfcsshared', '$_peer', 1, 3)
''');
        expect(
          (await candidate(withSince: false))['shares_active_context'],
          isTrue,
        );
        expect(await mutualSince(), _late);
      },
    );
  });
}
