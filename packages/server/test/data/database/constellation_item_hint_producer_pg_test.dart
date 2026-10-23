@Tags(['pg'])
library;

import 'dart:async';
import 'dart:convert';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import '../../support/disposable_pg_target.dart';

/// #671: a Request that becomes discoverable emits ONE `constellation_item`
/// hint (id = the Request, event `insert`) to everyone whose field has the
/// author as a direct contact — the people who trust the author — and to no
/// one else (not someone only the author trusts, not a blocked one). The hint
/// carries no content; later edits emit nothing. (A Post can never be
/// discoverable: `beacon_post_shape_ck`.)
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_CONSTELLATION_ITEM_HINT_TEST_DB',
    defaultNamePrefix: 'tentura_test_cihint',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('constellation item hint producer', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late Connection listener;
    late StreamSubscription<String> subscription;
    final notifications = <Map<String, dynamic>>[];

    const author = 'Ucihintauthor';
    const truster = 'Ucihinttruster';
    const trusted = 'Ucihinttrusted';
    const stranger = 'Ucihintstrangr';
    const blocked = 'Ucihintblocked';

    List<Map<String, dynamic>> itemHints() => notifications
        .where((m) => m['entity'] == 'constellation_item')
        .toList();

    Future<void> settle([int ms = 300]) =>
        Future<void>.delayed(Duration(milliseconds: ms));

    Future<void> vote(String subject, String object) => writer.execute(
      Sql.named('''
INSERT INTO public.vote_user (subject, object, amount)
VALUES (@s, @o, 1)
ON CONFLICT (subject, object) DO UPDATE SET amount = 1
'''),
      parameters: {'s': subject, 'o': object},
    );

    Future<void> insertBeacon(
      String id, {
      bool discoverable = true,
      bool published = true,
    }) => writer.execute('''
INSERT INTO public.beacon (
  id, user_id, title, description, status, is_discoverable,
  published_at, created_at, updated_at
) VALUES (
  '$id', '$author', 'secret title', 'secret description', 0,
  $discoverable, ${published ? 'now()' : 'NULL'}, now(), now()
)
''');

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      for (final id in [author, truster, trusted, stranger, blocked]) {
        await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ('$id', '$id', 'pk-$id', now(), now())
''');
      }
      await vote(truster, author);
      await vote(author, trusted);
      await vote(blocked, author);
      await writer.execute('''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES ('$author', '$blocked', '$author')
''');
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
        "DELETE FROM public.beacon WHERE user_id = '$author'",
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

    test('publishing a discoverable Request addresses the people who trust '
        'the author only, with no content', () async {
      await insertBeacon('Bcihint0001');
      await settle();

      final hints = itemHints();
      expect(hints, hasLength(1));
      final hint = hints.single;
      expect(hint['id'], 'Bcihint0001');
      expect(hint['event'], 'insert');
      expect(
        (hint['user_ids'] as List).cast<String>(),
        [truster],
      );
      final wire = jsonEncode(hint);
      expect(wire, isNot(contains('secret')));
      expect(
        hint.keys.toSet(),
        containsAll(<String>{'event', 'entity', 'id', 'user_ids'}),
      );
      expect(
        hint.keys.toSet().difference({
          'event',
          'entity',
          'id',
          'user_ids',
          'actor_user_id',
        }),
        isEmpty,
      );
    }, skip: skipReason);

    test('a draft emits nothing until it is published; edits after that '
        'emit nothing more', () async {
      await insertBeacon('Bcihint0002', published: false);
      await settle();
      expect(itemHints(), isEmpty);

      await writer.execute(
        'UPDATE public.beacon SET published_at = now() '
        "WHERE id = 'Bcihint0002'",
      );
      await settle();
      expect(itemHints(), hasLength(1));

      await writer.execute(
        "UPDATE public.beacon SET title = 'renamed', published_at = now() "
        "WHERE id = 'Bcihint0002'",
      );
      await settle();
      expect(itemHints(), hasLength(1));
    }, skip: skipReason);

    test('a hidden Request emits nothing until it is made findable', () async {
      await insertBeacon('Bcihint0003', discoverable: false);
      await settle();
      expect(itemHints(), isEmpty);

      await writer.execute(
        'UPDATE public.beacon SET is_discoverable = true '
        "WHERE id = 'Bcihint0003'",
      );
      await settle();
      expect(itemHints().map((h) => h['id']), ['Bcihint0003']);
    }, skip: skipReason);
  });
}
