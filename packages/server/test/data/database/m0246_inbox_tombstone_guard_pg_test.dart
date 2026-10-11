@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

/// m0246: `inbox_item_guard_tombstone` lets the beacon trigger move a
/// closed-before-response row (3) back to 0 on reopen from review and up to
/// 4 on delete; every other status change on a tombstone row, and every
/// change made outside the beacon trigger, is still refused.
const _author = 'Um0245author1';
const _recipient = 'Um0245recip01';
const _request = 'Bm0245request';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_M0246_INBOX_TOMBSTONE_GUARD_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_m0246_tombstone_guard',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  late DisposablePgWriterSession session;
  late Connection writer;

  setUpAll(() async {
    session = await setUpDisposablePgWriter(target: target);
    writer = session.writer;
  });

  setUp(() async => _seed(writer));

  tearDownAll(() async {
    await tearDownDisposablePgWriter(session: session);
  });

  for (final reopenTo in [0, 7, 8]) {
    test('review → $reopenTo reverts an untouched row to 0', () async {
      await _setStatus(writer, 5);
      expect(await _inboxStatus(writer), 3);

      await _setStatus(writer, reopenTo);

      final row = await _inboxRow(writer);
      expect(row.status, 0);
      expect(row.terminalAt, isNull);
    });
  }

  test('delete after review upgrades the tombstone 3 → 4', () async {
    await _setStatus(writer, 5);
    await _setStatus(writer, 2);
    expect(await _inboxStatus(writer), 4);
  });

  test('outside the beacon trigger a tombstone row is frozen', () async {
    await _setStatus(writer, 5);
    for (final to in [0, 1, 2, 4]) {
      await expectLater(
        _setInboxStatus(writer, to),
        throwsA(isA<ServerException>()),
        reason: '3 → $to',
      );
    }
    await expectLater(
      writer.execute(
        "UPDATE public.inbox_item SET rejection_message = 'x' "
        "WHERE beacon_id = '$_request'",
      ),
      throwsA(isA<ServerException>()),
    );

    await _setStatus(writer, 2);
    for (final to in [0, 3]) {
      await expectLater(
        _setInboxStatus(writer, to),
        throwsA(isA<ServerException>()),
        reason: '4 → $to',
      );
    }
    expect(await _inboxStatus(writer), 4);
  });

  test('even under the trigger flag only 3 → 0 and 3 → 4 pass', () async {
    await _setStatus(writer, 5);
    for (final to in [1, 2]) {
      await expectLater(
        writer.runTx((tx) async {
          await tx.execute(
            "SELECT set_config('tentura.allow_inbox_tombstone_transition', "
            "'1', true)",
          );
          await tx.execute(
            'UPDATE public.inbox_item SET status = $to '
            "WHERE beacon_id = '$_request'",
          );
        }),
        throwsA(isA<ServerException>()),
        reason: '3 → $to',
      );
    }
    expect(await _inboxStatus(writer), 3);
  });
}

Future<void> _seed(Connection writer) async {
  await writer.execute('''
TRUNCATE TABLE
  public.inbox_item,
  public.beacon_forward_edge,
  public.beacon,
  public."user"
CASCADE
''');
  final users = [_author, _recipient];
  for (var i = 0; i < users.length; i++) {
    await writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
      parameters: {'id': users[i], 'key': pgTestPublicKey('m0246', i + 1)},
    );
  }
  await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, published_at)
VALUES ('$_request', '$_author', 'Request', 'desc', 0, now())
''');
  await writer.execute('''
INSERT INTO public.inbox_item (user_id, beacon_id)
VALUES ('$_recipient', '$_request')
''');
}

Future<void> _setStatus(Connection writer, int status) => writer.execute(
  Sql.named('UPDATE public.beacon SET status = @s WHERE id = @b'),
  parameters: {'s': status, 'b': _request},
);

Future<void> _setInboxStatus(Connection writer, int status) => writer.execute(
  Sql.named('UPDATE public.inbox_item SET status = @s WHERE beacon_id = @b'),
  parameters: {'s': status, 'b': _request},
);

Future<({int status, DateTime? terminalAt})> _inboxRow(
  Connection writer,
) async {
  final row = (await writer.execute(
    Sql.named(
      'SELECT status, before_response_terminal_at '
      'FROM public.inbox_item WHERE beacon_id = @b',
    ),
    parameters: {'b': _request},
  )).single;
  return (status: row[0]! as int, terminalAt: row[1] as DateTime?);
}

Future<int> _inboxStatus(Connection writer) async =>
    (await _inboxRow(writer)).status;
