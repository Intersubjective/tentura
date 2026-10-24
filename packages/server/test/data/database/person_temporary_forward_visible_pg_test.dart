@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import '../../support/disposable_pg_target.dart';

/// `person_temporary_forward_peers(viewer)` / `person_temporary_forward_visible
/// (viewer, peer)`: a forwarded Request makes its author and its holder
/// visible to each other for as long as the holder keeps the Request.
const _towardViewer = 1;
const _towardAuthor = 2;

const _open = 0;
const _cancelled = 1;
const _deleted = 2;
const _closed = 6;

const _watching = 1;
const _rejected = 2;

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_PERSON_TEMPORARY_FORWARD_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_person_temporary_forward',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  group('person_temporary_forward_peers', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    var seq = 0;

    Future<void> sql(String statement) => writer.execute(statement);

    /// A fresh author/recipient pair and one forwarded Request.
    Future<({String author, String holder, String beacon})> scenario({
      int kind = 0,
      int status = _open,
    }) async {
      final n = (++seq).toString().padLeft(4, '0');
      final author = 'Utfauthor$n';
      final holder = 'Utfholder$n';
      final beacon = 'Btfreq$n';
      for (final id in [author, holder]) {
        await sql('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('$id', '$id', 'pk-$id')
''');
      }
      await sql('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, is_discoverable,
   published_at, created_at, status_changed_at)
VALUES ('$beacon', '$author', '${kind == 0 ? 'Request $n' : ''}',
  '${kind == 0 ? 'd' : ''}', $status, $kind, ${kind == 0},
  now() - interval '1 day', now() - interval '1 day', now() - interval '1 day')
''');
      await sql('''
INSERT INTO public.beacon_forward_edge (beacon_id, sender_id, recipient_id)
VALUES ('$beacon', '$author', '$holder')
''');
      return (author: author, holder: holder, beacon: beacon);
    }

    Future<Map<String, ({String beaconId, int direction})>> peers(
      String viewer,
    ) async {
      final rows = await writer.execute(
        Sql.named(
          'SELECT peer_id, beacon_id, direction '
          'FROM public.person_temporary_forward_peers(@viewer)',
        ),
        parameters: {'viewer': viewer},
      );
      return {
        for (final r in rows)
          r[0]! as String: (
            beaconId: r[1]! as String,
            direction: r[2]! as int,
          ),
      };
    }

    Future<bool> visible(String viewer, String peer) async {
      final rows = await writer.execute(
        Sql.named(
          'SELECT public.person_temporary_forward_visible(@viewer, @peer)',
        ),
        parameters: {'viewer': viewer, 'peer': peer},
      );
      return rows.single[0]! as bool;
    }

    /// Both directions at once: (viewer sees author, author sees viewer).
    Future<({bool holderSeesAuthor, bool authorSeesHolder})> both(
      ({String author, String holder, String beacon}) s,
    ) async => (
      holderSeesAuthor: await visible(s.holder, s.author),
      authorSeesHolder: await visible(s.author, s.holder),
    );

    Future<void> setInbox(
      ({String author, String holder, String beacon}) s,
      int status,
    ) => sql('''
UPDATE public.inbox_item SET status = $status
WHERE user_id = '${s.holder}' AND beacon_id = '${s.beacon}'
''');

    setUpAll(() async {
      session = await setUpDisposablePgWriter(
        target: target,
        createPgmer2Extension: true,
      );
      writer = session.writer;
    });

    tearDownAll(() async {
      await session.writer.close();
      await target.drop();
    });

    test('recipient with the Request in needs-me sees its author', () async {
      final s = await scenario();
      expect(await visible(s.holder, s.author), isTrue);
      expect(
        (await peers(s.holder))[s.author],
        (beaconId: s.beacon, direction: _towardViewer),
      );
    });

    test('recipient watching the Request still sees its author', () async {
      final s = await scenario();
      await setInbox(s, _watching);
      expect(await visible(s.holder, s.author), isTrue);
    });

    test('active help offer keeps the author visible', () async {
      final s = await scenario();
      await setInbox(s, _rejected);
      expect(await visible(s.holder, s.author), isFalse);
      await sql('''
INSERT INTO public.beacon_help_offer (beacon_id, user_id, message, status)
VALUES ('${s.beacon}', '${s.holder}', 'offer', 0)
''');
      expect(await visible(s.holder, s.author), isTrue);
    });

    test('rejecting the Request ends direction 1', () async {
      final s = await scenario();
      await setInbox(s, _rejected);
      expect(await visible(s.holder, s.author), isFalse);
      expect(await peers(s.holder), isEmpty);
    });

    for (final entry in {
      'closed': _closed,
      'cancelled': _cancelled,
      'deleted': _deleted,
    }.entries) {
      test('${entry.key} Request ends direction 1', () async {
        final s = await scenario();
        expect(await visible(s.holder, s.author), isTrue);
        await sql('''
UPDATE public.beacon SET status = ${entry.value} WHERE id = '${s.beacon}'
''');
        expect(await visible(s.holder, s.author), isFalse);
      });
    }

    test('cancelled forward ends direction 1', () async {
      final s = await scenario();
      await sql('''
UPDATE public.beacon_forward_edge SET cancelled_at = now()
WHERE beacon_id = '${s.beacon}'
''');
      expect(await visible(s.holder, s.author), isFalse);
    });

    test('a Post never makes its author temporarily visible', () async {
      final s = await scenario(kind: 1);
      expect(await visible(s.holder, s.author), isFalse);
      expect(await peers(s.holder), isEmpty);
    });

    test('a block between the pair ends direction 1', () async {
      final s = await scenario();
      await sql('''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES ('${s.holder}', '${s.author}', '${s.author}')
''');
      expect(await visible(s.holder, s.author), isFalse);
    });

    test('unrelated people are not temporarily visible', () async {
      final s = await scenario();
      expect(await visible(s.holder, s.holder), isFalse);
      expect(await peers(s.author), isNot(contains(s.author)));
    });

    test('author sees the holder while the holder keeps the Request', () async {
      final s = await scenario();
      expect(await both(s), (holderSeesAuthor: true, authorSeesHolder: true));
      expect(
        (await peers(s.author))[s.holder],
        (beaconId: s.beacon, direction: _towardAuthor),
      );
    });

    test('author sees the holder watching or with an active offer', () async {
      final s = await scenario();
      await setInbox(s, _watching);
      expect(await visible(s.author, s.holder), isTrue);
      await setInbox(s, _rejected);
      await sql('''
INSERT INTO public.beacon_help_offer (beacon_id, user_id, message, status)
VALUES ('${s.beacon}', '${s.holder}', 'offer', 0)
''');
      expect(await visible(s.author, s.holder), isTrue);
    });

    for (final entry in {
      'closed': _closed,
      'cancelled': _cancelled,
      'deleted': _deleted,
    }.entries) {
      test('${entry.key} Request ends direction 2', () async {
        final s = await scenario();
        expect(await visible(s.author, s.holder), isTrue);
        await sql(
          'UPDATE public.beacon SET status = ${entry.value} '
          "WHERE id = '${s.beacon}'",
        );
        expect(await visible(s.author, s.holder), isFalse);
      });
    }

    test('cancelled forward ends direction 2', () async {
      final s = await scenario();
      await sql('''
UPDATE public.beacon_forward_edge SET cancelled_at = now()
WHERE beacon_id = '${s.beacon}'
''');
      expect(await visible(s.author, s.holder), isFalse);
    });

    test('direction 2 for a Post and for a blocked pair is false', () async {
      final post = await scenario(kind: 1);
      expect(await visible(post.author, post.holder), isFalse);

      final blocked = await scenario();
      await sql('''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES ('${blocked.author}', '${blocked.holder}', '${blocked.holder}')
''');
      expect(await visible(blocked.author, blocked.holder), isFalse);
    });

    test('rejection does not make the holder vanish for the author '
        '(the author cannot learn of a rejection from the node)', () async {
      // Rule recorded in the journal: an author cannot see a recipient's
      // rejection today, so direction 2 ends with the Request, not with the
      // rejection.
      final s = await scenario();
      await setInbox(s, _rejected);
      expect(await visible(s.author, s.holder), isTrue);
    });
  });
}
