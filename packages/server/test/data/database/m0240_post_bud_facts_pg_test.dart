@Tags(['pg'])
library;

import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/person_visibility_repository.dart';
import 'package:tentura_server/data/repository/post_bud_repository.dart';
import 'package:tentura_server/domain/entity/post_bud_invite_candidate.dart';
import 'package:tentura_server/domain/port/person_visibility_repository_port.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

/// m0240 (budding B2): the effective Post member set `E(P)`, the per-member
/// invite facts and the pretick set (Arch §2.1, §3.3), plus
/// `PostBudPort.inviteCandidates`, which adds the cold-member visibility gate.
///
/// Members of the Post `_post` (author `_author`), seen by the budder `_budder`:
/// - `_warm`: first responder and writer, arrived from the author;
/// - `_cold`: arrived from the budder, reciprocal explicit trust with them;
/// - `_stranger`: cold, no relation to the budder; arrived from the author,
///   then (later) from `_warm`;
/// - `_blockedAuthor`: blocked by the Post author (not a member);
/// - `_blockedBudder`: blocks the budder (member, `blocked`);
/// - `_cancelled`: their only edge was cancelled (access 0, not a member);
/// - `_left`: left the Post (access 5, not a member);
/// - `_paused`: availability-paused (`recipientPaused`);
/// - `_invited`: holds a pending invite from the budder for this Post;
/// - `_outsider`: never in the Post, only @mentioned.
const _author = 'Um0239author01';
const _budder = 'Um0239budder01';
const _warm = 'Um0239warm0001';
const _cold = 'Um0239cold0001';
const _stranger = 'Um0239strange1';
const _blockedAuthor = 'Um0239blkauth1';
const _blockedBudder = 'Um0239blkbudd1';
const _cancelled = 'Um0239cancel01';
const _left = 'Um0239left0001';
const _paused = 'Um0239paused01';
const _invited = 'Um0239invited1';
const _outsider = 'Um0239outside1';

const _users = [
  _author,
  _budder,
  _warm,
  _cold,
  _stranger,
  _blockedAuthor,
  _blockedBudder,
  _cancelled,
  _left,
  _paused,
  _invited,
  _outsider,
];

const _post = 'Bm0239post0001';
const _child = 'Bm0239child001';

