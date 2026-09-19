@Tags(['pg'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:injectable/injectable.dart' show Environment;
import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/inbox_repository.dart';
import 'package:tentura_server/env.dart';

import '../../support/pg_test_public_keys.dart';

const _beaconId = 'Binboxtest01';
const _authorId = 'Uinboxtestauth';
const _recipientId = 'Uinboxtestrecp';
const _senderId = 'Uinboxtestsend';
const _sender2Id = 'Uinboxtestsnd2';
const _watcherId = 'Uinboxtestwatch';

/// Postgres integration — inbox state machine + provenance (COV-090).
Future<void> main() async {
  final postgresReachable = await _canConnectPostgres();
  var skipReason = postgresReachable ? false : 'local Postgres not reachable';
  var tombstoneSkipReason = skipReason;
  var provenanceSkipReason = skipReason;
  var latestNoteSkipReason = skipReason;

  if (postgresReachable) {
    final env = _testEnv();
    final probe = TenturaDb(env);
    try {
      if (!await _hasInboxSchema(probe)) {
        skipReason = 'inbox_item status / tombstone function missing';
        tombstoneSkipReason = skipReason;
        provenanceSkipReason = skipReason;
        latestNoteSkipReason = skipReason;
      } else {
        if (!await _hasM0102TombstoneFunction(probe)) {
          tombstoneSkipReason =
              'm0102 tombstone function (beacon.status) missing';
        }
        if (!await _hasM0100Provenance(probe)) {
          provenanceSkipReason =
              'm0100 provenance (cancelled_at filter) missing';
        } else if (!await _hasM0103Provenance(probe)) {
          provenanceSkipReason =
              'm0103 provenance (self/context invite-forward) missing';
        }
        latestNoteSkipReason = provenanceSkipReason;
        if (latestNoteSkipReason == false &&
            !await _hasM0190LatestNoteForward(probe)) {
          latestNoteSkipReason =
              'm0190 provenance (latestNoteForward) missing';
        }
      }
    } finally {
      await probe.close();
    }
  }

  late TenturaDb db;
  late InboxRepository repo;

  if (skipReason == false) {
    setUpAll(() async {
      db = TenturaDb(_testEnv());
      repo = InboxRepository(db);
    });

    tearDownAll(() async {
      await db.close();
    });

    tearDown(() async {
      await db.customStatement(
        "DELETE FROM public.beacon_forward_edge WHERE beacon_id LIKE 'Binboxtest%'",
      );
      await db.customStatement(
        "DELETE FROM public.inbox_item WHERE beacon_id LIKE 'Binboxtest%'",
      );
      await db.customStatement(
        "DELETE FROM public.beacon WHERE id LIKE 'Binboxtest%'",
      );
      await db.customStatement(
        '''DELETE FROM public."user" WHERE id LIKE 'Uinboxtest%' ''',
      );
    });
  }

  Future<void> seedUsers() async {
    final keyA = pgTestPublicKey('inboxtest', 1);
    final keyB = pgTestPublicKey('inboxtest', 2);
    final keyC = pgTestPublicKey('inboxtest', 3);
    final keyD = pgTestPublicKey('inboxtest', 4);
    final keyE = pgTestPublicKey('inboxtest', 5);
    await db.customStatement(
      r'''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES
  ($1, 'Author', $2, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
  ($3, 'Recipient', $4, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
  ($5, 'Sender One', $6, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
  ($7, 'Sender Two', $8, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
  ($9, 'Watcher', $10, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO UPDATE SET
  display_name = EXCLUDED.display_name,
  public_key = EXCLUDED.public_key
''',
      [
        _authorId,
        keyA,
        _recipientId,
        keyB,
        _senderId,
        keyC,
        _sender2Id,
        keyD,
        _watcherId,
        keyE,
      ],
    );
  }

  Future<void> seedBeacon({int status = 0}) async {
    await db.customStatement(
      r'''
INSERT INTO public.beacon (id, user_id, title, description, status, created_at, updated_at)
VALUES ($1, $2, 'Inbox repo test', '', $3, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO UPDATE SET status = EXCLUDED.status
''',
      [_beaconId, _authorId, status],
    );
  }

  Future<int> inboxStatus(String userId) async {
    final row = await db
        .customSelect(
          'SELECT status FROM public.inbox_item WHERE user_id = \$1 AND beacon_id = \$2',
          variables: [Variable<String>(userId), Variable<String>(_beaconId)],
        )
        .getSingle();
    return row.read<int>('status');
  }

  Future<DateTime?> inboxLatestForwardAt(String userId) async {
    final row = await db
        .customSelect(
          'SELECT latest_forward_at::text AS latest_forward_at '
          'FROM public.inbox_item WHERE user_id = \$1 AND beacon_id = \$2',
          variables: [Variable<String>(userId), Variable<String>(_beaconId)],
        )
        .getSingleOrNull();
    final text = row?.read<String>('latest_forward_at');
    return text == null ? null : DateTime.parse(text).toUtc();
  }

  test(
    'fetchWatchingUserIdsByBeacon and fetchRejectedUserIdsByBeacon filter by status',
    () async {
      await seedUsers();
      await seedBeacon();

      await db.customStatement(
        r'''
INSERT INTO public.inbox_item (
  user_id, beacon_id, status, forward_count, latest_forward_at, latest_note_preview, rejection_message
) VALUES
  ($1, $2, 0, 1, '2026-01-01T00:00:00Z', 'needs me', ''),
  ($3, $2, 1, 0, '2026-01-02T00:00:00Z', '', ''),
  ($4, $2, 2, 0, '2026-01-03T00:00:00Z', '', 'no thanks')
ON CONFLICT (user_id, beacon_id) DO UPDATE SET status = EXCLUDED.status
''',
        [_recipientId, _beaconId, _watcherId, _senderId],
      );

      expect(
        await repo.fetchWatchingUserIdsByBeacon(_beaconId),
        [_watcherId],
      );
      expect(
        await repo.fetchRejectedUserIdsByBeacon(_beaconId),
        [_senderId],
      );
    },
    skip: skipReason,
  );

  test(
    'upsertWatchingForSender sets watching and preserves forward_count on conflict',
    () async {
      await seedUsers();
      await seedBeacon();

      await db.customStatement(
        r'''
INSERT INTO public.inbox_item (
  user_id, beacon_id, status, forward_count, latest_forward_at, latest_note_preview, rejection_message
) VALUES ($1, $2, 2, 3, '2026-01-01T00:00:00Z', 'old preview', 'prior reject')
ON CONFLICT (user_id, beacon_id) DO NOTHING
''',
        [_senderId, _beaconId],
      );

      await repo.upsertWatchingForSender(
        senderId: _senderId,
        beaconId: _beaconId,
      );

      expect(await inboxStatus(_senderId), 1);
      final row = await db
          .customSelect(
            'SELECT forward_count, latest_note_preview, rejection_message '
            'FROM public.inbox_item WHERE user_id = \$1 AND beacon_id = \$2',
            variables: [
              Variable<String>(_senderId),
              Variable<String>(_beaconId),
            ],
          )
          .getSingle();
      expect(row.read<int>('forward_count'), 3);
      expect(row.read<String>('latest_note_preview'), 'old preview');
      expect(row.read<String>('rejection_message'), '');
    },
    skip: skipReason,
  );

  test(
    'upsertWatchingForSender with touchForwardOrdering false keeps latest_forward_at on conflict',
    () async {
      await seedUsers();
      await seedBeacon();

      const stableAt = '2020-06-15T12:00:00Z';
      await db.customStatement(
        r'''
INSERT INTO public.inbox_item (
  user_id, beacon_id, status, forward_count, latest_forward_at, latest_note_preview, rejection_message
) VALUES ($1, $2, 0, 1, $3::timestamptz, '', '')
ON CONFLICT (user_id, beacon_id) DO NOTHING
''',
        [_senderId, _beaconId, stableAt],
      );

      await repo.upsertWatchingForSender(
        senderId: _senderId,
        beaconId: _beaconId,
        touchForwardOrdering: false,
      );

      final at = await inboxLatestForwardAt(_senderId);
      expect(at, DateTime.parse(stableAt).toUtc());
      expect(await inboxStatus(_senderId), 1);
    },
    skip: skipReason,
  );

  test(
    'setStatus writes rejected status and message',
    () async {
      await seedUsers();
      await seedBeacon();

      await db.customStatement(
        r'''
INSERT INTO public.inbox_item (
  user_id, beacon_id, status, forward_count, latest_forward_at, latest_note_preview, rejection_message
) VALUES ($1, $2, 0, 1, '2026-01-01T00:00:00Z', '', '')
ON CONFLICT (user_id, beacon_id) DO NOTHING
''',
        [_recipientId, _beaconId],
      );

      await repo.setStatus(
        userId: _recipientId,
        beaconId: _beaconId,
        status: 2,
        rejectionMessage: 'not for me',
      );

      expect(await inboxStatus(_recipientId), 2);
      final msg = await db
          .customSelect(
            'SELECT rejection_message FROM public.inbox_item WHERE user_id = \$1 AND beacon_id = \$2',
            variables: [
              Variable<String>(_recipientId),
              Variable<String>(_beaconId),
            ],
          )
          .getSingle();
      expect(msg.read<String>('rejection_message'), 'not for me');
    },
    skip: skipReason,
  );

  test(
    'markForwardCancelledForRecipient only closes needs_me rows',
    () async {
      await seedUsers();
      await seedBeacon();

      await db.customStatement(
        r'''
INSERT INTO public.inbox_item (
  user_id, beacon_id, status, forward_count, latest_forward_at, latest_note_preview, rejection_message
) VALUES
  ($1, $2, 0, 1, '2026-01-01T00:00:00Z', '', ''),
  ($3, $2, 1, 0, '2026-01-02T00:00:00Z', '', ''),
  ($4, $2, 2, 0, '2026-01-03T00:00:00Z', '', 'nope')
ON CONFLICT (user_id, beacon_id) DO NOTHING
''',
        [_recipientId, _beaconId, _watcherId, _senderId],
      );

      await repo.markForwardCancelledForRecipient(
        beaconId: _beaconId,
        recipientId: _recipientId,
      );

      expect(await inboxStatus(_recipientId), 3);
      expect(await inboxStatus(_watcherId), 1);
      expect(await inboxStatus(_senderId), 2);
    },
    skip: skipReason,
  );

  test(
    'fetchByUserId orders by latest_forward_at desc and filters context',
    () async {
      await seedUsers();

      await db.customStatement(
        r'''
INSERT INTO public.beacon (id, user_id, title, description, status, created_at, updated_at)
VALUES
  ($1, $2, 'Alpha beacon', '', 0, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
  ($3, $2, 'Beta beacon', '', 0, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''',
        ['${_beaconId}a', _authorId, '${_beaconId}b'],
      );
      await db.customStatement(
        r'''
INSERT INTO public.inbox_item (
  user_id, beacon_id, context, status, forward_count, latest_forward_at, latest_note_preview, rejection_message
) VALUES
  ($1, $2, 'alpha', 0, 1, '2026-01-01T00:00:00Z', '', ''),
  ($1, $3, 'beta', 0, 1, '2026-01-03T00:00:00Z', '', '')
ON CONFLICT (user_id, beacon_id) DO NOTHING
''',
        [_recipientId, '${_beaconId}a', '${_beaconId}b'],
      );

      final all = await repo.fetchByUserId(_recipientId);
      expect(all.map((e) => e.beaconId), ['${_beaconId}b', '${_beaconId}a']);

      final betaOnly = await repo.fetchByUserId(_recipientId, context: 'beta');
      expect(betaOnly, hasLength(1));
      expect(betaOnly.single.beaconId, '${_beaconId}b');
    },
    skip: skipReason,
  );

  test(
    'applyTombstoneAfterWithdraw maps watching to closed_before_response or deleted_before_response',
    () async {
      await seedUsers();

      await seedBeacon(status: BeaconStatus.closed.smallintValue);
      await db.customStatement(
        r'''
INSERT INTO public.inbox_item (
  user_id, beacon_id, status, forward_count, latest_forward_at, latest_note_preview, rejection_message
) VALUES ($1, $2, 1, 0, '2026-01-01T00:00:00Z', '', '')
ON CONFLICT (user_id, beacon_id) DO NOTHING
''',
        [_watcherId, _beaconId],
      );

      await repo.applyTombstoneAfterWithdraw(
        userId: _watcherId,
        beaconId: _beaconId,
      );
      expect(await inboxStatus(_watcherId), 3);

      await db.customStatement(
        r'''
DELETE FROM public.inbox_item WHERE user_id = $1 AND beacon_id = $2
''',
        [_watcherId, _beaconId],
      );
      await seedBeacon(status: BeaconStatus.deleted.smallintValue);
      await db.customStatement(
        r'''
INSERT INTO public.inbox_item (
  user_id, beacon_id, status, forward_count, latest_forward_at, latest_note_preview, rejection_message
) VALUES ($1, $2, 1, 0, '2026-01-01T00:00:00Z', '', '')
ON CONFLICT (user_id, beacon_id) DO NOTHING
''',
        [_watcherId, _beaconId],
      );

      await repo.applyTombstoneAfterWithdraw(
        userId: _watcherId,
        beaconId: _beaconId,
      );
      expect(await inboxStatus(_watcherId), 4);
    },
    skip: tombstoneSkipReason,
  );

  test(
    'inbox provenance excludes cancelled forward edges',
    () async {
      await seedUsers();
      await seedBeacon();

      await db.customStatement(
        r'''
INSERT INTO public.inbox_item (
  user_id, beacon_id, status, forward_count, latest_forward_at, latest_note_preview, rejection_message
) VALUES ($1, $2, 0, 1, '2026-01-01T00:00:00Z', '', '')
ON CONFLICT (user_id, beacon_id) DO NOTHING
''',
        [_recipientId, _beaconId],
      );

      await db.customStatement(
        r'''
INSERT INTO public.beacon_forward_edge (
  id, beacon_id, sender_id, recipient_id, note, created_at
) VALUES
  ('Finboxtest01', $1, $2, $3, 'active note', '2026-01-01T00:00:00Z'),
  ('Finboxtest02', $1, $4, $3, 'cancelled note', '2026-01-02T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''',
        [_beaconId, _senderId, _recipientId, _sender2Id],
      );
      await db.customStatement(
        '''
UPDATE public.beacon_forward_edge
SET cancelled_at = now()
WHERE id = 'Finboxtest02'
''',
      );

      final row = await db
          .customSelect(
            r'''
SELECT public.inbox_item_inbox_provenance_data(ii, $1::json) AS data
FROM public.inbox_item ii
WHERE ii.user_id = $2 AND ii.beacon_id = $3
''',
            variables: [
              Variable<String>(
                jsonEncode({'x-hasura-user-id': _recipientId}),
              ),
              Variable<String>(_recipientId),
              Variable<String>(_beaconId),
            ],
          )
          .getSingle();

      final parsed =
          jsonDecode(row.read<String>('data')) as Map<String, dynamic>;
      expect(parsed['totalDistinctSenders'], 1);
      final senders = parsed['senders'] as List<dynamic>;
      expect(senders, hasLength(1));
      expect(senders.single['id'], _senderId);
    },
    skip: provenanceSkipReason,
  );

  test(
    'inbox provenance excludes self-forward and counts invite-forward edges',
    () async {
      await seedUsers();
      await seedBeacon();

      await db.customStatement(
        r'''
INSERT INTO public.inbox_item (
  user_id, beacon_id, context, status, forward_count, latest_forward_at, latest_note_preview, rejection_message
) VALUES ($1, $2, 'coordination', 0, 1, '2026-01-01T00:00:00Z', '', '')
ON CONFLICT (user_id, beacon_id) DO UPDATE SET context = EXCLUDED.context
''',
        [_recipientId, _beaconId],
      );

      await db.customStatement(
        r'''
INSERT INTO public.beacon_forward_edge (
  id, beacon_id, sender_id, recipient_id, note, context, created_at
) VALUES
  ('Finboxtest03', $1, $2, $3, 'invite path', NULL, '2026-01-01T00:00:00Z'),
  ('Finboxtest04', $1, $3, $3, 'self loop', 'coordination', '2026-01-02T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''',
        [_beaconId, _senderId, _recipientId],
      );

      final row = await db
          .customSelect(
            r'''
SELECT public.inbox_item_inbox_provenance_data(ii, $1::json) AS data
FROM public.inbox_item ii
WHERE ii.user_id = $2 AND ii.beacon_id = $3
''',
            variables: [
              Variable<String>(
                jsonEncode({'x-hasura-user-id': _recipientId}),
              ),
              Variable<String>(_recipientId),
              Variable<String>(_beaconId),
            ],
          )
          .getSingle();

      final parsed =
          jsonDecode(row.read<String>('data')) as Map<String, dynamic>;
      expect(parsed['totalDistinctSenders'], 1);
      final senders = parsed['senders'] as List<dynamic>;
      expect(senders, hasLength(1));
      expect(senders.single['id'], _senderId);
    },
    skip: provenanceSkipReason,
  );

  test(
    'the Inbox delegate keeps its blocked-sender behaviour (issue #188)',
    () async {
      // U15R-b shares one body between the Inbox computed field and the
      // attention read path, so this case is the guard on the *one* place
      // they legitimately differ: the delegate passes `p_exclude_blocked =
      // false`, and whether that is right is issue #188 — a product decision,
      // not a thing to settle under cover of a contract extension. If a later
      // change quietly turns the wall on here, the Inbox starts hiding
      // forwarders it has always shown, and this goes red.
      await seedUsers();
      await seedBeacon();

      await db.customStatement(
        r'''
INSERT INTO public.inbox_item (
  user_id, beacon_id, status, forward_count, latest_forward_at, latest_note_preview, rejection_message
) VALUES ($1, $2, 0, 2, '2026-01-02T00:00:00Z', '', '')
ON CONFLICT (user_id, beacon_id) DO NOTHING
''',
        [_recipientId, _beaconId],
      );
      await db.customStatement(
        r'''
INSERT INTO public.beacon_forward_edge (
  id, beacon_id, sender_id, recipient_id, note, created_at
) VALUES
  ('Finboxtest05', $1, $2, $3, 'visible note', '2026-01-01T00:00:00Z'),
  ('Finboxtest06', $1, $4, $3, 'blocked note', '2026-01-02T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''',
        [_beaconId, _senderId, _recipientId, _sender2Id],
      );
      await db.customStatement(
        r'''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES ($1, $2, $2)
ON CONFLICT DO NOTHING
''',
        [_recipientId, _sender2Id],
      );

      final row = await db
          .customSelect(
            r'''
SELECT public.inbox_item_inbox_provenance_data(ii, $1::json) AS data
FROM public.inbox_item ii
WHERE ii.user_id = $2 AND ii.beacon_id = $3
''',
            variables: [
              Variable<String>(
                jsonEncode({'x-hasura-user-id': _recipientId}),
              ),
              Variable<String>(_recipientId),
              Variable<String>(_beaconId),
            ],
          )
          .getSingle();

      final parsed =
          jsonDecode(row.read<String>('data')) as Map<String, dynamic>;
      expect(
        parsed['totalDistinctSenders'],
        2,
        reason: 'the Inbox has never applied the block filter here',
      );
      expect(
        (parsed['senders'] as List<dynamic>).map((e) => e['id']),
        containsAll([_senderId, _sender2Id]),
      );
      expect(
        (parsed['latestNoteForward'] as Map<String, dynamic>)['senderId'],
        _sender2Id,
        reason:
            'the new field reads from the same filtered edges as the list, '
            'so it shows exactly what this caller already shows — no more, '
            'and no less',
      );
    },
    skip: latestNoteSkipReason,
  );
}

Env _testEnv() => Env(
  environment: Environment.test,
  pgHost: Platform.environment['POSTGRES_HOST'] ?? '127.0.0.1',
  pgPort: int.tryParse(Platform.environment['POSTGRES_PORT'] ?? '') ?? 5432,
  pgPassword: Platform.environment['POSTGRES_PASSWORD'] ?? 'password',
  printEnv: false,
  isDebugModeOn: false,
);

Future<bool> _hasInboxSchema(TenturaDb db) async {
  final statusCol = await db.customSelect(
    '''
SELECT 1 FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'inbox_item'
  AND column_name = 'status'
LIMIT 1
''',
  ).get();
  if (statusCol.isEmpty) return false;

  final tombstoneFn = await db.customSelect(
    '''
SELECT 1 FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'inbox_item_apply_tombstone_after_withdraw'
LIMIT 1
''',
  ).get();
  if (tombstoneFn.isEmpty) return false;

  final provenanceFn = await db.customSelect(
    '''
SELECT 1 FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'inbox_item_inbox_provenance_data'
LIMIT 1
''',
  ).get();
  return provenanceFn.isNotEmpty;
}

Future<bool> _hasM0102TombstoneFunction(TenturaDb db) async {
  final row = await db.customSelect(
    r'''
SELECT pg_get_functiondef(p.oid) AS def
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'inbox_item_apply_tombstone_after_withdraw'
LIMIT 1
''',
  ).getSingleOrNull();
  final def = row?.read<String>('def') ?? '';
  return def.contains('b.status') && !def.contains('b.state');
}

Future<bool> _hasM0100Provenance(TenturaDb db) async {
  final index = await db.customSelect(
    '''
SELECT 1 FROM pg_indexes
WHERE schemaname = 'public' AND indexname = 'bfe_active_unique'
LIMIT 1
''',
  ).get();
  if (index.isEmpty) return false;

  final def = await _provenanceImplSource(db);
  return def.contains('cancelled_at IS NULL');
}

/// U15R-b — the delegate reaches the m0190 body (`latestNoteForward`).
Future<bool> _hasM0190LatestNoteForward(TenturaDb db) async {
  final def = await _provenanceImplSource(db);
  return def.contains('latestNoteForward');
}

Future<bool> _hasM0103Provenance(TenturaDb db) async {
  final def = await _provenanceImplSource(db);
  // Self-forward exclusion: m0103 spelled the recipient `inbox_row.user_id`;
  // after m0188 moved the body behind `attention_provenance_data` it is the
  // `p_recipient_id` argument. Match the predicate, not one spelling of it.
  final excludesSelfForward = RegExp(
    r'bfe\.sender_id\s*<>\s*[A-Za-z_][\w.]*',
  ).hasMatch(def);
  return excludesSelfForward &&
      def.contains("nullif(trim(bfe.context), '') IS NULL");
}

/// Source of the provenance implementation **as actually reached at runtime**.
///
/// `inbox_item_inbox_provenance_data` is the Hasura computed field, but since
/// m0188 (U10d) its body is a one-line delegation to the shared
/// `attention_provenance_data`. Grepping the computed field's own definition
/// therefore finds none of the predicates that define m0100/m0103 semantics,
/// which is exactly how these probes silently went false and skipped the two
/// live provenance cases. Follow the delegation: concatenate the entry point's
/// definition with those of every `public.` function it transitively calls, so
/// the probes see the SQL that really runs no matter how many hops it is moved
/// behind.
Future<String> _provenanceImplSource(TenturaDb db) async {
  final seen = <String>{};
  final buffer = StringBuffer();
  final pending = <String>['inbox_item_inbox_provenance_data'];

  while (pending.isNotEmpty) {
    final name = pending.removeLast();
    if (!seen.add(name)) continue;

    final rows = await db
        .customSelect(
          r'''
SELECT pg_get_functiondef(p.oid) AS def
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = $1
''',
          variables: [Variable<String>(name)],
        )
        .get();

    for (final row in rows) {
      final def = row.read<String>('def');
      buffer.writeln(def);
      for (final m in RegExp(r'public\.([a-z_][a-z0-9_]*)\s*\(').allMatches(
        def,
      )) {
        final callee = m.group(1)!;
        if (!seen.contains(callee)) pending.add(callee);
      }
    }
  }

  return buffer.toString();
}

Future<bool> _canConnectPostgres() async {
  try {
    final db = TenturaDb(_testEnv());
    await db.customSelect('SELECT 1').getSingle();
    await db.close();
    return true;
  } on Object catch (_) {
    return false;
  }
}
