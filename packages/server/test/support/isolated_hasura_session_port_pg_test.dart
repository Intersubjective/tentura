// tentura-acz: `beacon_admitted_helpers_hasura_test` intermittently got
// `beacon_by_pk == null` in the full pg suite. Three test files start an
// [IsolatedHasuraSession] concurrently; each one probes for a free port by
// bind-and-release, and only later does its container claim it. Two starts
// therefore pick the same port, the losing container dies (`--rm`), and the
// health probe answers from the *winner* — which serves a different database —
// so the loser's queries silently hit the wrong Hasura and return no rows.
//
// This test reproduces that exact query (a discover observer reading
// `beacon_by_pk`) against several concurrently started sessions, each backed by
// its own database that carries a database-specific title marker, so a session
// talking to another session's Hasura is detectable, and it then checks the
// whole admitted-helpers contract of that test (access flags, helper list,
// block filtering, aggregate, offer-message denial) — not only "row present".
//
// Two shapes: sessions started concurrently in one process, and sessions
// started from separate OS processes released at the same instant (the real
// failure mode: separate `dart test` files under full-suite parallelism).
@Tags(['pg'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart' show TenturaDb;
import 'package:tentura_server/domain/port/invitation_repository_port.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/use_case/auth_case.dart';
import 'package:tentura_server/env.dart';

import '../data/repository/beacon_hierarchy_pg_helpers.dart';
import '../support/beacon_hierarchy_fixture.dart';
import '../support/hasura_pg_jwt_keys.dart';
import '../support/isolated_hasura_session.dart';

const _kSessions = 3;

/// One disposable database + Hasura + JWT issuer, torn down piecewise.
final class _Slot {
  _Slot(this.index, this.target);

  final int index;
  final BeaconHierarchyDisposablePgTarget target;
  Connection? writer;
  TenturaDb? db;
  IsolatedHasuraSession? hasura;
  late AuthCase authCase;

  String get marker => 'hasura-port-marker-$index';

  Future<void> dispose() async {
    // Every step runs even if an earlier one (or setup) failed partway.
    Future<void> attempt(Future<void>? Function() step) async {
      try {
        await step();
      } on Object catch (_) {}
    }

    await attempt(() => hasura?.stop());
    await attempt(() => db?.close());
    await attempt(() => writer?.close());
    await attempt(target.drop);
  }
}

Future<bool> _containerRunning(String containerName) async {
  final result = await Process.run('docker', [
    'inspect',
    '-f',
    '{{.State.Running}}',
    containerName,
  ]);
  return result.exitCode == 0 && (result.stdout as String).trim() == 'true';
}

Future<void> main() async {
  final postgresReachable = await canConnectBeaconHierarchyPostgres();
  final dockerReachable =
      postgresReachable && await IsolatedHasuraSession.isDockerAvailable();
  final skipReason = !postgresReachable
      ? 'Postgres admin database not reachable'
      : !dockerReachable
      ? 'Docker not available for isolated Hasura'
      : false;

  group('IsolatedHasuraSession concurrent starts', () {
    test(
      'in one process: each session serves its own database',
      () async {
        final slots = _newSlots();
        try {
          await _prepareSlots(slots);
          await Future.wait(
            slots.map((slot) async {
              slot.hasura = await IsolatedHasuraSession.start(
                databaseEnv: slot.target.databaseEnv,
                jwtPublicPem: _jwtKeys.publicKey,
              );
              await slot.hasura!.applyRepoMetadata();
            }),
          );
          await _expectAllSessionsHealthy(slots, {
            for (final slot in slots)
              slot.index: (
                baseUrl: slot.hasura!.baseUrl,
                port: slot.hasura!.port,
                containerName: slot.hasura!.containerName,
              ),
          });
        } finally {
          for (final slot in slots) {
            await slot.dispose();
          }
        }
      },
      skip: skipReason,
      timeout: const Timeout(Duration(minutes: 5)),
    );

    test(
      'across processes (separate test files): each session serves its own '
      'database',
      () async {
        final slots = _newSlots();
        final children = <Process>[];
        final infos = <int, _SessionInfo>{};
        try {
          await _prepareSlots(slots);

          // One OS process per "test file", all parked at a barrier.
          final outputs = <Process, Stream<String>>{};
          for (final slot in slots) {
            final child = await Process.start(Platform.resolvedExecutable, [
              'run',
              'test/support/isolated_hasura_session_probe.dart',
              slot.target.databaseName,
            ], workingDirectory: Directory.current.path);
            children.add(child);
            unawaited(child.stderr.drain<void>());
            outputs[child] = child.stdout
                .transform(utf8.decoder)
                .transform(const LineSplitter())
                .asBroadcastStream();
          }
          for (final child in children) {
            await outputs[child]!
                .firstWhere((line) => line == 'READY')
                .timeout(const Duration(minutes: 2));
          }

          // Release them together, as the parallel test runner effectively
          // does, and collect what each one got.
          final replies = <Process, Future<String>>{
            for (final child in children)
              child: outputs[child]!
                  .firstWhere(
                    (line) =>
                        line.startsWith('SESSION ') ||
                        line.startsWith('ERROR '),
                  )
                  .timeout(const Duration(minutes: 3)),
          };
          for (final child in children) {
            child.stdin.writeln('go');
            await child.stdin.flush();
          }
          for (var i = 0; i < slots.length; i++) {
            final reply = await replies[children[i]]!;
            expect(reply, startsWith('SESSION '), reason: reply);
            final json =
                jsonDecode(reply.substring('SESSION '.length))
                    as Map<String, dynamic>;
            infos[i] = (
              baseUrl: json['baseUrl']! as String,
              port: json['port']! as int,
              containerName: json['containerName']! as String,
            );
          }

          await _expectAllSessionsHealthy(slots, infos);
        } finally {
          for (final child in children) {
            try {
              child.stdin.writeln('stop');
              await child.stdin.close();
            } on Object catch (_) {}
          }
          for (final child in children) {
            await child.exitCode.timeout(
              const Duration(seconds: 30),
              onTimeout: () {
                child.kill(ProcessSignal.sigkill);
                return -1;
              },
            );
          }
          // The children own the containers; sweep any a dead child left.
          for (final info in infos.values) {
            await Process.run('docker', ['rm', '-f', info.containerName]);
          }
          for (final slot in slots) {
            await slot.dispose();
          }
        }
      },
      skip: skipReason,
      timeout: const Timeout(Duration(minutes: 8)),
    );
  });
}

typedef _SessionInfo = ({String baseUrl, int port, String containerName});

final _jwtKeys = loadJwtKeysForHasuraPgTests();

List<_Slot> _newSlots() => List.generate(
  _kSessions,
  (i) => _Slot(
    i,
    BeaconHierarchyDisposablePgTarget.fromEnvironment(
      databaseNameOverride:
          'tentura_test_hasura_ports_${pid}_'
          '${DateTime.timestamp().microsecondsSinceEpoch}_$i',
    ),
  ),
);

/// One database per session, migrated and seeded exactly like the real Hasura
/// pg tests (lifecycle lock, migrateDbSchema, fixture).
Future<void> _prepareSlots(List<_Slot> slots) async {
  // One process opens several TenturaDb instances on purpose.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  for (final slot in slots) {
    final session = await openBeaconHierarchyPgSession(slot.target);
    slot
      ..writer = session.writer
      ..db = session.db;
    slot.authCase = AuthCase(
      _NoopUserRepository(),
      _NoopInvitationRepository(),
      env: _authEnvForHasura(slot.target, _jwtKeys),
      logger: Logger('IsolatedHasuraPortTest${slot.index}'),
    );
    await _seedDiscoverScenario(
      BeaconHierarchyFixture(writer: session.writer, db: session.db),
      session.writer,
      marker: slot.marker,
    );
  }
}

/// Every session must be a distinct live container serving *its own* database
/// with the full `beacon_admitted_helpers_hasura_test` behaviour.
Future<void> _expectAllSessionsHealthy(
  List<_Slot> slots,
  Map<int, _SessionInfo> infos,
) async {
  const beaconId = BeaconHierarchyTopology.beaconB;
  const helper = BeaconHierarchyTopology.carolId;
  const blockedHelper = BeaconHierarchyTopology.daveId;
  final problems = <String>[];

  for (final slot in slots) {
    final info = infos[slot.index]!;
    final who = 'session ${slot.index} (:${info.port})';
    final jwt = slot.authCase
        .issueAccessToken(BeaconHierarchyTopology.frankId)
        .rawToken;

    final main = await _gql(
      hasuraUrl: info.baseUrl,
      jwt: jwt,
      query:
          '''
query {
  beacon_by_pk(id: "$beaconId") {
    title
    can_read_content
    can_read_admitted_helpers
    can_read_involvement
    admitted_helpers(order_by: {user_id: asc}) { user_id }
    admitted_helpers_aggregate { aggregate { count } }
  }
}
''',
    );
    if (main.errors != null) {
      problems.add('$who: GraphQL errors ${main.errors}');
      continue;
    }
    final beacon = main.data['beacon_by_pk'] as Map<String, dynamic>?;
    if (beacon == null) {
      problems.add(
        '$who: beacon_by_pk returned null for the discover observer',
      );
      continue;
    }
    if (beacon['title'] != slot.marker) {
      problems.add(
        '$who: served "${beacon['title']}" instead of "${slot.marker}" — '
        "it is talking to another session's Hasura",
      );
    }
    if (beacon['can_read_content'] != true) {
      problems.add('$who: can_read_content=${beacon['can_read_content']}');
    }
    if (beacon['can_read_admitted_helpers'] != true) {
      problems.add(
        '$who: can_read_admitted_helpers='
        '${beacon['can_read_admitted_helpers']}',
      );
    }
    if (beacon['can_read_involvement'] != false) {
      problems.add(
        '$who: can_read_involvement=${beacon['can_read_involvement']}',
      );
    }
    final helpers = (beacon['admitted_helpers'] as List? ?? const [])
        .map((e) => (e as Map)['user_id'] as String)
        .toList();
    if (!helpers.contains(helper)) {
      problems.add('$who: admitted_helpers $helpers lacks $helper');
    }
    if (helpers.contains(blockedHelper)) {
      problems.add('$who: admitted_helpers $helpers includes blocked helper');
    }
    final count =
        ((beacon['admitted_helpers_aggregate'] as Map?)?['aggregate']
            as Map?)?['count'];
    if (count != helpers.length) {
      problems.add('$who: aggregate count $count != ${helpers.length}');
    }

    // Involvement-gated offer messages stay closed to a discover observer.
    final offers = await _gql(
      hasuraUrl: info.baseUrl,
      jwt: jwt,
      query:
          '''
query {
  beacon_help_offer(where: {beacon_id: {_eq: "$beaconId"}}) {
    user_id
    message
  }
}
''',
    );
    final offerRows = offers.data['beacon_help_offer'];
    if (offerRows is List && offerRows.isNotEmpty) {
      problems.add('$who: offer messages leaked to discover observer');
    }
  }
  expect(problems, isEmpty, reason: problems.join('\n'));

  final ports = infos.values.map((i) => i.port).toList();
  expect(
    ports.toSet(),
    hasLength(slots.length),
    reason: 'two sessions share a Hasura port: $ports',
  );
  for (final info in infos.values) {
    expect(
      await _containerRunning(info.containerName),
      isTrue,
      reason:
          'session on :${info.port} has no live container '
          '(${info.containerName})',
    );
  }
}

/// Mirrors `beacon_admitted_helpers_hasura_test`: frank discovers bob's
/// beacon B through mutual votes + `is_discoverable`; carol and dave are
/// admitted helpers and frank blocks dave. B's title is replaced with a
/// per-database [marker].
Future<void> _seedDiscoverScenario(
  BeaconHierarchyFixture fixture,
  Connection writer, {
  required String marker,
}) async {
  await fixture.seedFullTopology();
  await seedPublishedHierarchyTree(writer);
  const beaconId = BeaconHierarchyTopology.beaconB;
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon_participant (
  id, beacon_id, user_id, role, status, room_access, created_at, updated_at
) VALUES
  ('Pahlhasura01', @beaconId, @helper, 2, 5, @access, now(), now()),
  ('Pahlhasura02', @beaconId, @blocked, 2, 5, @access, now(), now())
ON CONFLICT (beacon_id, user_id) DO UPDATE SET
  room_access = EXCLUDED.room_access,
  role = EXCLUDED.role
'''),
    parameters: {
      'beaconId': beaconId,
      'helper': BeaconHierarchyTopology.carolId,
      'blocked': BeaconHierarchyTopology.daveId,
      'access': RoomAccessBits.admitted,
    },
  );
  await writer.execute(
    Sql.named('''
INSERT INTO public.vote_user (subject, object, amount, created_at, updated_at)
VALUES
  (@a, @b, 1, now(), now()),
  (@b, @a, 1, now(), now())
ON CONFLICT (subject, object) DO UPDATE SET amount = EXCLUDED.amount
'''),
    parameters: {
      'a': BeaconHierarchyTopology.bobId,
      'b': BeaconHierarchyTopology.frankId,
    },
  );
  await writer.execute(
    Sql.named(
      'UPDATE public.beacon SET is_discoverable = true, title = @title '
      'WHERE id = @id',
    ),
    parameters: {'id': beaconId, 'title': marker},
  );
  await writer.execute(
    Sql.named('''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id, created_at)
VALUES (@blocker, @blocked, @blocked, now())
ON CONFLICT DO NOTHING
'''),
    parameters: {
      'blocker': BeaconHierarchyTopology.frankId,
      'blocked': BeaconHierarchyTopology.daveId,
    },
  );
}

Future<({Map<String, dynamic> data, Object? errors})> _gql({
  required String hasuraUrl,
  required String jwt,
  required String query,
}) async {
  final response = await http.post(
    Uri.parse('$hasuraUrl/v1/graphql'),
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $jwt',
    },
    body: jsonEncode({'query': query}),
  );
  final body = jsonDecode(response.body) as Map<String, dynamic>;
  return (
    data: (body['data'] as Map<String, dynamic>?) ?? const {},
    errors: body['errors'],
  );
}

final class _NoopUserRepository implements UserRepositoryPort {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _NoopInvitationRepository implements InvitationRepositoryPort {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Env _authEnvForHasura(
  BeaconHierarchyDisposablePgTarget target,
  ({String publicKey, String privateKey}) jwtKeys,
) {
  final base = target.databaseEnv;
  return Env(
    environment: base.environment,
    pgHost: base.pgHost,
    pgPort: base.pgPort,
    pgDatabase: base.pgDatabase,
    pgUsername: base.pgUsername,
    pgPassword: base.pgPassword,
    printEnv: false,
    isDebugModeOn: false,
    publicKey: jwtKeys.publicKey,
    privateKey: jwtKeys.privateKey,
  );
}