Future<void> main() async {
  final migrationTarget = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_M0240_POST_BUD_FACTS_MIGRATION_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_m0240_bud_mig',
  );
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_M0240_POST_BUD_FACTS_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_m0240_bud',
  );
  final pgSkip =
      await pgSkipReason(migrationTarget) ?? await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  group('upgrade from the previous schema version', () {
    late DisposablePgWriterSession session;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(
        target: migrationTarget,
        lastInclusiveVersion: '0239',
      );
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session);
    });

    test('the functions work on rows written before the migration', () async {
      final writer = session.writer;
      await _seed(writer);

      await migrateDbSchema(writer);

      expect(await _members(writer), _expectedMembers);
      expect(await _pretick(writer), {_cold, _warm, _outsider});
      expect(
        (await _facts(writer)).keys.toSet(),
        {
          ..._expectedMembers,
        }..remove(_budder),
      );
    });
  });

  group('full schema', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb database;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      database = openDisposablePgDatabase(target);
    });

    setUp(() async {
      await _seed(writer);
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session, drift: database);
    });

    group('post_effective_members', () {
      test('author plus admitted members, minus author blocks', () async {
        expect(await _members(writer), _expectedMembers);
      });

      test('the author is included without a participant row', () async {
        final rows = await writer.execute(
          'SELECT count(*)::int FROM public.beacon_participant '
          "WHERE beacon_id = '$_post' AND user_id = '$_author'",
        );
        expect(rows.single.single, 0);
        expect(await _members(writer), contains(_author));
      });

      test('a member blocked with the Post author is excluded', () async {
        expect(await _members(writer), isNot(contains(_blockedAuthor)));
        // Still holds an admitted participant row: the block alone excludes.
        final rows = await writer.execute(
          'SELECT room_access FROM public.beacon_participant '
          "WHERE beacon_id = '$_post' AND user_id = '$_blockedAuthor'",
        );
        expect(rows.single.single, 3);
      });

      test('cancelled (access 0) and left (access 5) are excluded', () async {
        final members = await _members(writer);
        expect(members, isNot(contains(_cancelled)));
        expect(members, isNot(contains(_left)));
        final rows = await writer.execute(
          'SELECT user_id, room_access FROM public.beacon_participant '
          "WHERE beacon_id = '$_post' "
          "AND user_id IN ('$_cancelled', '$_left') ORDER BY user_id",
        );
        expect(
          {for (final r in rows) r[0]: r[1]},
          {_cancelled: 0, _left: 5},
        );
      });

      test('a Request has no effective Post members', () async {
        final rows = await writer.execute(
          "SELECT user_id FROM public.post_effective_members('$_child')",
        );
        expect(rows, isEmpty);
      });
    });

    group('post_bud_invite_facts', () {
      test('covers E(P) without the budder', () async {
        final facts = await _facts(writer);
        expect(facts.keys.toSet(), {..._expectedMembers}..remove(_budder));
      });

      test('warm: first responders and the Post author', () async {
        final facts = await _facts(writer);
        expect(
          {
            for (final e in facts.entries)
              if (e.value.warm) e.key,
          },
          {_author, _warm},
        );
      });

      test('reasons: blocked with the budder, paused, already invited', () {
        return _facts(writer).then((facts) {
          expect(
            {for (final e in facts.entries) e.key: e.value.reason},
            {
              _author: 0,
              _warm: 0,
              _cold: 0,
              _stranger: 0,
              _blockedBudder: 2,
              _paused: 4,
              _invited: 5,
            },
          );
        });
      });

      test(
        'a resolved invite and an expired pause leave the slot free',
        () async {
          await writer.execute(
            'UPDATE public.beacon_author_invite SET status = 2 '
            "WHERE invitee_id = '$_invited'",
          );
          await writer.execute(
            'UPDATE public.user_availability '
            "SET resume_on = public.utc_today() WHERE user_id = '$_paused'",
          );
          final facts = await _facts(writer);
          expect(facts[_invited]!.reason, 0);
          expect(facts[_paused]!.reason, 0);
        },
      );

      test('has_written ignores system messages', () async {
        final facts = await _facts(writer);
        expect(
          {
            for (final e in facts.entries)
              if (e.value.hasWritten) e.key,
          },
          {_warm, _stranger},
        );
      });

      test('via: sender of the latest active inbound edge', () async {
        final facts = await _facts(writer);
        expect(facts[_author]!.via, isNull);
        expect(facts[_warm]!.via, _author);
        // The later edge from _warm was cancelled.
        expect(facts[_cold]!.via, _budder);
        // The later edge from _warm is active.
        expect(facts[_stranger]!.via, _warm);
      });
    });

    group('post_bud_pretick', () {
      test('budder mentions plus replies to budder messages', () async {
        expect(await _pretick(writer), {_cold, _warm, _outsider});
      });

      test(
        'is empty for a member who neither mentioned nor got replies',
        () async {
          final rows = await writer.execute(
            "SELECT user_id FROM public.post_bud_pretick('$_post', '$_paused')",
          );
          expect(rows, isEmpty);
        },
      );
    });

    group('PostBudRepository', () {
      test('effectiveMemberIds mirrors post_effective_members', () async {
        final repository = PostBudRepository(
          database,
          PersonVisibilityRepository(database),
        );
        expect(
          (await repository.effectiveMemberIds(_post)).toSet(),
          _expectedMembers,
        );
      });

      test('inviteCandidates applies the cold visibility gate', () async {
        final repository = PostBudRepository(
          database,
          PersonVisibilityRepository(database),
        );
        final candidates = await repository.inviteCandidates(
          postId: _post,
          budderId: _budder,
        );
        final byId = {for (final c in candidates) c.userId: c};
        expect(
          {for (final e in byId.entries) e.key: e.value.reason},
          {
            _author: PostBudInviteReason.eligible,
            _warm: PostBudInviteReason.eligible,
            // Cold, reciprocal explicit trust with the budder.
            _cold: PostBudInviteReason.eligible,
            // Cold, no relation with the budder.
            _stranger: PostBudInviteReason.notVisible,
            _blockedBudder: PostBudInviteReason.blocked,
            _paused: PostBudInviteReason.recipientPaused,
            _invited: PostBudInviteReason.alreadyInvited,
          },
        );
        expect(
          {
            for (final c in candidates)
              if (c.isEligible) c.userId,
          },
          {_author, _warm, _cold},
        );
        expect(byId[_warm]!.warm, isTrue);
        expect(byId[_cold]!.warm, isFalse);
        expect(byId[_warm]!.hasWritten, isTrue);
        expect(byId[_stranger]!.viaUserId, _warm);
        expect(
          {
            for (final c in candidates)
              if (c.pretick) c.userId,
          },
          {_cold, _warm},
        );
      });

      test('warm members skip the visibility check', () async {
        final visibility = _RecordingVisibility();
        final repository = PostBudRepository(database, visibility);
        final candidates = await repository.inviteCandidates(
          postId: _post,
          budderId: _budder,
        );
        expect(visibility.viewerId, _budder);
        expect(visibility.peerIds, {_cold, _stranger});
        expect(
          {
            for (final c in candidates)
              if (c.isEligible) c.userId,
          },
          {_author, _warm},
        );
      });
    });
  });
}

