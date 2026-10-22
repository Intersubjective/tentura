@Tags(['pg'])
library;

import 'dart:async';
import 'dart:convert';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts/coordination_item_consts.dart';

import '../../support/disposable_pg_target.dart';

/// m0257: creating (or changing, or deleting) the Request **Questions** item
/// (`coordination_item` kind 7) sends no `coordination_item` realtime hint,
/// so nobody outside the Questions audience learns that Questions was
/// opened. Every other coordination item still hints the General room
/// recipients exactly as before.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_M0257_QUESTIONS_ITEM_HINT_TEST_DB',
    defaultNamePrefix: 'tentura_test_m0257_qitem',
  );
  final skipReason = await pgSkipReason(target);

  const beaconId = 'Bqitem000001';
  const lobbyId = 'Lqitem000001';
  // Request author: General recipient and Questions audience.
  const author = 'Uqiauthor001';
  // Admitted helper: General recipient and Questions audience.
  const helper = 'Uqihelper001';
  // Admitted helper the author removed from Questions.
  const bannedHelper = 'Uqibanned001';
  // General room member outside the Questions audience: an admitted
  // participant who can no longer read the Request (blocked with the
  // author), so `questions_access_levels` gives them nothing.
  const generalOnly = 'Uqigenonl001';
  // Live forward: Questions audience only.
  const forwardee = 'Uqiforwrd001';

  group('m0257 Questions item realtime hint', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late Connection listener;
    late StreamSubscription<String> subscription;
    final notifications = <Map<String, dynamic>>[];

    Future<void> sql(String statement) => writer.execute(statement);

    setUpAll(() async {
      if (skipReason != null) return;
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      listener = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await listener.execute('LISTEN entity_changes');
      subscription = listener.channels['entity_changes'].listen(
        (payload) =>
            notifications.add(jsonDecode(payload) as Map<String, dynamic>),
      );
    });

    tearDownAll(() async {
      if (skipReason != null) return;
      await subscription.cancel();
      await listener.close();
      await tearDownDisposablePgWriter(session: session);
    });

    setUp(() async {
      if (skipReason != null) return;
      await sql(
        'TRUNCATE TABLE public.coordination_item, public.beacon_help_offer, '
        'public.beacon_forward_edge, public.beacon_participant, '
        'public.beacon_lobby_ban, public.user_block, public.beacon, '
        'public."user" CASCADE',
      );
      final users = [author, helper, bannedHelper, generalOnly, forwardee];
      await sql(
        'INSERT INTO public."user" (id, display_name, handle, public_key) '
        'VALUES ${[for (final u in users) "('$u', '${u.substring(3, 9)}', '${u.substring(3, 9)}', 'k$u')"].join(', ')}',
      );
      await sql(
        'INSERT INTO public.beacon (id, user_id, title, description, status, '
        'kind, is_discoverable, published_at, created_at, updated_at) VALUES '
        "('$beaconId', '$author', 'Moving day', 'desc', 0, 0, true, "
        "'2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', "
        "'2026-01-01T00:00:00Z')",
      );
      for (final u in [helper, bannedHelper, generalOnly, forwardee]) {
        await sql(
          'INSERT INTO public.beacon_forward_edge (beacon_id, sender_id, '
          "recipient_id) VALUES ('$beaconId', '$author', '$u')",
        );
      }
      for (final u in [helper, bannedHelper, generalOnly]) {
        await sql(
          'INSERT INTO public.beacon_help_offer (beacon_id, user_id, '
          "message, status) VALUES ('$beaconId', '$u', 'I can help', 0)",
        );
        await sql(
          'INSERT INTO public.beacon_participant (beacon_id, user_id, role, '
          "status, room_access) VALUES ('$beaconId', '$u', 2, 0, 3)",
        );
      }
      await sql(
        'INSERT INTO public.beacon_lobby_ban (beacon_id, user_id, banned_by) '
        "VALUES ('$beaconId', '$bannedHelper', '$author')",
      );
      await sql(
        'INSERT INTO public.user_block (blocker_id, blocked_id, origin_id) '
        "VALUES ('$author', '$generalOnly', '$author')",
      );
      // Settle every setup hint before the test watches the channel.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      notifications.clear();
    });

    /// Every `coordination_item` hint about [beaconId] after [action], once
    /// the stream has gone quiet (or [waitFor] all arrived).
    Future<List<Set<String>>> itemHintsAfter(
      Future<void> Function() action, {
      Set<String> waitFor = const {},
    }) async {
      notifications.clear();
      await action();
      List<Set<String>> current() => [
        for (final n in notifications)
          if (n['entity'] == 'coordination_item' && n['id'] == beaconId)
            (n['user_ids'] as List).cast<String>().toSet(),
      ];
      final deadline = DateTime.now().add(const Duration(seconds: 3));
      while (DateTime.now().isBefore(deadline) &&
          !current().expand((s) => s).toSet().containsAll(waitFor)) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      // A late hint would arrive in the same NOTIFY batch; give it a beat.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      return current();
    }

    Future<Set<String>> questionsAudience() async {
      final rows = await writer.execute(
        "SELECT user_id FROM public.questions_audience('$beaconId')",
      );
      return {for (final r in rows) r[0]! as String};
    }

    test('the fixture: banned and General-only members are General room '
        'recipients outside the Questions audience', () async {
      final general = await writer.execute(
        "SELECT public.realtime_room_recipients('$beaconId')",
      );
      expect(
        (general.single[0]! as List).cast<String>().toSet(),
        containsAll(<String>{author, helper, bannedHelper, generalOnly}),
      );
      final audience = await questionsAudience();
      expect(audience, containsAll(<String>{author, helper, forwardee}));
      expect(audience, isNot(contains(bannedHelper)));
      expect(audience, isNot(contains(generalOnly)));
    });

    test('creating, changing and deleting the Questions item sends no '
        'coordination_item hint to anyone', () async {
      final created = await itemHintsAfter(
        () => sql(
          'INSERT INTO public.coordination_item (id, beacon_id, kind, '
          'status, creator_id, published, published_at) VALUES '
          "('$lobbyId', '$beaconId', $coordinationItemKindLobby, 0, "
          "'$author', true, now())",
        ),
      );
      expect(created, isEmpty);

      final updated = await itemHintsAfter(
        () => sql(
          'UPDATE public.coordination_item SET updated_at = now() '
          "WHERE id = '$lobbyId'",
        ),
      );
      expect(updated, isEmpty);

      final deleted = await itemHintsAfter(
        () => sql(
          "DELETE FROM public.coordination_item WHERE id = '$lobbyId'",
        ),
      );
      expect(deleted, isEmpty);
    });

    test('a row turned into or out of the Questions kind sends no '
        'coordination_item hint', () async {
      await sql(
        'INSERT INTO public.coordination_item (id, beacon_id, kind, status, '
        'creator_id, title, published, published_at) VALUES '
        "('Cqitem000009', '$beaconId', $coordinationItemKindAsk, 0, "
        "'$author', 'Van?', true, now())",
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final intoQuestions = await itemHintsAfter(
        () => sql(
          'UPDATE public.coordination_item '
          'SET kind = $coordinationItemKindLobby '
          "WHERE id = 'Cqitem000009'",
        ),
      );
      expect(intoQuestions, isEmpty);
      final outOfQuestions = await itemHintsAfter(
        () => sql(
          'UPDATE public.coordination_item '
          'SET kind = $coordinationItemKindAsk '
          "WHERE id = 'Cqitem000009'",
        ),
      );
      expect(outOfQuestions, isEmpty);
    });

    test('other coordination items still hint every General recipient, '
        'banned from Questions or not (insert, update, delete)', () async {
      const itemId = 'Cqitem000001';
      const general = <String>{author, helper, bannedHelper, generalOnly};

      final created = await itemHintsAfter(
        () => sql(
          'INSERT INTO public.coordination_item (id, beacon_id, kind, '
          'status, creator_id, title, published, published_at) VALUES '
          "('$itemId', '$beaconId', $coordinationItemKindAsk, 0, "
          "'$helper', 'Who has a van?', true, now())",
        ),
        waitFor: general,
      );
      expect(created, hasLength(1));
      expect(created.single, containsAll(general));
      expect(created.single, isNot(contains(forwardee)));

      final updated = await itemHintsAfter(
        () => sql(
          "UPDATE public.coordination_item SET title = 'Who has a truck?' "
          "WHERE id = '$itemId'",
        ),
        waitFor: general,
      );
      expect(updated, hasLength(1));
      expect(updated.single, containsAll(general));

      final deleted = await itemHintsAfter(
        () => sql(
          "DELETE FROM public.coordination_item WHERE id = '$itemId'",
        ),
        waitFor: general,
      );
      expect(deleted, hasLength(1));
      expect(deleted.single, containsAll(general));
    });
  }, skip: skipReason);
}
