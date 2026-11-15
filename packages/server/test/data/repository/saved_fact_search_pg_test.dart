@Tags(['pg'])
library;

import 'package:drift_postgres/drift_postgres.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts/beacon_fact_card_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/saved_fact_repository.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

/// `SavedFactRepository.search`: the facts a user may pick, found by words.
/// Candidates are facts of beacons the user authors, stewards or joined
/// (`room_access <> 5`) plus the user's saved facts; each row passes the same
/// read rule as the saved list (removed never, draft author-only,
/// request-visible needs can_read, discussion-only needs can_use_room).
/// Words arrive already folded (lower case, ё→е); the fact text is folded
/// here. Server only: input devices, locale and viewport are n/a.

const _author = 'Ufsearchauth';
const _member = 'Ufsearchmemb'; // admitted in R, P, the other draft
const _steward = 'Ufsearchstew'; // steward of R, no participant row
const _requested = 'Ufsearchreqd'; // room_access 1 in R, forwarded R
const _stranger = 'Ufsearchstrg'; // forwarded R, no membership
const _leftOnly = 'Ufsearchleft'; // room_access 5 in R, nothing saved
const _leaver = 'Ufsearchleav'; // left R2, saved two of its facts
const _blocked = 'Ufsearchblkd'; // admitted in RB, later blocked
const _blocker = 'Ufsearchblkr'; // admitted in RB, later blocks the author
const _saver = 'Ufsearchsavr'; // admitted in RO, saved two of its facts

const _r = 'Bfsearch000R'; // published Request
const _r2 = 'Bfsearch00R2'; // published Request the leaver left
const _rb = 'Bfsearch00RB'; // published Request of the block pair
const _ro = 'Bfsearch00RO'; // published Request for ordering
const _p = 'Bfsearch000P'; // published Post
const _otherDraft = 'Bfsearch00DO'; // the author's draft Request
const _ownDraft = 'Bfsearch00DM'; // the member's own draft Request

const _postRoot = 'Mfsearchroot';

// Facts of R.
const _fMango = 'Ffsearch0001';
const _fMangoRoom = 'Ffsearch0002';
const _fMangoRemoved = 'Ffsearch0003';
const _fKiwiR = 'Ffsearch0004';
const _fGuava = 'Ffsearch0005'; // saved by the member
const _fCherry = 'Ffsearch0006'; // saved by the member
const _fPlum = 'Ffsearch0007';
const _fEdited = 'Ffsearch0008';
const _fYo = 'Ffsearch0009';
const _fPercent = 'Ffsearch0010';
const _fNoPercent = 'Ffsearch0011';
const _fUnderscore = 'Ffsearch0012';
const _fNoUnderscore = 'Ffsearch0013';
const _fSalad = 'Ffsearch0014';
const _fSoup = 'Ffsearch0015';
const _fMilk = 'Ffsearch0016';
// Fact of P.
const _fKiwiP = 'Ffsearch0020';
// Facts of the drafts.
const _fOtherDraft = 'Ffsearch0030';
const _fOwnDraft = 'Ffsearch0031';
// Facts of R2.
const _fQuince = 'Ffsearch0040';
const _fQuinceRoom = 'Ffsearch0041';
// Facts of RB.
const _fDurianOne = 'Ffsearch0050';
const _fDurianTwo = 'Ffsearch0051';
// Facts of RO.
const _fFigSavedFirst = 'Ffsearch0060';
const _fFigSavedLater = 'Ffsearch0061';
const _fFigNewest = 'Ffsearch0062';
const _fFigTieB = 'Ffsearch0064';
const _fFigTieA = 'Ffsearch0063';

