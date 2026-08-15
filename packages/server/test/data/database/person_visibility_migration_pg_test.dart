@Tags(['pg'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/forward_candidates_sql.dart';
import 'package:tentura_server/env.dart';

typedef _PeerSignals = ({
  bool trustOut,
  bool trustIn,
  bool mrOut,
  bool mrIn,
});

typedef _VisibilityExpectation = ({
  bool visibleOut,
  bool visibleIn,
  bool mutual,
});

/// Live Postgres + MeritRank proof of person visibility functions.
///
/// Incoming-only MeritRank is not a visibility signal here.
/// `mr_mutual_scores(viewer)` is ego-outbound, so a peer with only
/// peer→viewer MR (including mixed explicit trustOut + mrIn) is omitted.
/// We dropped `mr_edgelist` / per-peer `mr_node_score` discovery: first for
/// speed, second for simplicity. Mutual visibility remains explicit
/// `vote_user` and/or a `mr_mutual_scores` row (both directions in that
/// row). Mixed `trustIn + mrOut` is unchanged.
Future<void> main() async {
  final postgresReachable = await _canConnectPostgres();
  var skipReason = postgresReachable ? false : 'local Postgres not reachable';

  if (postgresReachable) {
    final env = _testEnv();
    final connection = await Connection.open(
      env.pgEndpoint,
      settings: env.pgEndpointSettings,
    );
    try {
      final meritRank = await connection.execute(
        Sql(
          "SELECT count(*) > 0 FROM pg_proc WHERE proname = 'mr_mutual_scores'",
        ),
      );
      final hasMr = meritRank.first.first as bool;
      final visibility = await connection.execute(
        Sql('''
SELECT
  (SELECT count(*) FROM pg_proc WHERE proname = 'person_visibility_peers') > 0
  AND (SELECT count(*) FROM pg_proc WHERE proname = 'mutually_visible_users') > 0
  AND (SELECT count(*) FROM pg_proc WHERE proname = 'user_get_trusts_viewer') > 0
'''),
      );
      final hasVisibility = visibility.first.first as bool;
      if (!hasMr) {
        skipReason = 'mr_mutual_scores missing';
      } else if (!hasVisibility) {
        skipReason = 'm0140 person visibility functions missing';
      }
    } finally {
      await connection.close();
    }
  }

  late TenturaDb db;

  const viewerId = 'Upvviewer001';
  const selfPeerId = 'Upvselfpeer1';
  const blockedPeerId = 'Upvblocked01';
  const ctxPeerId = 'Upvctxpeer01';

  final scenarioPeers = List.generate(
    10,
    (i) => 'Upvscen${i.toString().padLeft(2, '0')}peer',
  );
  final allUserIds = [
    viewerId,
    selfPeerId,
    blockedPeerId,
    ctxPeerId,
    ...scenarioPeers,
  ];

  // m0151: incoming-only MR (mrIn without trust or mrOut) omits the row —
  // first for speed, second for simplicity. Mixed trustOut+mrIn is outbound
  // only, not mutual. Mixed trustIn+mrOut stays mutual.
  const truthTable = <_PeerSignals, _VisibilityExpectation>{
    (trustOut: false, trustIn: false, mrOut: false, mrIn: false): (
      visibleOut: false,
      visibleIn: false,
      mutual: false,
    ),
    (trustOut: true, trustIn: false, mrOut: false, mrIn: false): (
      visibleOut: true,
      visibleIn: false,
      mutual: false,
    ),
    (trustOut: false, trustIn: false, mrOut: true, mrIn: false): (
      visibleOut: true,
      visibleIn: false,
      mutual: false,
    ),
    (trustOut: false, trustIn: true, mrOut: false, mrIn: false): (
      visibleOut: false,
      visibleIn: true,
      mutual: false,
    ),
    (trustOut: false, trustIn: false, mrOut: false, mrIn: true): (
      visibleOut: false,
      visibleIn: false,
      mutual: false,
    ),
    (trustOut: true, trustIn: true, mrOut: false, mrIn: false): (
      visibleOut: true,
      visibleIn: true,
      mutual: true,
    ),
    (trustOut: false, trustIn: false, mrOut: true, mrIn: true): (
      visibleOut: true,
      visibleIn: true,
      mutual: true,
    ),
    (trustOut: true, trustIn: false, mrOut: false, mrIn: true): (
      visibleOut: true,
      visibleIn: false,
      mutual: false,
    ),
    (trustOut: false, trustIn: true, mrOut: true, mrIn: false): (
      visibleOut: true,
      visibleIn: true,
      mutual: true,
    ),
    (trustOut: true, trustIn: false, mrOut: true, mrIn: false): (
      visibleOut: true,
      visibleIn: false,
      mutual: false,
    ),
  };

  Future<void> insertUser(String id) => db.customStatement(
    '''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ('$id', '$id', 'pk-$id', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''',
  );

  Future<void> trustEdge(String subject, String object) => db.customStatement(
    '''
INSERT INTO public.vote_user (subject, object, amount, created_at, updated_at)
VALUES ('$subject', '$object', 1, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (subject, object) DO UPDATE SET amount = EXCLUDED.amount
''',
  );

  Future<void> deleteTrust(String subject, String object) => db.customStatement(
    '''
DELETE FROM public.vote_user WHERE subject = '$subject' AND object = '$object'
''',
  );

  Future<void> mrEdge(String subject, String object) => db.customStatement(
    "SELECT mr_put_edge('$subject', '$object', 0.75::double precision, ''::text, 0)",
  );

  Future<void> clearMrEdge(String subject, String object) => db.customStatement(
    "SELECT mr_put_edge('$subject', '$object', 0::double precision, ''::text, 0)",
  );

  Future<void> applySignals(String peerId, _PeerSignals signals) async {
    await deleteTrust(viewerId, peerId);
    await deleteTrust(peerId, viewerId);
    await clearMrEdge(viewerId, peerId);
    await clearMrEdge(peerId, viewerId);
    if (signals.trustOut) {
      await trustEdge(viewerId, peerId);
    }
    if (signals.trustIn) {
      await trustEdge(peerId, viewerId);
    }
    if (signals.mrOut) {
      await mrEdge(viewerId, peerId);
    }
    if (signals.mrIn) {
      await mrEdge(peerId, viewerId);
    }
  }

  Future<Map<String, dynamic>?> peerRow(String peerId, {String? ctx}) async {
    final row = await db
        .customSelect(
          '''
SELECT *
FROM public.person_visibility_peers(\$1, \$2)
WHERE peer_id = \$3
''',
          variables: [
            Variable<String>(viewerId),
            Variable<String>(ctx ?? ''),
            Variable<String>(peerId),
          ],
        )
        .getSingleOrNull();
    return row?.data;
  }

  Future<void> cleanup() async {
    final idList = allUserIds.map((id) => "'$id'").join(', ');
    await db.customStatement(
      'DELETE FROM public.user_block WHERE blocker_id IN ($idList) '
      'OR blocked_id IN ($idList)',
    );
    await db.customStatement(
      'DELETE FROM public.vote_user WHERE subject IN ($idList) OR object IN ($idList)',
    );
    for (final peerId in scenarioPeers) {
      await clearMrEdge(viewerId, peerId);
      await clearMrEdge(peerId, viewerId);
    }
    await clearMrEdge(viewerId, ctxPeerId);
    await clearMrEdge(ctxPeerId, viewerId);
    await clearMrEdge(viewerId, blockedPeerId);
    await clearMrEdge(blockedPeerId, viewerId);
    await db.customStatement(
      '''DELETE FROM public."user" WHERE id IN ($idList)''',
    );
  }

  Future<bool> isMutuallyVisible(String peerId) async {
    final result = await db
        .customSelect(
          r"SELECT public.person_is_mutually_visible($1, $2, '') AS mutual",
          variables: [
            Variable<String>(viewerId),
            Variable<String>(peerId),
          ],
        )
        .getSingle();
    return result.read<bool>('mutual');
  }

  if (skipReason == false) {
    setUp(() async {
      db = TenturaDb(_testEnv());
      await cleanup();
      for (final id in allUserIds) {
        await insertUser(id);
      }
    });

    tearDown(() async {
      await cleanup();
      await db.close();
    });
  }

  test(
    'person_visibility_peers truth table for all four independent signals',
    () async {
      var index = 0;
      for (final entry in truthTable.entries) {
        final peerId = scenarioPeers[index++];
        await applySignals(peerId, entry.key);
        final row = await peerRow(peerId);
        final signals = entry.key;
        final expected = entry.value;
        final rowOmitted =
            !signals.trustOut && !signals.trustIn && !signals.mrOut;
        if (rowOmitted) {
          expect(
            row,
            isNull,
            reason:
                'no outbound trust/MR (incoming-only MR omitted, m0151) '
                'should omit peer row for $peerId',
          );
          expect(
            await isMutuallyVisible(peerId),
            isFalse,
            reason: 'mutual for absent $peerId',
          );
          continue;
        }
        expect(
          row,
          isNotNull,
          reason: 'missing row for $peerId / ${entry.key}',
        );
        expect(
          row!['viewer_can_see_subject'],
          expected.visibleOut,
          reason: 'viewer→ for $peerId',
        );
        expect(
          row['subject_can_see_viewer'],
          expected.visibleIn,
          reason: 'viewer← for $peerId',
        );
        expect(
          row['is_mutually_visible'],
          expected.mutual,
          reason: 'mutual for $peerId',
        );
      }
    },
    skip: skipReason,
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'user_get_trusts_viewer reads only peer→viewer positive trust',
    () async {
      final peerId = scenarioPeers[0];
      await applySignals(
        peerId,
        (trustOut: false, trustIn: true, mrOut: true, mrIn: true),
      );

      final session = _sessionJson(viewerId);
      final trustsViewer = await db
          .customSelect(
            r'''
SELECT public.user_get_trusts_viewer(u, $1::json) AS trusts_viewer
FROM public."user" u
WHERE u.id = $2
''',
            variables: [
              Variable<String>(session),
              Variable<String>(peerId),
            ],
          )
          .getSingle();
      expect(trustsViewer.read<bool>('trusts_viewer'), isTrue);

      await deleteTrust(peerId, viewerId);
      final trustsViewerAfter = await db
          .customSelect(
            r'''
SELECT public.user_get_trusts_viewer(u, $1::json) AS trusts_viewer
FROM public."user" u
WHERE u.id = $2
''',
            variables: [
              Variable<String>(session),
              Variable<String>(peerId),
            ],
          )
          .getSingle();
      expect(trustsViewerAfter.read<bool>('trusts_viewer'), isFalse);
    },
    skip: skipReason,
  );

  test(
    'mutually_visible_users includes explicit, MR, and trustIn+mrOut mixed',
    () async {
      final explicitPeer = scenarioPeers[5];
      final mrPeer = scenarioPeers[6];
      final droppedTrustOutMrInPeer = scenarioPeers[8];
      final keptTrustInMrOutPeer = scenarioPeers[9];
      final oneWayPeer = scenarioPeers[1];

      await applySignals(
        explicitPeer,
        (trustOut: true, trustIn: true, mrOut: false, mrIn: false),
      );
      await applySignals(
        mrPeer,
        (trustOut: false, trustIn: false, mrOut: true, mrIn: true),
      );
      // Dropped in m0151 (speed, then simplicity): not mutual.
      await applySignals(
        droppedTrustOutMrInPeer,
        (trustOut: true, trustIn: false, mrOut: false, mrIn: true),
      );
      await applySignals(
        keptTrustInMrOutPeer,
        (trustOut: false, trustIn: true, mrOut: true, mrIn: false),
      );
      await applySignals(
        oneWayPeer,
        (trustOut: true, trustIn: false, mrOut: false, mrIn: false),
      );

      final session = _sessionJson(viewerId);
      final visibleIds = await db
          .customSelect(
            r'''
SELECT u.id
FROM public.mutually_visible_users('', $1::json) u
ORDER BY u.id
''',
            variables: [Variable<String>(session)],
          )
          .map((row) => row.read<String>('id'))
          .get();

      expect(
        visibleIds,
        containsAll([explicitPeer, mrPeer, keptTrustInMrOutPeer]),
      );
      expect(visibleIds, isNot(contains(droppedTrustOutMrInPeer)));
      expect(visibleIds, isNot(contains(oneWayPeer)));
      expect(visibleIds, isNot(contains(viewerId)));
    },
    skip: skipReason,
  );

  test('mutually_visible_users excludes blocked peers', () async {
    final peerId = scenarioPeers[7];
    await applySignals(
      peerId,
      (trustOut: true, trustIn: true, mrOut: false, mrIn: false),
    );
    await db.customStatement(
      '''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES ('$viewerId', '$peerId', '$peerId')
ON CONFLICT DO NOTHING
''',
    );

    final session = _sessionJson(viewerId);
    final visibleIds = await db
        .customSelect(
          r'''
SELECT u.id
FROM public.mutually_visible_users('', $1::json) u
''',
          variables: [Variable<String>(session)],
        )
        .map((row) => row.read<String>('id'))
        .get();

    expect(visibleIds, isNot(contains(peerId)));
  }, skip: skipReason);

  test('person_is_mutually_visible is false for missing peer row', () async {
    final missingPeer = 'Upvmissing01';
    await insertUser(missingPeer);
    final result = await db
        .customSelect(
          r'''
SELECT public.person_is_mutually_visible($1, $2, '') AS mutual
''',
          variables: [
            Variable<String>(viewerId),
            Variable<String>(missingPeer),
          ],
        )
        .getSingle();
    expect(result.read<bool>('mutual'), isFalse);
    await db.customStatement(
      '''DELETE FROM public."user" WHERE id = '$missingPeer' ''',
    );
  }, skip: skipReason);

  test('blank viewer yields no person_visibility_peers rows', () async {
    final peerId = scenarioPeers[0];
    await applySignals(
      peerId,
      (trustOut: true, trustIn: true, mrOut: false, mrIn: false),
    );
    final rows = await db
        .customSelect(
          r"SELECT * FROM public.person_visibility_peers('', '')",
        )
        .get();
    expect(rows, isEmpty);
  }, skip: skipReason);

  test(
    'context null and empty string normalize the same for candidates',
    () async {
      await applySignals(
        ctxPeerId,
        (trustOut: true, trustIn: true, mrOut: false, mrIn: false),
      );
      final session = _sessionJson(viewerId);
      final emptyCtx = await db
          .customSelect(
            r'''
SELECT u.id
FROM public.mutually_visible_users('', $1::json) u
WHERE u.id = $2
''',
            variables: [
              Variable<String>(session),
              Variable<String>(ctxPeerId),
            ],
          )
          .get();
      final nullCtx = await db
          .customSelect(
            r'''
SELECT u.id
FROM public.mutually_visible_users(NULL, $1::json) u
WHERE u.id = $2
''',
            variables: [
              Variable<String>(session),
              Variable<String>(ctxPeerId),
            ],
          )
          .get();
      expect(emptyCtx.length, 1);
      expect(nullCtx.length, 1);
    },
    skip: skipReason,
  );

  test(
    'forwardCandidates wrap id-set matches mutually_visible_users',
    () async {
      final explicitPeer = scenarioPeers[5];
      final mrPeer = scenarioPeers[6];
      final droppedTrustOutMrInPeer = scenarioPeers[8];
      final keptTrustInMrOutPeer = scenarioPeers[9];
      final oneWayPeer = scenarioPeers[1];
      final blockedPeer = scenarioPeers[7];

      await applySignals(
        explicitPeer,
        (trustOut: true, trustIn: true, mrOut: false, mrIn: false),
      );
      await applySignals(
        mrPeer,
        (trustOut: false, trustIn: false, mrOut: true, mrIn: true),
      );
      await applySignals(
        droppedTrustOutMrInPeer,
        (trustOut: true, trustIn: false, mrOut: false, mrIn: true),
      );
      await applySignals(
        keptTrustInMrOutPeer,
        (trustOut: false, trustIn: true, mrOut: true, mrIn: false),
      );
      await applySignals(
        oneWayPeer,
        (trustOut: true, trustIn: false, mrOut: false, mrIn: false),
      );
      await applySignals(
        blockedPeer,
        (trustOut: true, trustIn: true, mrOut: false, mrIn: false),
      );
      await db.customStatement(
        '''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES ('$viewerId', '$blockedPeer', '$blockedPeer')
ON CONFLICT DO NOTHING
''',
      );

      final wrapIds = await _wrapPeerIds(db, viewerId: viewerId);
      final mvuIds = await _mvuIds(db, viewerId: viewerId);

      expect(wrapIds.toSet(), mvuIds);
      expect(wrapIds, containsAll([explicitPeer, mrPeer, keptTrustInMrOutPeer]));
      expect(wrapIds, isNot(contains(droppedTrustOutMrInPeer)));
      expect(wrapIds, isNot(contains(oneWayPeer)));
      expect(wrapIds, isNot(contains(blockedPeer)));
      expect(wrapIds, isNot(contains(viewerId)));
    },
    skip: skipReason,
  );

  test(
    'forwardCandidates wrap keeps trust-only MR zeros and mixed trustIn+mrOut',
    () async {
      final trustOnly = scenarioPeers[5];
      final mixed = scenarioPeers[9];
      await applySignals(
        trustOnly,
        (trustOut: true, trustIn: true, mrOut: false, mrIn: false),
      );
      await applySignals(
        mixed,
        (trustOut: false, trustIn: true, mrOut: true, mrIn: false),
      );

      final rows = await db
          .customSelect(
            kForwardCandidatesWrapSql,
            variables: [
              Variable<String>(viewerId),
              Variable<String>(''),
            ],
          )
          .get();
      final byId = {
        for (final row in rows) row.read<String>('peer_id'): row,
      };

      expect(byId[trustOnly]!.read<bool>('viewer_explicitly_trusts_subject'), isTrue);
      expect(byId[trustOnly]!.read<bool>('subject_explicitly_trusts_viewer'), isTrue);
      expect(_asDouble(byId[trustOnly]!.data['forward_mr']), 0);
      expect(_asDouble(byId[trustOnly]!.data['reverse_mr']), 0);

      expect(byId[mixed]!.read<bool>('viewer_explicitly_trusts_subject'), isFalse);
      expect(byId[mixed]!.read<bool>('subject_explicitly_trusts_viewer'), isTrue);
      expect(_asDouble(byId[mixed]!.data['forward_mr']), greaterThan(0));
    },
    skip: skipReason,
  );

  test('forwardCandidates wrap excludes MR peers missing from user', () async {
    const ghostId = 'Ufwghost0001';
    await insertUser(ghostId);
    await mrEdge(viewerId, ghostId);
    await mrEdge(ghostId, viewerId);
    addTearDown(() async {
      await clearMrEdge(viewerId, ghostId);
      await clearMrEdge(ghostId, viewerId);
      await db.customStatement(
        '''DELETE FROM public."user" WHERE id = '$ghostId' ''',
      );
    });

    expect(await _wrapPeerIds(db, viewerId: viewerId), contains(ghostId));

    await db.customStatement(
      '''DELETE FROM public."user" WHERE id = '$ghostId' ''',
    );

    final rawPeers = await db
        .customSelect(
          r'''
SELECT peer_id
FROM public.person_visibility_peers($1, $2)
WHERE peer_id = $3
''',
          variables: [
            Variable<String>(viewerId),
            Variable<String>(''),
            Variable<String>(ghostId),
          ],
        )
        .get();
    expect(rawPeers, isNotEmpty);

    final wrapIds = await _wrapPeerIds(db, viewerId: viewerId);
    expect(wrapIds, isNot(contains(ghostId)));
  }, skip: skipReason);

  test(
    'forwardCandidates wrap normalizes blank contexts like cap_normalize_context',
    () async {
      await applySignals(
        ctxPeerId,
        (trustOut: true, trustIn: true, mrOut: false, mrIn: false),
      );
      final empty = await _wrapPeerIds(db, viewerId: viewerId);
      final short = await _wrapPeerIds(db, viewerId: viewerId, context: 'ab');
      final padded = await _wrapPeerIds(db, viewerId: viewerId, context: '  ');
      final nullCtx = await db
          .customSelect(
            kForwardCandidatesWrapSql,
            variables: [
              Variable<String>(viewerId),
              const Variable<String>(null),
            ],
          )
          .map((row) => row.read<String>('peer_id'))
          .get();
      expect(short.toSet(), empty.toSet());
      expect(padded.toSet(), empty.toSet());
      expect(nullCtx.toSet(), empty.toSet());
      expect(empty, contains(ctxPeerId));
    },
    skip: skipReason,
  );

  test(
    'forwardCandidates wrap orders by forward_mr then name and caps at 500',
    () async {
      final high = scenarioPeers[0];
      final mid = scenarioPeers[1];
      final ann = scenarioPeers[2];
      final bob = scenarioPeers[3];
      await applySignals(
        high,
        (trustOut: false, trustIn: false, mrOut: true, mrIn: true),
      );
      await db.customStatement(
        "SELECT mr_put_edge('$viewerId', '$high', 0.9::double precision, ''::text, 0)",
      );
      await applySignals(
        mid,
        (trustOut: false, trustIn: false, mrOut: true, mrIn: true),
      );
      await db.customStatement(
        "SELECT mr_put_edge('$viewerId', '$mid', 0.4::double precision, ''::text, 0)",
      );
      await applySignals(
        ann,
        (trustOut: true, trustIn: true, mrOut: false, mrIn: false),
      );
      await applySignals(
        bob,
        (trustOut: true, trustIn: true, mrOut: false, mrIn: false),
      );
      await db.customStatement(
        "UPDATE public.\"user\" SET display_name = 'Zed' WHERE id = '$high'",
      );
      await db.customStatement(
        "UPDATE public.\"user\" SET display_name = 'Mia' WHERE id = '$mid'",
      );
      await db.customStatement(
        "UPDATE public.\"user\" SET display_name = 'Ann' WHERE id = '$ann'",
      );
      await db.customStatement(
        "UPDATE public.\"user\" SET display_name = 'Bob' WHERE id = '$bob'",
      );

      final ordered = await _wrapPeerIds(db, viewerId: viewerId);
      expect(ordered.take(4).toList(), [high, mid, ann, bob]);

      await db.customStatement(r'''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
SELECT
  'Ufwlim' || lpad(g::text, 3, '0'),
  'Ufwlim' || lpad(g::text, 3, '0'),
  'pk-Ufwlim' || lpad(g::text, 3, '0'),
  '2026-01-01T00:00:00Z',
  '2026-01-01T00:00:00Z'
FROM generate_series(1, 501) g
ON CONFLICT (id) DO NOTHING
''');
      await db.customStatement('''
INSERT INTO public.vote_user (subject, object, amount, created_at, updated_at)
SELECT '$viewerId', 'Ufwlim' || lpad(g::text, 3, '0'), 1,
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'
FROM generate_series(1, 501) g
ON CONFLICT (subject, object) DO UPDATE SET amount = EXCLUDED.amount
''');
      await db.customStatement('''
INSERT INTO public.vote_user (subject, object, amount, created_at, updated_at)
SELECT 'Ufwlim' || lpad(g::text, 3, '0'), '$viewerId', 1,
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'
FROM generate_series(1, 501) g
ON CONFLICT (subject, object) DO UPDATE SET amount = EXCLUDED.amount
''');
      addTearDown(() async {
        await db.customStatement(
          "DELETE FROM public.vote_user WHERE subject LIKE 'Ufwlim%' "
          "OR object LIKE 'Ufwlim%'",
        );
        await db.customStatement(
          '''DELETE FROM public."user" WHERE id LIKE 'Ufwlim%' ''',
        );
      });

      final capped = await _wrapPeerIds(db, viewerId: viewerId);
      expect(capped, hasLength(500));
      expect(capped, isNot(contains('Ufwlim501')));
    },
    skip: skipReason,
  );
}

Future<List<String>> _wrapPeerIds(
  TenturaDb db, {
  required String viewerId,
  String context = '',
}) async {
  final rows = await db
      .customSelect(
        kForwardCandidatesWrapSql,
        variables: [
          Variable<String>(viewerId),
          Variable<String>(context),
        ],
      )
      .get();
  return [for (final row in rows) row.read<String>('peer_id')];
}

Future<Set<String>> _mvuIds(
  TenturaDb db, {
  required String viewerId,
  String context = '',
}) async {
  final session = _sessionJson(viewerId);
  final rows = await db
      .customSelect(
        r'''
SELECT u.id
FROM public.mutually_visible_users($1, $2::json) u
''',
        variables: [
          Variable<String>(context),
          Variable<String>(session),
        ],
      )
      .get();
  return {for (final row in rows) row.read<String>('id')};
}

double _asDouble(Object? value) {
  if (value == null) {
    return 0;
  }
  if (value is num) {
    return value.toDouble();
  }
  throw StateError('Expected num, got ${value.runtimeType}');
}

Env _testEnv() => Env(
  environment: Environment.test,
  pgHost: Platform.environment['POSTGRES_HOST'] ?? 'localhost',
  pgPort: int.tryParse(Platform.environment['POSTGRES_PORT'] ?? '') ?? 5432,
  pgDatabase: Platform.environment['POSTGRES_DBNAME'] ?? 'postgres',
  pgUsername: Platform.environment['POSTGRES_USERNAME'] ?? 'postgres',
  pgPassword: Platform.environment['POSTGRES_PASSWORD'] ?? 'password',
  genealogyNodeKeySecret: 'test-genealogy-secret',
);

Future<bool> _canConnectPostgres() async {
  try {
    final env = _testEnv();
    final connection = await Connection.open(
      env.pgEndpoint,
      settings: env.pgEndpointSettings,
    );
    await connection.execute(Sql('SELECT 1'));
    await connection.close();
    return true;
  } catch (_) {
    return false;
  }
}

String _sessionJson(String userId) => jsonEncode({
  'x-hasura-user-id': userId,
});