const _expectedMembers = {
  _author,
  _budder,
  _warm,
  _cold,
  _stranger,
  _blockedBudder,
  _paused,
  _invited,
};

Future<Set<String>> _members(Connection writer) async {
  final rows = await writer.execute(
    "SELECT user_id FROM public.post_effective_members('$_post')",
  );
  return {for (final r in rows) r.single! as String};
}

Future<Set<String>> _pretick(Connection writer) async {
  final rows = await writer.execute(
    "SELECT user_id FROM public.post_bud_pretick('$_post', '$_budder')",
  );
  return {for (final r in rows) r.single! as String};
}

typedef _Fact = ({bool warm, int reason, bool hasWritten, String? via});

Future<Map<String, _Fact>> _facts(Connection writer) async {
  final rows = await writer.execute(
    'SELECT user_id, warm, reason, has_written, via_user_id '
    "FROM public.post_bud_invite_facts('$_post', '$_budder')",
  );
  return {
    for (final r in rows)
      r[0]! as String: (
        warm: r[1]! as bool,
        reason: r[2]! as int,
        hasWritten: r[3]! as bool,
        via: r[4] as String?,
      ),
  };
}

Future<void> _seed(Connection writer) async {
  await writer.execute('''
TRUNCATE TABLE
  public.beacon_author_invite,
  public.post_first_response,
  public.user_availability,
  public.user_block,
  public.vote_user,
  public.beacon_room_message,
  public.beacon_forward_edge,
  public.beacon_participant,
  public.beacon,
  public."user"
CASCADE
''');
  for (var i = 0; i < _users.length; i++) {
    await writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
      parameters: {
        'id': _users[i],
        // Nine slots per namespace.
        'key': pgTestPublicKey(i < 9 ? 'm0240' : 'n0239', i % 9 + 1),
      },
    );
  }
  await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, forward_policy,
   is_discoverable, published_at)
VALUES ('$_post', '$_author', '', '', 0, 1, 1, false, now())
''');
  await writer.execute('''
