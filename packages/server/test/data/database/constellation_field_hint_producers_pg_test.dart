@Tags(['pg'])
library;

import 'dart:async';
import 'dart:convert';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import '../../support/disposable_pg_target.dart';

/// Visibility changes (trust edges, MR publication, blocks) emit
/// `constellation_field` hints on the `entity_changes` channel: trust and
/// publication emit ONE global payload-free marker per change (never a
/// per-viewer enumeration); a block addresses both parties.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_CONSTELLATION_FIELD_HINT_TEST_DB',
    defaultNamePrefix: 'tentura_test_cfhint',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('constellation field hint producers', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late Connection listener;
    late StreamSubscription<String> subscription;
    final notifications = <Map<String, dynamic>>[];

    const alice = 'Ucfhintalice1';
    const bob = 'Ucfhintbob0001';
    const carol = 'Ucfhintcarol01';

    List<Map<String, dynamic>> fieldHints() => notifications
        .where((m) => m['entity'] == 'constellation_field')
        .toList();

    List<Map<String, dynamic>> globalMarkers() =>
        fieldHints().where((m) => m['id'] == 'global').toList();

    Future<void> settle([int ms = 300]) =>
        Future<void>.delayed(Duration(milliseconds: ms));

    Future<void> upsertTrust(String subject, String object, double good) =>
        writer.execute(
          Sql.named('''
INSERT INTO public.user_trust_edge (subject, object, trust_w, target_w)
VALUES (@s, @o, @g, @g)
ON CONFLICT (subject, object) DO UPDATE SET trust_w = EXCLUDED.trust_w
'''),
          parameters: {'s': subject, 'o': object, 'g': good},
        );

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      for (final id in [alice, bob, carol]) {
        await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ('$id', '$id', 'pk-$id', now(), now())
''');
      }
      listener = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await listener.execute('LISTEN entity_changes');
      subscription = listener.channels['entity_changes'].listen(
        (payload) =>
            notifications.add(jsonDecode(payload) as Map<String, dynamic>),
      );
      await settle();
    });

    setUp(() async {
      await writer.execute(
        'DELETE FROM public.user_block '
        "WHERE blocker_id IN ('$alice', '$bob', '$carol')",
      );
      await writer.execute(
        'DELETE FROM public.user_trust_edge '
        "WHERE subject IN ('$alice', '$bob', '$carol')",
      );
      await settle();
      notifications.clear();
    });

    tearDownAll(() async {
      if (!session.setupComplete) {
        return;
      }
      await subscription.cancel();
      await listener.close();
      await tearDownDisposablePgWriter(session: session);
    });

    test('a trust change emits exactly one global marker', () async {
      await upsertTrust(alice, bob, 1);
      await settle();

      final markers = globalMarkers();
      expect(markers, hasLength(1));
      expect(markers.single['event'], 'update');
      expect(markers.single.containsKey('revision'), isFalse);
      // No per-viewer enumeration: no hint addressed to a specific user.
      expect(fieldHints(), hasLength(1));
    }, skip: skipReason);

    test('an MR publication epoch bump emits exactly one global marker',
        () async {
      final updated = await writer.execute(
        'UPDATE public.mr_publish_epoch SET epoch = epoch + 1 '
        'WHERE id = true',
      );
      expect(updated.affectedRows, 1);
      await settle();

      expect(globalMarkers(), hasLength(1));
      expect(fieldHints(), hasLength(1));
    }, skip: skipReason);

    test('a multi-row trust statement still emits one marker', () async {
      await writer.execute('''
INSERT INTO public.user_trust_edge (subject, object, trust_w, target_w)
VALUES ('$alice', '$bob', 1, 1), ('$alice', '$carol', 1, 1),
       ('$bob', '$carol', 1, 1)
''');
      await settle();

      expect(globalMarkers(), hasLength(1));
      expect(fieldHints(), hasLength(1));
    }, skip: skipReason);

    test('a block notifies both the blocker and the blocked user', () async {
      await writer.execute('''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES ('$alice', '$bob', '$alice')
''');
      await settle();

      final recipients = <String>{
        for (final h in fieldHints().where((h) => h['id'] != 'global'))
          ...(h['user_ids'] as List).cast<String>(),
      };
      expect(recipients, {alice, bob});
      expect(recipients, isNot(contains(carol)));
    }, skip: skipReason);

    test('removing a block notifies both parties again', () async {
      await writer.execute('''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES ('$alice', '$bob', '$alice')
''');
      await settle();
      notifications.clear();

      await writer.execute(
        "DELETE FROM public.user_block WHERE blocker_id = '$alice'",
      );
      await settle();

      final recipients = <String>{
        for (final h in fieldHints().where((h) => h['id'] != 'global'))
          ...(h['user_ids'] as List).cast<String>(),
      };
      expect(recipients, {alice, bob});
    }, skip: skipReason);

    test('100 trust changes in one second emit 100 markers', () async {
      final started = DateTime.timestamp();
      for (var i = 0; i < 100; i++) {
        await upsertTrust(alice, bob, 1.0 + i);
      }
      final elapsed = DateTime.timestamp().difference(started);
      await settle(500);

      expect(elapsed, lessThan(const Duration(seconds: 5)));
      expect(globalMarkers(), hasLength(100));
    }, skip: skipReason);
  });
}