final _t0 = DateTime.utc(2026, 11, 1, 12);

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_SAVED_FACT_SEARCH_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_saved_fact_search',
  );
  final skip = await pgSkipReason(target);
  if (skip != null) {
    test('saved fact search tests require reachable Postgres', () {
      fail(skip);
    });
    return;
  }

  late DisposablePgWriterSession session;
  late TenturaDb db;
  late SavedFactRepository repository;

  setUpAll(() async {
    session = await setUpDisposablePgWriter(target: target);
    await _seed(session.writer);
    db = TenturaDb.forTest(
      database: PgDatabase.opened(
        Pool<dynamic>.withEndpoints(
          [target.databaseEnv.pgEndpoint],
          settings: target.databaseEnv.pgPoolSettings,
        ),
        enableMigrations: false,
      ),
    );
    repository = SavedFactRepository(db);
  });
  tearDownAll(() => tearDownDisposablePgWriter(session: session, drift: db));

  Future<List<Map<String, Object?>>> search(
    String userId,
    List<String> words, {
    String? excludeBeaconId,
    int limit = kMaxFactSearchResults,
  }) async {
    final rows = await repository.search(
      userId: userId,
      words: words,
      excludeBeaconId: excludeBeaconId,
      limit: limit,
    );
    // Every row of every search: exactly these six keys, none null.
    for (final row in rows) {
      expect(row.keys.toSet(), {
        'factCardId',
        'beaconId',
        'beaconKind',
        'factText',
        'attachmentsJson',
        'saved',
      }, reason: '$row');
      expect(row.values, everyElement(isNotNull), reason: '$row');
    }
    return rows;
  }

  List<Object?> ids(List<Map<String, Object?>> rows) => [
    for (final r in rows) r['factCardId'],
  ];

  test('kMaxFactSearchResults is 30', () {
    expect(kMaxFactSearchResults, 30);
  });

  group('who finds the facts of a Request', () {
    test('an admitted member finds request-visible and discussion-only '
        'facts, never removed ones', () async {
      expect(
        (await search(_member, ['mango'])).map((r) => r['factCardId']).toSet(),
        {_fMango, _fMangoRoom},
      );
    });

    test('the author without a participant row finds the facts', () async {
      expect(
        (await search(_author, ['mango'])).map((r) => r['factCardId']).toSet(),
        {_fMango, _fMangoRoom},
      );
    });

    // A steward is a room member in `beacon_fact_access` (m0311:
    // `is_room_member` checks `beacon_steward`, so can_use_room is true), so
    // the discussion-only fact is theirs too; the removed one never is.
    test('a steward who is not the author and has no participant row finds '
        'the request-visible and discussion-only facts only', () async {
      final rows = await search(_steward, ['mango']);
      expect(rows.map((r) => r['factCardId']).toSet(), {_fMango, _fMangoRoom});
      expect(rows, hasLength(2));
    });

    test('a requested participant finds request-visible facts only', () async {
      expect(ids(await search(_requested, ['mango'])), [_fMango]);
    });

    test('a user who can read the Request but has no membership and no saved '
        'fact finds nothing', () async {
      expect(await search(_stranger, ['mango']), isEmpty);
    });

    test('a user who left the Request and saved none of its facts finds '
        'nothing', () async {
      expect(await search(_leftOnly, ['mango']), isEmpty);
    });

    // Each block test starts and ends without a block row between its two
    // users, so it holds in any order and on a re-run.
    Future<void> clearBlocks(String member) => session.writer.execute(
      Sql.named(
        'DELETE FROM public.user_block '
        'WHERE (blocker_id = @a AND blocked_id = @m) '
        'OR (blocker_id = @m AND blocked_id = @a)',
      ),
      parameters: {'a': _author, 'm': member},
    );

    Future<void> expectBlockHides({
      required String member,
      required String blocker,
      required String blockedUser,
    }) async {
      await clearBlocks(member);
      try {
        expect(
          (await search(member, [
            'durian',
          ])).map((r) => r['factCardId']).toSet(),
          {_fDurianOne, _fDurianTwo},
          reason: 'without a block the member finds both facts',
        );
        await session.writer.execute(
          Sql.named(
            'INSERT INTO public.user_block (blocker_id, blocked_id, origin_id) '
            'VALUES (@a, @b, @a)',
          ),
          parameters: {'a': blocker, 'b': blockedUser},
        );
        expect(await search(member, ['durian']), isEmpty);
      } finally {
        await clearBlocks(member);
      }
    }

    test('the author blocking a member hides every fact of that '
        'Request from the member, saved ones included', () async {
      await expectBlockHides(
        member: _blocked,
        blocker: _author,
        blockedUser: _blocked,
      );
    });

    test('a member blocking the author hides every fact of that Request, '
        'saved ones included', () async {
      await expectBlockHides(
        member: _blocker,
        blocker: _blocker,
        blockedUser: _author,
      );
    });
  });

  group('drafts', () {
    test("another user's draft facts are absent and the user's own draft "
        'facts are present', () async {
      expect(ids(await search(_member, ['papaya'])), [_fOwnDraft]);
    });
  });

  group('saved facts', () {
    test('a saved fact of a left Request is returned when request-visible '
        'and absent when discussion-only', () async {
      final rows = await search(_leaver, ['quince']);
      expect(rows, [
        {
          'factCardId': _fQuince,
          'beaconId': _r2,
          'beaconKind': 0,
          'factText': 'quince request visible',
          'attachmentsJson': '[]',
          'saved': true,
        },
      ]);
      expect(ids(rows), isNot(contains(_fQuinceRoom)));
      // Words that only the saved discussion-only fact holds find nothing.
      expect(await search(_leaver, ['quince', 'discussion']), isEmpty);
    });

    test('a saved fact of a beacon the user also belongs to appears once, '
        'marked saved', () async {
      final rows = await search(_member, ['guava']);
      expect(rows, [
        {
          'factCardId': _fGuava,
          'beaconId': _r,
          'beaconKind': 0,
          'factText': 'guava saved and joined',
          'attachmentsJson': '[]',
          'saved': true,
        },
      ]);
    });

    test('a saved fact whose text lacks the word is not returned, while '
        'the same saved fact is found by its own word', () async {
      // _fCherry ('cherry saved elsewhere') is saved by the member;
      // _fPlum ('plum not saved') is not.
      final plum = ids(await search(_member, ['plum']));
      expect(plum, isNot(contains(_fCherry)));
      expect(plum, [_fPlum]);
      final cherry = await search(_member, ['cherry']);
      expect(ids(cherry), [_fCherry]);
      expect(cherry.single['saved'], isTrue);
    });
  });

  group('row shape', () {
    test('a Request fact row carries exactly the six non-null keys with kind '
        '0, empty attachments and saved false', () async {
      final row = (await search(_requested, ['mango'])).single;
      expect(row, {
        'factCardId': _fMango,
        'beaconId': _r,
        'beaconKind': 0,
        'factText': 'Mango request visible',
        'attachmentsJson': '[]',
        'saved': false,
      });
    });

    test('a Post fact row carries exactly the six non-null keys with kind '
        '1', () async {
      final rows = await search(_member, ['kiwi'], excludeBeaconId: _r);
      expect(rows, [
        {
          'factCardId': _fKiwiP,
          'beaconId': _p,
          'beaconKind': 1,
          'factText': 'kiwi in the post',
          'attachmentsJson': '[]',
          'saved': false,
        },
      ]);
    });

    test('an edited fact is found by its new text only and returns the new '
        'text', () async {
      final rows = await search(_member, ['newword']);
      expect(rows, [
        {
          'factCardId': _fEdited,
          'beaconId': _r,
          'beaconKind': 0,
          'factText': 'newword banana',
          'attachmentsJson': '[]',
          'saved': false,
        },
      ]);
      expect(await search(_member, ['oldword']), isEmpty);
    });
  });

  group('order and limit', () {
    test('saved matches come first, later saved first, then the rest by '
        'updated_at descending and id ascending', () async {
      final rows = await search(_saver, ['fig']);
      expect(ids(rows), [
        _fFigSavedLater,
        _fFigSavedFirst,
        _fFigNewest,
        _fFigTieA,
        _fFigTieB,
      ]);
      expect(
        [for (final r in rows) r['saved']],
        [
          true,
          true,
          false,
          false,
          false,
        ],
      );
    });

    test('the limit caps the rows and keeps a saved match before a newer '
        'unsaved one', () async {
      expect(ids(await search(_saver, ['fig'], limit: 1)), [_fFigSavedLater]);
      expect(ids(await search(_saver, ['fig'], limit: 3)), [
        _fFigSavedLater,
        _fFigSavedFirst,
        _fFigNewest,
      ]);
    });

    test('excludeBeaconId drops the facts of that beacon', () async {
      expect(
        (await search(_member, ['kiwi'])).map((r) => r['factCardId']).toSet(),
        {_fKiwiR, _fKiwiP},
      );
      expect(ids(await search(_member, ['kiwi'], excludeBeaconId: _r)), [
        _fKiwiP,
      ]);
    });
  });

  group('word matching', () {
    test('ё in the fact text matches е in the word', () async {
      expect(ids(await search(_member, ['елка'])), [_fYo]);
    });

    test('case in the fact text is ignored', () async {
      expect(ids(await search(_member, ['молоко'])), [_fMilk]);
    });

    test('% matches only a literal percent', () async {
      expect(ids(await search(_member, ['50%'])), [_fPercent]);
      expect(
        (await search(_member, [
          'discount',
        ])).map((r) => r['factCardId']).toSet(),
        {_fPercent, _fNoPercent},
      );
    });

    test('_ matches only a literal underscore', () async {
      expect(ids(await search(_member, ['qa_bq'])), [_fUnderscore]);
      expect(ids(await search(_member, ['qaxbq'])), [_fNoUnderscore]);
    });

    test('every word must occur in the fact text', () async {
      expect(ids(await search(_member, ['tomato', 'salad'])), [_fSalad]);
      expect(
        (await search(_member, ['tomato'])).map((r) => r['factCardId']).toSet(),
        {_fSalad, _fSoup},
      );
    });
  });
}

