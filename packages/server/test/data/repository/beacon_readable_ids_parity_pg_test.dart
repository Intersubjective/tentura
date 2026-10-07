@Tags(['pg', 'mr'])
library;

import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart' show Variable;
import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';

/// `beacon_readable_ids(viewer, ids)` is the set-based companion of
/// `beacon_can_read_content(beacon, viewer)`: it must return exactly the ids
/// the per-row function accepts, and be much cheaper over many beacons.
Future<void> main() async {
  final postgresReachable = await canReachPostgresAdmin(_target);
  DisposablePgWriterSession? pgSession;
  if (postgresReachable) {
    pgSession = await setUpDisposablePgWriter(
      target: _target,
      createPgmer2Extension: true,
    );
    tearDownAll(() => tearDownDisposablePgWriter(session: pgSession!));
  }
  final Object skipReason = postgresReachable
      ? false
      : 'local Postgres not reachable';

  late TenturaDb db;

  const userCount = 24;
  final userIds = [
    for (var i = 0; i < userCount; i++) 'Urdy${i.toString().padLeft(8, '0')}',
  ];
  String beaconId(int i) => 'Brdy${i.toString().padLeft(8, '0')}';

  Future<void> sql(String statement) => db.customStatement(statement);

  Future<void> cleanup() async {
    await sql(
      "DELETE FROM public.beacon_help_offer WHERE beacon_id LIKE 'Brdy%'",
    );
    await sql(
      "DELETE FROM public.beacon_forward_edge WHERE beacon_id LIKE 'Brdy%'",
    );
    await sql("DELETE FROM public.beacon_steward WHERE beacon_id LIKE 'Brdy%'");
    await sql(
      "DELETE FROM public.beacon_participant WHERE beacon_id LIKE 'Brdy%'",
    );
    await sql("DELETE FROM public.user_block WHERE blocker_id LIKE 'Urdy%'");
    await sql("DELETE FROM public.vote_user WHERE subject LIKE 'Urdy%'");
    await sql(
      "DELETE FROM public.beacon_ancestor WHERE beacon_id LIKE 'Brdy%'",
    );
    await sql("DELETE FROM public.beacon WHERE id LIKE 'Brdy%'");
    await sql("DELETE FROM public.\"user\" WHERE id LIKE 'Urdy%'");
  }

  /// Seeds [beaconCount] beacons with randomized author, status, discoverable
  /// flag, publication, parent, forwards, participants, stewards, offers,
  /// plus random mutual trust and blocks between users.
  Future<void> seed(Random rnd, int beaconCount) async {
    for (final id in userIds) {
      await sql('''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ('$id', '$id', 'pk-$id', now(), now())
''');
    }
    String pick() => userIds[rnd.nextInt(userCount)];
    for (var i = 0; i < userCount; i++) {
      for (var j = i + 1; j < userCount; j++) {
        if (rnd.nextInt(6) == 0) {
          await sql('''
INSERT INTO public.vote_user (subject, object, amount, created_at, updated_at)
VALUES ('${userIds[i]}', '${userIds[j]}', 1, now(), now()),
       ('${userIds[j]}', '${userIds[i]}', 1, now(), now())
''');
        }
      }
    }
    for (var n = 0; n < 12; n++) {
      final a = pick();
      final b = pick();
      if (a == b) continue;
      await sql('''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES ('$a', '$b', '$a') ON CONFLICT DO NOTHING
''');
    }
    const statuses = [0, 0, 0, 2, 3, 7, 8];
    final values = <String>[];
    final publishedIndexes = <int>[];
    for (var i = 0; i < beaconCount; i++) {
      // The schema only lets a published, non-draft beacon be a parent.
      final published = rnd.nextInt(10) == 0 ? 'NULL' : 'now()';
      final status = statuses[rnd.nextInt(statuses.length)];
      final parent = publishedIndexes.isNotEmpty && rnd.nextInt(4) == 0
          ? "'${beaconId(publishedIndexes[rnd.nextInt(publishedIndexes.length)])}'"
          : 'NULL';
      if (published != 'NULL' && status != 3) publishedIndexes.add(i);
      values.add(
        "('${beaconId(i)}', '${pick()}', '${beaconId(i)}', '', "
        '$status, $published, '
        '${rnd.nextBool()}, $parent, now(), now())',
      );
    }
    // Parents first so the ancestor trigger sees them: insert one by one.
    for (final v in values) {
      await sql('''
INSERT INTO public.beacon (id, user_id, title, description, status,
  published_at, is_discoverable, parent_beacon_id, created_at, updated_at)
VALUES $v
''');
    }
    for (var i = 0; i < beaconCount; i++) {
      final b = beaconId(i);
      if (rnd.nextInt(5) == 0) {
        await sql('''
INSERT INTO public.beacon_forward_edge (beacon_id, sender_id, recipient_id,
  cancelled_at)
VALUES ('$b', '${pick()}', '${pick()}',
  ${rnd.nextInt(3) == 0 ? 'now()' : 'NULL'})
''');
      }
      if (rnd.nextInt(5) == 0) {
        await sql('''
INSERT INTO public.beacon_participant (id, beacon_id, user_id, role,
  room_access, created_at, updated_at)
VALUES ('Prdy${i.toString().padLeft(8, '0')}', '$b', '${pick()}',
  ${rnd.nextInt(2)}, ${rnd.nextBool() ? 3 : 0}, now(), now())
''');
      }
      if (rnd.nextInt(8) == 0) {
        await sql('''
INSERT INTO public.beacon_steward (beacon_id, user_id)
VALUES ('$b', '${pick()}')
''');
      }
      if (rnd.nextInt(8) == 0) {
        await sql('''
INSERT INTO public.beacon_help_offer (beacon_id, user_id, message, status,
  created_at, updated_at)
VALUES ('$b', '${pick()}', 'offer', ${rnd.nextInt(2)}, now(), now())
ON CONFLICT DO NOTHING
''');
      }
    }
  }

  Future<Set<String>> perRowReadable(String viewer, List<String> ids) async {
    final rows = await db
        .customSelect(
          r'''
SELECT i AS id FROM unnest($2::text[]) AS i
WHERE public.beacon_can_read_content(i, $1)
''',
          variables: [
            Variable<String>(viewer),
            Variable<String>(_textArray(ids)),
          ],
        )
        .get();
    return {for (final r in rows) r.read<String>('id')};
  }

  Future<Set<String>> setReadable(String viewer, List<String> ids) async {
    final rows = await db
        .customSelect(
          r'SELECT public.beacon_readable_ids($1, $2::text[]) AS id',
          variables: [
            Variable<String>(viewer),
            Variable<String>(_textArray(ids)),
          ],
        )
        .get();
    return {for (final r in rows) r.read<String>('id')};
  }

  var schemaMigrated = false;

  if (skipReason == false) {
    setUp(() async {
      final testEnv = _testEnv();
      if (!schemaMigrated) {
        final writer = await Connection.open(
          testEnv.pgEndpoint,
          settings: testEnv.pgEndpointSettings,
        );
        await writer.execute('SET check_function_bodies = false');
        await writer.execute('CREATE EXTENSION IF NOT EXISTS pgmer2');
        await migrateDbSchema(writer);
        await writer.close();
        schemaMigrated = true;
      }
      db = TenturaDb(testEnv);
      await cleanup();
    });

    tearDown(() async {
      await cleanup();
      await db.close();
    });
  }

  test(
    'set-based readable ids equal the per-row verdict over randomized '
    'viewer/beacon pairs',
    () async {
      final rnd = Random(229);
      const beaconCount = 60;
      await seed(rnd, beaconCount);
      final ids = [for (var i = 0; i < beaconCount; i++) beaconId(i)];

      var pairs = 0;
      var readablePairs = 0;
      for (final viewer in userIds) {
        final expected = await perRowReadable(viewer, ids);
        final actual = await setReadable(viewer, ids);
        expect(actual, expected, reason: 'viewer $viewer');
        pairs += ids.length;
        readablePairs += expected.length;
      }
      expect(pairs, greaterThanOrEqualTo(500));
      // The fixture must exercise both outcomes, or parity proves nothing.
      expect(readablePairs, greaterThan(0));
      expect(readablePairs, lessThan(pairs));
    },
    skip: skipReason,
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'set-based readable ids match the expected verdict of every access branch',
    () async {
      const viewer = 'Urdy00000000';
      const other = 'Urdy00000001';
      const friend = 'Urdy00000002';
      const foe = 'Urdy00000003';
      const foe2 = 'Urdy00000004';
      for (final id in [viewer, other, friend]) {
        await sql('''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ('$id', '$id', 'pk-$id', now(), now())
''');
      }
      var next = 0;
      Future<String> beacon(
        String author, {
        int status = 0,
        bool published = true,
        bool discoverable = false,
        String? parent,
      }) async {
        final id = beaconId(next++);
        await sql('''
INSERT INTO public.beacon (id, user_id, title, description, status,
  published_at, is_discoverable, parent_beacon_id, created_at, updated_at)
VALUES ('$id', '$author', '$id', '', $status,
  ${published ? 'now()' : 'NULL'}, $discoverable,
  ${parent == null ? 'NULL' : "'$parent'"}, now(), now())
''');
        return id;
      }

      Future<void> forward(String b, {bool cancelled = false}) => sql('''
INSERT INTO public.beacon_forward_edge (beacon_id, sender_id, recipient_id,
  cancelled_at)
VALUES ('$b', '$other', '$viewer', ${cancelled ? 'now()' : 'NULL'})
''');
      Future<void> participant(String b, String user, int role, int access) =>
          sql('''
INSERT INTO public.beacon_participant (id, beacon_id, user_id, role,
  room_access, created_at, updated_at)
VALUES ('Prdy${b.substring(4)}${user.substring(10)}', '$b', '$user', $role,
  $access, now(), now())
''');
      Future<void> block(String blocker, String blocked) => sql('''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES ('$blocker', '$blocked', '$blocker')
''');

      // Mutual explicit trust between the viewer and `friend` only.
      await sql('''
INSERT INTO public.vote_user (subject, object, amount, created_at, updated_at)
VALUES ('$viewer', '$friend', 1, now(), now()),
       ('$friend', '$viewer', 1, now(), now())
''');

      final expected = <String, bool>{};
      void want(String name, String id, bool readable) =>
          expected['$name|$id'] = readable;

      // Author branch, status gates first.
      want('author open', await beacon(viewer), true);
      want(
        'author draft',
        await beacon(viewer, status: 3, published: false),
        true,
      );
      want('author deleted', await beacon(viewer, status: 2), false);
      want(
        'foreign draft forwarded to viewer',
        await (() async {
          final b = await beacon(other, status: 3, published: false);
          await forward(b);
          return b;
        })(),
        false,
      );
      want(
        'foreign deleted forwarded to viewer',
        await (() async {
          final b = await beacon(other, status: 2);
          await forward(b);
          return b;
        })(),
        false,
      );
      want('foreign private, no relation', await beacon(other), false);

      // Forward recipient.
      final forwarded = await beacon(other);
      await forward(forwarded);
      want('forward recipient', forwarded, true);
      final cancelledFwd = await beacon(other);
      await forward(cancelledFwd, cancelled: true);
      want('cancelled forward', cancelledFwd, false);

      // Participant.
      final steward = await beacon(other);
      await participant(steward, viewer, 1, 0);
      want('participant role 1', steward, true);
      final admitted = await beacon(other);
      await participant(admitted, viewer, 0, 3);
      want('participant room access 3', admitted, true);
      final unadmitted = await beacon(other);
      await participant(unadmitted, viewer, 0, 0);
      want('participant without access', unadmitted, false);

      // Beacon steward row.
      final stewarded = await beacon(other);
      await sql(
        "INSERT INTO public.beacon_steward (beacon_id, user_id) "
        "VALUES ('$stewarded', '$viewer')",
      );
      want('beacon steward', stewarded, true);

      // Help offers.
      final activeOffer = await beacon(other);
      await sql('''
INSERT INTO public.beacon_help_offer (beacon_id, user_id, message, status,
  created_at, updated_at)
VALUES ('$activeOffer', '$viewer', 'offer', 0, now(), now())
''');
      want('active help offer', activeOffer, true);
      final withdrawnOffer = await beacon(other);
      await sql('''
INSERT INTO public.beacon_help_offer (beacon_id, user_id, message, status,
  created_at, updated_at)
VALUES ('$withdrawnOffer', '$viewer', 'offer', 1, now(), now())
''');
      want('non-active help offer', withdrawnOffer, false);

      // Discoverable + mutual visibility.
      for (final status in [0, 7, 8]) {
        want(
          'discoverable mutual status $status',
          await beacon(friend, status: status, discoverable: true),
          true,
        );
      }
      for (final status in [1, 5, 6]) {
        want(
          'discoverable mutual closed status $status',
          await beacon(friend, status: status, discoverable: true),
          false,
        );
      }
      want(
        'discoverable mutual draft by friend',
        await beacon(friend, status: 3, published: false, discoverable: true),
        false,
      );
      want(
        'discoverable mutual unpublished',
        await beacon(friend, published: false, discoverable: true),
        false,
      );
      want('mutual but not discoverable', await beacon(friend), false);
      want(
        'discoverable but no mutual trust',
        await beacon(other, discoverable: true),
        false,
      );

      // Hierarchy: viewer is a member of a child/parent beacon.
      final grandparent = await beacon(other);
      final parent = await beacon(other, parent: grandparent);
      final childOwn = await beacon(viewer, parent: parent);
      want('parent of own child (context ancestor)', parent, true);
      want('grandparent of own grandchild', grandparent, true);
      final ownParent = await beacon(viewer);
      want(
        'child of own parent (context child)',
        await beacon(other, parent: ownParent),
        true,
      );
      final unrelatedParent = await beacon(other);
      want(
        'sibling-free parent without viewer membership',
        unrelatedParent,
        false,
      );
      await beacon(other, parent: unrelatedParent);
      want('own child itself', childOwn, true);
      // Draft child does not make the parent readable.
      final draftChildParent = await beacon(other);
      await beacon(
        viewer,
        status: 3,
        published: false,
        parent: draftChildParent,
      );
      want('parent of own draft child', draftChildParent, false);
      // Deleted child does not make the parent readable.
      final deletedChildParent = await beacon(other);
      await beacon(viewer, status: 2, parent: deletedChildParent);
      want('parent of own deleted child', deletedChildParent, false);
      // Participant (not author) of a child grants parent access.
      final partParent = await beacon(other);
      final partChild = await beacon(other, parent: partParent);
      await participant(partChild, viewer, 1, 0);
      want('parent of child the viewer participates in', partParent, true);
      // Blocks beat every grant, in both directions. Dedicated authors keep
      // these rows independent of the grants above.
      for (final id in [foe, foe2]) {
        await sql('''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ('$id', '$id', 'pk-$id', now(), now())
''');
      }
      await sql('''
INSERT INTO public.vote_user (subject, object, amount, created_at, updated_at)
VALUES ('$viewer', '$foe', 1, now(), now()),
       ('$foe', '$viewer', 1, now(), now()),
       ('$viewer', '$foe2', 1, now(), now()),
       ('$foe2', '$viewer', 1, now(), now())
''');
      await block(viewer, foe);
      await block(foe2, viewer);
      for (final author in [foe, foe2]) {
        final tag = author == foe
            ? 'viewer blocked author'
            : 'author blocked viewer';
        final fwd = await beacon(author);
        await forward(fwd);
        want('forward recipient but $tag', fwd, false);
        final part = await beacon(author);
        await participant(part, viewer, 1, 0);
        want('participant but $tag', part, false);
        want(
          'discoverable mutual but $tag',
          await beacon(author, discoverable: true),
          false,
        );
        final blockedParent = await beacon(author);
        final blockedChild = await beacon(author, parent: blockedParent);
        await participant(blockedChild, viewer, 1, 0);
        want('parent of participated child but $tag', blockedParent, false);
      }

      final ids = [for (var i = 0; i < next; i++) beaconId(i)];
      final perRow = await perRowReadable(viewer, ids);

      // The fixture itself must keep every branch alive.
      final trueNames = expected.entries.where((e) => e.value).length;
      final falseNames = expected.length - trueNames;
      expect(trueNames, greaterThanOrEqualTo(12));
      expect(falseNames, greaterThanOrEqualTo(12));
      for (final entry in expected.entries) {
        final id = entry.key.split('|').last;
        expect(
          perRow.contains(id),
          entry.value,
          reason: 'per-row verdict for ${entry.key}',
        );
      }
      // Per-row verdicts above pin the fixture; the set function must agree.
      final set = await setReadable(viewer, ids);
      for (final entry in expected.entries) {
        final id = entry.key.split('|').last;
        expect(
          set.contains(id),
          entry.value,
          reason: 'set verdict for ${entry.key}',
        );
      }
      expect(set, perRow);
    },
    skip: skipReason,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'set-based readable ids ignore unknown ids and an empty id list',
    () async {
      await seed(Random(7), 5);
      expect(await setReadable(userIds.first, ['Bnosuchbeacon']), isEmpty);
      expect(await setReadable(userIds.first, const []), isEmpty);
    },
    skip: skipReason,
  );

  test(
    'set-based readable ids are at least 5x faster than per-row checks on '
    '1000 beacons',
    () async {
      const beaconCount = 1000;
      await seed(Random(1000), beaconCount);
      final ids = [for (var i = 0; i < beaconCount; i++) beaconId(i)];
      final viewer = userIds.first;

      final perRowWatch = Stopwatch()..start();
      final expected = await perRowReadable(viewer, ids);
      perRowWatch.stop();

      final setWatch = Stopwatch()..start();
      final actual = await setReadable(viewer, ids);
      setWatch.stop();

      final ratio =
          perRowWatch.elapsedMicroseconds /
          (setWatch.elapsedMicroseconds == 0
              ? 1
              : setWatch.elapsedMicroseconds);
      // ignore: avoid_print
      print(
        'beacon_readable_ids timing: per-row ${perRowWatch.elapsedMilliseconds}'
        ' ms, set ${setWatch.elapsedMilliseconds} ms, '
        'speedup ${ratio.toStringAsFixed(1)}x over $beaconCount beacons',
      );

      expect(actual, expected);
      expect(ratio, greaterThanOrEqualTo(5));
    },
    skip: skipReason,
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

String _textArray(List<String> ids) =>
    '{${ids.map((id) => '"${id.replaceAll('"', r'\"')}"').join(',')}}';

final _target = DisposablePgTarget.fromNamedEnvironment(
  envVarName: 'TENTURA_BEACON_READABLE_IDS_TEST_DB',
  defaultNamePrefix: 'tentura_test_readable_ids',
);

Env _testEnv() => Env(
  environment: Environment.test,
  pgHost: Platform.environment['POSTGRES_HOST'] ?? 'localhost',
  pgPort: int.tryParse(Platform.environment['POSTGRES_PORT'] ?? '') ?? 5432,
  pgDatabase: _target.databaseName,
  pgUsername: Platform.environment['POSTGRES_USERNAME'] ?? 'postgres',
  pgPassword: Platform.environment['POSTGRES_PASSWORD'] ?? 'password',
  genealogyNodeKeySecret: 'test-genealogy-secret',
);
