@Tags(['pg', 'mr'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/forward_candidates_repository.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

const _viewer = 'Ufcowviewer1';
const _other = 'Ufcowother01';
const _peerA = 'Ufcowpeera01';
const _peerB = 'Ufcowpeerb01';
const _author = 'Ufcowauthor1';
const _users = [_viewer, _other, _peerA, _peerB, _author];

/// B3: the repository returns the viewer's own forward timestamps per
/// recipient for the requested window, and reading them writes nothing to the
/// trust tables.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_FORWARD_CANDIDATES_OWN_FORWARDS_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_fc_own_forwards',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  late Connection writer;
  late TenturaDb database;
  late ForwardCandidatesRepository repo;

  // Whole-second UTC so values round-trip exactly through timestamptz.
  final now = DateTime.fromMillisecondsSinceEpoch(
    (DateTime.timestamp().millisecondsSinceEpoch ~/ 1000) * 1000,
    isUtc: true,
  );
  final since = now.subtract(const Duration(days: 7));

  var edgeSeq = 0;
  Future<void> forward({
    required String sender,
    required String recipient,
    required DateTime at,
  }) async {
    edgeSeq++;
    // One active edge per (beacon, sender, recipient): each forward gets its
    // own request.
    final beacon = 'Bfcow${edgeSeq.toString().padLeft(7, '0')}';
    await writer.execute('''
INSERT INTO public.beacon (id, user_id, title, description, status)
VALUES ('$beacon', '$_author', 'own forwards', '', 0)
''');
    await writer.execute(
      Sql.named(r'''
INSERT INTO public.beacon_forward_edge (
  id, beacon_id, sender_id, recipient_id, created_at
) VALUES (@id, @beacon, @sender, @recipient, @at)
'''),
      parameters: {
        'id': 'Ffcow${edgeSeq.toString().padLeft(7, '0')}',
        'beacon': beacon,
        'sender': sender,
        'recipient': recipient,
        'at': at,
      },
    );
  }

  Future<Map<String, int>> trustCounts() async {
    final out = <String, int>{};
    for (final t in const [
      'user_trust_edge',
      'trust_evidence',
      'trust_publish_queue',
    ]) {
      final r = await writer.execute('SELECT count(*) FROM public.$t');
      out[t] = r.first.first! as int;
    }
    return out;
  }

  List<int> secs(List<DateTime>? times) =>
      [for (final t in times ?? const <DateTime>[]) t.millisecondsSinceEpoch ~/ 1000]
        ..sort();

  int s(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

  if (skipReason == false) {
    setUpAll(() async {
      await target.recreate();
      writer = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await writer.execute('CREATE EXTENSION IF NOT EXISTS pgmer2');
      await migrateDbSchema(writer);
      database = TenturaDb(target.databaseEnv);
      repo = ForwardCandidatesRepository(database);
    });

    tearDownAll(() async {
      await database.close();
      await writer.close();
      await target.drop();
    });

    setUp(() async {
      await writer.execute('DELETE FROM public.beacon_forward_edge');
      await writer.execute("DELETE FROM public.beacon WHERE id LIKE 'Bfcow%'");
      for (var i = 0; i < _users.length; i++) {
        await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('${_users[i]}', '${_users[i]}', '${pgTestPublicKey('fcow', i + 1)}')
ON CONFLICT (id) DO NOTHING
''');
      }
    });
  }

  group(
    'ForwardCandidatesRepository.fetchRecentOwnForwardTimes',
    skip: skipReason,
    () {
      test('groups the viewer\'s forward timestamps by recipient', () async {
        final a1 = now.subtract(const Duration(days: 1));
        final a2 = now.subtract(const Duration(days: 3));
        final b1 = now.subtract(const Duration(hours: 2));
        await forward(sender: _viewer, recipient: _peerA, at: a1);
        await forward(sender: _viewer, recipient: _peerA, at: a2);
        await forward(sender: _viewer, recipient: _peerB, at: b1);

        final result = await repo.fetchRecentOwnForwardTimes(
          viewerId: _viewer,
          since: since,
        );

        expect(result.keys.toSet(), {_peerA, _peerB});
        expect(secs(result[_peerA]), [s(a2), s(a1)]);
        expect(secs(result[_peerB]), [s(b1)]);
      });

      test('ignores forwards sent by other users', () async {
        await forward(
          sender: _other,
          recipient: _peerA,
          at: now.subtract(const Duration(hours: 1)),
        );
        final mine = now.subtract(const Duration(days: 2));
        await forward(sender: _viewer, recipient: _peerA, at: mine);

        final result = await repo.fetchRecentOwnForwardTimes(
          viewerId: _viewer,
          since: since,
        );

        expect(secs(result[_peerA]), [s(mine)]);
        expect(
          await repo.fetchRecentOwnForwardTimes(
            viewerId: _peerB,
            since: since,
          ),
          isEmpty,
        );
      });

      test('honours the since cutoff', () async {
        final inside = since.add(const Duration(minutes: 1));
        await forward(sender: _viewer, recipient: _peerA, at: inside);
        await forward(
          sender: _viewer,
          recipient: _peerA,
          at: since.subtract(const Duration(minutes: 1)),
        );
        await forward(
          sender: _viewer,
          recipient: _peerB,
          at: now.subtract(const Duration(days: 30)),
        );

        final result = await repo.fetchRecentOwnForwardTimes(
          viewerId: _viewer,
          since: since,
        );

        expect(secs(result[_peerA]), [s(inside)]);
        expect(result.containsKey(_peerB), isFalse);
      });

      test('blank viewer yields an empty map', () async {
        await forward(sender: _viewer, recipient: _peerA, at: now);

        expect(
          await repo.fetchRecentOwnForwardTimes(viewerId: '  ', since: since),
          isEmpty,
        );
      });

      test('reading forward times writes nothing to the trust tables', () async {
        await forward(sender: _viewer, recipient: _peerA, at: now);
        final before = await trustCounts();

        await repo.fetchRecentOwnForwardTimes(viewerId: _viewer, since: since);

        expect(await trustCounts(), before);
      });
    },
  );
}