Future<void> _seed(Connection w) async {
  Future<void> run(String sql, [Map<String, Object?>? p]) async {
    await w.execute(Sql.named(sql), parameters: p ?? {});
  }

  for (final (i, u) in [
    _author,
    _member,
    _steward,
    _requested,
    _stranger,
    _leftOnly,
    _leaver,
    _blocked,
    _saver,
    _blocker,
  ].indexed) {
    await run(
      'INSERT INTO public."user" (id, display_name, public_key) '
      'VALUES (@id, @n, @k)',
      {
        'id': u,
        'n': 'User$i',
        // Slots stop at 9: the tenth user takes a key from another namespace.
        'k': i < 9
            ? pgTestPublicKey('fsearch', i + 1)
            : pgTestPublicKey('blocker', 1),
      },
    );
  }

  // (id, author, kind, status, published)
  for (final (id, owner, kind, status, published) in [
    (_r, _author, 0, 0, true),
    (_r2, _author, 0, 0, true),
    (_rb, _author, 0, 0, true),
    (_ro, _author, 0, 0, true),
    (_p, _author, 1, 0, true),
    (_otherDraft, _author, 0, 3, false),
    (_ownDraft, _member, 0, 3, false),
  ]) {
    await run(
      '''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, published_at,
   is_discoverable, expires_at)
VALUES (@id, @o, @title, @desc, @status::smallint, @kind::smallint,
        CASE WHEN @pub::boolean THEN @t0::timestamptz END, @disc,
        CASE WHEN @kind::smallint = 1 THEN now() + interval '2 days' END)
''',
      {
        'id': id,
        'o': owner,
        'kind': kind,
        'status': status,
        'pub': published,
        't0': _t0,
        // A Post has an empty title and description and is not discoverable.
        'title': kind == 1 ? '' : id,
        'desc': kind == 1 ? '' : 'd',
        'disc': kind == 0,
      },
    );
  }
  // A published Post has a root message; without one it is a draft.
  await run(
    'INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body) '
    "VALUES (@m, @p, @o, 'Root')",
    {'m': _postRoot, 'p': _p, 'o': _author},
  );
  await run(
    'UPDATE public.beacon SET post_root_message_id = @m WHERE id = @p',
    {'m': _postRoot, 'p': _p},
  );

  await run(
    'INSERT INTO public.beacon_steward (beacon_id, user_id) VALUES (@b, @u)',
    {'b': _r, 'u': _steward},
  );

  var p = 0;
  for (final (beaconId, userId, roomAccess) in [
    (_r, _member, 3),
    (_p, _member, 3),
    (_otherDraft, _member, 3),
    (_r, _requested, 1),
    (_r, _leftOnly, 5),
    (_r2, _leaver, 5),
    (_rb, _blocked, 3),
    (_rb, _blocker, 3),
    (_ro, _saver, 3),
  ]) {
    await run(
      '''
INSERT INTO public.beacon_participant
  (id, beacon_id, user_id, role, status, room_access)
VALUES (@id, @b, @u, 0, 0, @ra)
''',
      {'id': 'Pfsearch${p++}', 'b': beaconId, 'u': userId, 'ra': roomAccess},
    );
  }

  // Forwards let these users read the Request without being members.
  for (final (beaconId, userId) in [
    (_r, _requested),
    (_r, _stranger),
    (_r2, _leaver),
  ]) {
    await run(
      'INSERT INTO public.beacon_forward_edge '
      '(beacon_id, sender_id, recipient_id) VALUES (@b, @o, @r)',
      {'b': beaconId, 'o': _author, 'r': userId},
    );
  }

  Future<void> fact(
    String id,
    String beaconId,
    String text, {
    int status = BeaconFactCardStatusBits.active,
    int visibility = BeaconFactCardVisibilityBits.public,
    DateTime? updatedAt,
    String pinnedBy = _author,
  }) async {
    await run(
      '''
INSERT INTO public.beacon_fact_card
  (id, beacon_id, fact_text, visibility, pinned_by, status, created_at,
   updated_at, revision_seq)
VALUES (@id, @b, @text, @vis, @o, @status, @t0, @upd, 1)
''',
      {
        'id': id,
        'b': beaconId,
        'text': text,
        'vis': visibility,
        'o': pinnedBy,
        'status': status,
        't0': _t0,
        'upd': updatedAt ?? _t0,
      },
    );
    await run(
      '''
INSERT INTO public.beacon_fact_card_revision
  (fact_card_id, seq, fact_text, actor_id, kind, created_at, attachments_json)
VALUES (@id, 1, @text, @o, @kind, @t0, '[]'::jsonb)
''',
      {
        'id': id,
        'text': text,
        'o': pinnedBy,
        'kind': BeaconFactCardRevisionKindBits.created,
        't0': _t0,
      },
    );
  }

  const room = BeaconFactCardVisibilityBits.room;
  const removed = BeaconFactCardStatusBits.removed;

  await fact(_fMango, _r, 'Mango request visible');
  await fact(_fMangoRoom, _r, 'mango discussion only', visibility: room);
  await fact(_fMangoRemoved, _r, 'mango removed', status: removed);
  await fact(_fKiwiR, _r, 'kiwi in the request');
  await fact(_fGuava, _r, 'guava saved and joined');
  await fact(_fCherry, _r, 'cherry saved elsewhere');
  await fact(_fPlum, _r, 'plum not saved');
  await fact(_fEdited, _r, 'oldword banana');
  await fact(_fYo, _r, 'Ёлка зелёная');
  await fact(_fPercent, _r, 'discount 50% now');
  await fact(_fNoPercent, _r, 'discount 500 now');
  await fact(_fUnderscore, _r, 'code qa_bq here');
  await fact(_fNoUnderscore, _r, 'code qaxbq here');
  await fact(_fSalad, _r, 'tomato salad');
  await fact(_fSoup, _r, 'tomato soup');
  await fact(_fMilk, _r, 'Молоко свежее');

  await fact(_fKiwiP, _p, 'kiwi in the post');

  await fact(_fOtherDraft, _otherDraft, 'papaya in their draft');
  await fact(_fOwnDraft, _ownDraft, 'papaya in my draft', pinnedBy: _member);

  await fact(_fQuince, _r2, 'quince request visible');
  await fact(_fQuinceRoom, _r2, 'quince discussion only', visibility: room);

  await fact(_fDurianOne, _rb, 'durian one');
  await fact(_fDurianTwo, _rb, 'durian two');

  // Saved ones are the oldest by updated_at, so saved-first is not an
  // accident of recency.
  await fact(_fFigSavedFirst, _ro, 'fig saved first');
  await fact(_fFigSavedLater, _ro, 'fig saved later');
  await fact(
    _fFigNewest,
    _ro,
    'fig newest',
    updatedAt: _t0.add(const Duration(minutes: 10)),
  );
  // Inserted B before A so id order is not insertion order.
  await fact(
    _fFigTieB,
    _ro,
    'fig tie b',
    updatedAt: _t0.add(const Duration(minutes: 5)),
  );
  await fact(
    _fFigTieA,
    _ro,
    'fig tie a',
    updatedAt: _t0.add(const Duration(minutes: 5)),
  );

  // The edit: revision 2 holds the new head text.
  await run(
    "UPDATE public.beacon_fact_card SET fact_text = 'newword banana', "
    'revision_seq = 2 WHERE id = @f',
    {'f': _fEdited},
  );
  await run(
    '''
INSERT INTO public.beacon_fact_card_revision
  (fact_card_id, seq, fact_text, actor_id, kind, created_at, attachments_json)
VALUES (@f, 2, 'newword banana', @o, @kind, @t, '[]'::jsonb)
''',
    {
      'f': _fEdited,
      'o': _author,
      'kind': BeaconFactCardRevisionKindBits.edited,
      't': _t0.add(const Duration(minutes: 1)),
    },
  );

  for (final (user, factId, minutes) in [
    (_member, _fGuava, 0),
    (_member, _fCherry, 1),
    (_leaver, _fQuince, 0),
    (_leaver, _fQuinceRoom, 1),
    (_blocked, _fDurianTwo, 0),
    (_blocker, _fDurianOne, 0),
    (_saver, _fFigSavedFirst, 0),
    (_saver, _fFigSavedLater, 1),
  ]) {
    await run(
      'INSERT INTO public.user_saved_fact (user_id, fact_card_id, created_at) '
      'VALUES (@u, @f, @t)',
      {'u': user, 'f': factId, 't': _t0.add(Duration(minutes: minutes))},
    );
  }
}