INSERT INTO public.beacon (id, user_id, title, description, status, published_at)
VALUES ('$_child', '$_budder', 'Child', '', 0, now())
''');

  // Forward edges admit the recipients (m0210); later edges are younger.
  var minutesAgo = 100;
  Future<void> edge(
    String id,
    String sender,
    String recipient, {
    bool cancel = false,
  }) async {
    await writer.execute('''
INSERT INTO public.beacon_forward_edge
  (id, beacon_id, sender_id, recipient_id, created_at)
VALUES ('$id', '$_post', '$sender', '$recipient',
        now() - interval '${minutesAgo--} minutes')
''');
    if (cancel) {
      await writer.execute(
        'UPDATE public.beacon_forward_edge SET cancelled_at = now() '
        "WHERE id = '$id'",
      );
    }
  }

  await edge('Fm0239e01', _author, _budder);
  await edge('Fm0239e02', _author, _warm);
  await edge('Fm0239e03', _budder, _cold);
  await edge('Fm0239e04', _author, _stranger);
  await edge('Fm0239e05', _author, _blockedAuthor);
  await edge('Fm0239e06', _author, _blockedBudder);
  await edge('Fm0239e07', _author, _cancelled, cancel: true);
  await edge('Fm0239e08', _author, _left);
  await edge('Fm0239e09', _author, _paused);
  await edge('Fm0239e10', _author, _invited);
  await edge('Fm0239e11', _warm, _stranger);
  await edge('Fm0239e12', _warm, _cold, cancel: true);
  await writer.execute(
    'UPDATE public.beacon_participant SET room_access = 5 '
    "WHERE beacon_id = '$_post' AND user_id = '$_left'",
  );

  await writer.execute('''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES ('$_author', '$_blockedAuthor', '$_author'),
       ('$_blockedBudder', '$_budder', '$_blockedBudder')
''');
  await writer.execute('''
INSERT INTO public.vote_user (subject, object, amount)
VALUES ('$_budder', '$_cold', 1), ('$_cold', '$_budder', 1)
''');
  await writer.execute('''
INSERT INTO public.user_availability (user_id, resume_on)
VALUES ('$_paused', public.utc_today() + 3)
''');
  await writer.execute('''
INSERT INTO public.post_first_response (beacon_id, user_id, source_kind, source_id)
VALUES ('$_post', '$_warm', 1, 'Rm0239msg02')
''');
  await writer.execute('''
INSERT INTO public.beacon_author_invite
  (id, beacon_id, inviter_id, invitee_id, source_post_id, warm, status)
VALUES ('BIm0239inv1', '$_child', '$_budder', '$_invited', '$_post', false, 0)
''');

  // Budder mentions _cold, _outsider and themselves; _warm replies to the
  // budder; _stranger writes; _cold only appears on a system notice.
  await writer.execute('''
INSERT INTO public.beacon_room_message
  (id, beacon_id, author_id, body, mentions, reply_to_message_id,
   system_message_kind)
VALUES
  ('Rm0239msg01', '$_post', '$_budder', 'hi',
   ARRAY['$_cold', '$_outsider', '$_budder'], NULL, NULL),
  ('Rm0239msg02', '$_post', '$_warm', 'reply', '{}', 'Rm0239msg01', NULL),
  ('Rm0239msg03', '$_post', '$_stranger', 'hello', '{}', NULL, NULL),
  ('Rm0239msg04', '$_post', '$_cold', '', ARRAY['$_paused'], 'Rm0239msg01', 1)
''');
}

class _RecordingVisibility extends Fake
    implements PersonVisibilityRepositoryPort {
  String? viewerId;
  Set<String>? peerIds;

  @override
  Future<Set<String>> personVisiblePeerIds({
    required String viewerId,
    required Iterable<String> peerIds,
    required String context,
  }) async {
    this.viewerId = viewerId;
    this.peerIds = peerIds.toSet();
    return {};
  }
}
