@Tags(['pg'])
@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';

import 'package:drift_postgres/drift_postgres.dart';
import 'package:graphql_schema2/graphql_schema2.dart';
import 'package:graphql_server2/graphql_server2.dart';
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/custom_types.dart';
import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/mappers/gql_v2_dto_maps.dart';
import 'package:tentura_server/api/controllers/graphql/query/query_forward_graph.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/forward_edge_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/inbox_repository.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/use_case/beacon_forward_graph_case.dart';

import '../../../support/disposable_pg_target.dart';
import '../../../support/pg_test_public_keys.dart';
import '../../../support/query_counter.dart';

const _a = 'Utreeauthor';
const _b = 'Utreeboris';
const _r = 'Utreeraf';
const _v = 'Utreevera';
const _d = 'Utreedima';
const _k = 'Utreekim';
const _l = 'Utreelena';
const _outsider = 'Utreeoutsider';
const _offerOnly = 'Utreeofferonly';
const _memberOnly = 'Utreememberonly';
const _cancelledOnly = 'Utreecancelled';
const _beacon = 'Bforwardtree1';
const _names = {
  _a: 'Anna Author',
  _b: 'Boris Branch',
  _r: 'Raf Branch',
  _v: 'Vera Helper',
  _d: 'Dima Unavailable',
  _k: 'Kim Unread',
  _l: 'Lena Reader',
  _outsider: 'Olga Outsider',
  _offerOnly: 'Owen Offer',
  _memberOnly: 'Maya Member',
  _cancelledOnly: 'Chris Cancelled',
};
const _orderedEdges = ['Fab', 'Fbv', 'Far', 'Fbk', 'Fbd', 'Frl'];
final _at = DateTime.utc(2026, 10, 31, 12);

// Sender and recipient of every live edge in the tree fixture.
const _edgeEnds = {
  'Fab': (_a, _b),
  'Fbv': (_b, _v),
  'Far': (_a, _r),
  'Fbk': (_b, _k),
  'Fbd': (_b, _d),
  'Frl': (_r, _l),
};
const _participants = [_a, _b, _r, _v, _d, _k, _l];

// Drift statements that could change MeritRank's graph. The server reaches
// MeritRank only through these pgmer2 SQL functions on its own connection.
final _mrMutation = RegExp(
  'mr_(put_edge|delete_edge|bulk_load_edges|set_new_edges_filter|sync|'
  r'bump_publish_epoch)\s*\(',
  caseSensitive: false,
);

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_FORWARD_TREE_TEST_DB',
    defaultNamePrefix: 'tentura_test_forward_tree',
  );
  final unavailable = await pgSkipReason(target);
  if (unavailable != null) {
    test('forward tree requires reachable Postgres', () => fail(unavailable));
    return;
  }

  group('Forward tree shared with chain participants', () {
    late DisposablePgWriterSession session;
    late TenturaDb db;
    late QueryCounter counter;
    late _StatementLog statements;
    late BeaconForwardGraphCase graphCase;
    late GraphQL graphQL;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      counter = QueryCounter();
      statements = _StatementLog();
      db = TenturaDb.forTest(
        database: PgDatabase.opened(
          Pool<dynamic>.withEndpoints(
            [target.databaseEnv.pgEndpoint],
            settings: target.databaseEnv.pgPoolSettings,
          ),
          enableMigrations: false,
        ).interceptWith(counter).interceptWith(statements),
      );
      graphCase = BeaconForwardGraphCase(
        BeaconRepository(db),
        ForwardEdgeRepository(db),
        HelpOfferRepository(db),
        BeaconAccessRepository(db),
        BeaconRoomRepository(db),
        env: target.databaseEnv,
        logger: Logger('ForwardTreePgTest'),
      );
      graphQL = GraphQL(
        GraphQLSchema(
          queryType: GraphQLObjectType('Query', null)
            ..fields.addAll(
              QueryForwardGraph(beaconForwardGraphCase: graphCase).all,
            ),
        ),
        customTypes: customTypes,
      );
    });

    Future<void> seed({int kind = 0}) async {
      await session.writer.execute(
        'TRUNCATE public.beacon, public."user" CASCADE',
      );
      for (final (i, entry) in _names.entries.indexed) {
        await session.writer.execute(
          Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @name, @key)
'''),
          parameters: {
            'id': entry.key,
            'name': entry.value,
            'key': pgTestPublicKey('${String.fromCharCode(97 + i)}t', 1),
          },
        );
      }
      await session.writer.execute(
        Sql.named('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, published_at, is_discoverable, kind)
VALUES (@beacon, @author, @title, '', 0, @at, @discoverable, @kind)
'''),
        parameters: {
          'beacon': _beacon,
          'author': _a,
          'at': _at,
          'kind': kind,
          'title': kind == 1 ? '' : 'A shared Request',
          'discoverable': kind == 0,
        },
      );
      // Insert order differs from chronology, while preserving parent FKs.
      for (final (id, sender, recipient, parent, second) in [
        ('Fab', _a, _b, null, 0),
        ('Far', _a, _r, null, 2),
        ('Fbv', _b, _v, 'Fab', 1),
        ('Fbd', _b, _d, 'Fab', 4),
        ('Fbk', _b, _k, 'Fab', 3),
        ('Frl', _r, _l, 'Far', 5),
        ('Fcancel', _v, _cancelledOnly, 'Fbv', 6),
      ]) {
        await session.writer.execute(
          Sql.named('''
INSERT INTO public.beacon_forward_edge
  (id, beacon_id, sender_id, recipient_id, parent_edge_id, created_at,
   recipient_read_at, recipient_rejected, cancelled_at)
VALUES (@id, @beacon, @sender, @recipient, @parent, @at, @read, @rejected,
        @cancelled)
'''),
          parameters: {
            'id': id,
            'beacon': _beacon,
            'sender': sender,
            'recipient': recipient,
            'parent': parent,
            'at': _at.add(Duration(seconds: second)),
            'read': recipient == _l
                ? _at.add(const Duration(minutes: 1))
                : null,
            'rejected': false,
            'cancelled': id == 'Fcancel'
                ? _at.add(const Duration(minutes: 2))
                : null,
          },
        );
      }
      if (kind == 0) {
        // Produce the rejection flag through the same inbox update and DB
        // trigger as a recipient's "can't help" response.
        await InboxRepository(db).setStatus(
          userId: _d,
          beaconId: _beacon,
          status: 2,
          rejectionMessage: 'Cannot make it',
        );
        await _offer(session.writer, _v);
        await session.writer.execute(
          Sql.named('''
INSERT INTO public.beacon_help_offer_coordination
  (offer_beacon_id, offer_user_id, author_user_id, response_type)
VALUES (@beacon, @helper, @author, 0)
'''),
          parameters: {'beacon': _beacon, 'helper': _v, 'author': _a},
        );
        await session.writer.execute(
          Sql.named('''
INSERT INTO public.beacon_help_offer_admission_event
  (id, beacon_id, offer_user_id, actor_user_id, action)
VALUES ('Eacceptvera', @beacon, @helper, @author, 1)
'''),
          parameters: {'beacon': _beacon, 'helper': _v, 'author': _a},
        );
      }
      await session.writer.execute(
        Sql.named('''
INSERT INTO public.beacon_participant
  (beacon_id, user_id, role, status, room_access)
VALUES (@beacon, @helper, 2, 1, 3)
ON CONFLICT (beacon_id, user_id) DO UPDATE SET room_access = 3
'''),
        parameters: {'beacon': _beacon, 'helper': _v},
      );
    }

    setUp(seed);

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session, drift: db);
    });

    // The public resolver, production access guard and repositories all run.
    // Existing fields let tree visibility fail independently of new fields.
    Future<Map<String, dynamic>> query(
      String viewer, {
      bool withOfferStatus = false,
    }) async {
      final result = await graphQL.parseAndExecute(
        '''
query ForwardTree(\$id: String!) {
  beaconForwardGraph(id: \$id) {
    beaconId authorId
    edges { id senderId recipientId parentEdgeId
${withOfferStatus ? 'offerStatus' : ''}
    }
  }
}
''',
        variableValues: {'id': _beacon},
        globalVariables: {kGlobalInputQueryJwt: JwtEntity(sub: viewer)},
      );
      return (result as Map<String, dynamic>)['beaconForwardGraph']
          as Map<String, dynamic>;
    }

    // Inspect the production wire projection without assuming where named
    // tree nodes will live. The old schema has only a single-route `path`;
    // this deliberately does not prescribe `nodes`, nested endpoints, etc.
    Future<Map<String, dynamic>> projection(String viewer) async =>
        forwardGraphResultToGqlMap(
          await graphCase.asMap(beaconId: _beacon, currentUserId: viewer),
        );

    Map<String, Map<String, dynamic>> byId(Map<String, dynamic> result) => {
      for (final edge in (result['edges'] as List).cast<Map<String, dynamic>>())
        edge['id'] as String: edge,
    };

    Map<String, dynamic> edge(Map<String, dynamic> result, String id) {
      final edges = byId(result);
      expect(edges, contains(id), reason: 'the tree must contain edge $id');
      return edges[id]!;
    }

    // Each edge endpoint is a person node: named, or anonymous when a block
    // between that person and the viewer hides them.
    Map<String, dynamic> person(Map<String, dynamic> e, String side) {
      expect(
        e,
        contains(side),
        reason: 'edge ${e['id']} must carry its $side as a person node',
      );
      return (e[side] as Map).cast<String, dynamic>();
    }

    Matcher named(String id) => allOf(
      containsPair('userId', id),
      containsPair('displayName', _names[id]),
      containsPair('anonymousCount', 0),
    );

    final anonymous = allOf(
      containsPair('userId', null),
      containsPair('displayName', null),
      containsPair('anonymousCount', 1),
    );

    for (final viewer in [_a, _b, _r, _v, _d, _k, _l]) {
      test(
        '${_names[viewer]} receives all live branches and dead ends',
        () async {
          final result = await query(viewer);
          expect(byId(result).keys, orderedEquals(_orderedEdges));
          expect(edge(result, 'Frl')['parentEdgeId'], 'Far');
          expect(edge(result, 'Fbk')['parentEdgeId'], 'Fab');
          expect(byId(result), isNot(contains('Fcancel')));
        },
      );
    }

    for (final status in [0, 1]) {
      test('an offer without a forward grants the whole tree when '
          '${status == 0 ? 'active' : 'withdrawn'}', () async {
        if (status == 1) {
          // A withdrawn offer alone grants no access to the Request's
          // content (beacon_access_sql_parity_test). This person still
          // reaches it through mutual trust with the author, which by itself
          // yields only the helper chains (see the reachable-viewer test).
          await session.writer.execute(
            Sql.named('''
INSERT INTO public.vote_user (subject, object, amount)
VALUES (@viewer, @author, 1), (@author, @viewer, 1)
'''),
            parameters: {'viewer': _offerOnly, 'author': _a},
          );
        }
        await _offer(session.writer, _offerOnly, status: status);
        expect(
          byId(await query(_offerOnly)).keys,
          orderedEquals(_orderedEdges),
        );
      });
    }

    // Post fixture: forwards admit each recipient to the room (m0212 has no
    // help offers on a Post). Dima has since left the chat; Maya is an
    // admitted member who neither sent nor received a forward.
    Future<void> seedPost() async {
      await seed(kind: 1);
      await session.writer.execute(
        Sql.named('''
INSERT INTO public.beacon_participant
  (beacon_id, user_id, role, status, room_access)
VALUES (@beacon, @person, 2, 1, 5)
ON CONFLICT (beacon_id, user_id) DO UPDATE SET room_access = 5
'''),
        parameters: {'beacon': _beacon, 'person': _d},
      );
      await session.writer.execute(
        Sql.named('''
INSERT INTO public.beacon_participant
  (beacon_id, user_id, role, status, room_access)
VALUES (@beacon, @member, 2, 1, 3)
'''),
        parameters: {'beacon': _beacon, 'member': _memberOnly},
      );
    }

    test('an admitted Post member with no edge or offer receives every '
        'forward edge, including the branch to someone who left', () async {
      await seedPost();
      final memberStanding = await session.writer.execute(
        Sql.named('''
SELECT
  (SELECT count(*) FROM public.beacon_forward_edge
   WHERE beacon_id = @beacon
     AND (sender_id = @member OR recipient_id = @member)),
  (SELECT count(*) FROM public.beacon_help_offer WHERE beacon_id = @beacon),
  (SELECT count(*) FROM public.beacon_participant
   WHERE beacon_id = @beacon AND user_id = @member AND room_access = 3)
'''),
        parameters: {'beacon': _beacon, 'member': _memberOnly},
      );
      expect(memberStanding.single.toList(), [0, 0, 1]);
      expect(byId(await query(_memberOnly)).keys, orderedEquals(_orderedEdges));
    });

    test('Post viewers outside the chain keep their existing result', () async {
      await seedPost();
      // A plain outsider has no involvement access to a Post at all.
      await expectLater(
        query(_outsider),
        throwsA(isA<UnauthorizedException>()),
      );
      // A steward reads involvement without being a chain participant: no
      // edge, offer or room membership.
      await session.writer.execute(
        Sql.named('''
INSERT INTO public.beacon_steward (beacon_id, user_id)
VALUES (@beacon, @viewer)
'''),
        parameters: {'beacon': _beacon, 'viewer': _outsider},
      );
      final outsiderStanding = await session.writer.execute(
        Sql.named('''
SELECT
  (SELECT count(*) FROM public.beacon_forward_edge
   WHERE beacon_id = @beacon
     AND (sender_id = @viewer OR recipient_id = @viewer)),
  (SELECT count(*) FROM public.beacon_help_offer
   WHERE beacon_id = @beacon AND user_id = @viewer),
  (SELECT count(*) FROM public.beacon_participant
   WHERE beacon_id = @beacon AND user_id = @viewer)
'''),
        parameters: {'beacon': _beacon, 'viewer': _outsider},
      );
      expect(outsiderStanding.single.toList(), [0, 0, 0]);
      // Today's steward result: how each currently admitted member got in
      // (every edge into Boris, Raf, Vera, Kim, Lena and their ancestors).
      // Dima left, so the dead-end edge to Dima is not part of it.
      expect(
        byId(await query(_outsider)).keys,
        orderedEquals(['Fab', 'Fbv', 'Far', 'Fbk', 'Frl']),
      );
    });

    test("a reachable Request viewer outside the chain keeps today's "
        'helper chains only', () async {
      // Reachable involvement without an edge, offer or room membership.
      await session.writer.execute(
        Sql.named('''
INSERT INTO public.vote_user (subject, object, amount)
VALUES (@viewer, @author, 1), (@author, @viewer, 1)
'''),
        parameters: {'viewer': _outsider, 'author': _a},
      );
      // Today's result: the chain to the active help offerer Vera.
      expect(byId(await query(_outsider)).keys, orderedEquals(['Fab', 'Fbv']));
    });

    test(
      'a cancelled delivery alone never makes someone a chain participant',
      () async {
        await expectLater(
          query(_cancelledOnly),
          throwsA(isA<UnauthorizedException>()),
        );
      },
    );

    for (final viewer in _participants) {
      test('${_names[viewer]} sees both ends of every edge by name', () async {
        // Lena and Boris are not mutually visible on the Field.
        final mutual = await session.writer.execute(
          Sql.named('''
SELECT public.person_are_mutually_visible_cached(@viewer, @person, '')
'''),
          parameters: {'viewer': _l, 'person': _b},
        );
        expect(mutual.single.single, isFalse);
        final result = await projection(viewer);
        for (final MapEntry(key: id, value: (sender, recipient))
            in _edgeEnds.entries) {
          final e = edge(result, id);
          expect(person(e, 'sender'), named(sender), reason: '$id sender');
          expect(
            person(e, 'recipient'),
            named(recipient),
            reason: '$id recipient',
          );
          expect(e, containsPair('senderId', sender));
          expect(e, containsPair('recipientId', recipient));
        }
      });
    }

    test('reading the tree writes nothing: no visibility, trust, anchor or '
        'MeritRank changes', () async {
      // Snapshot every table and materialized view in the database: the
      // visible-set, mutual-visibility, Field, anchor and trust stores all
      // live there, so a write through any of them (or a trigger) shows up.
      final before = await _snapshotAllTables(session.writer);
      expect(before.keys, containsAll(_storesThatMustStayUntouched));
      statements.clear();
      final results = [
        for (final viewer in _participants) await projection(viewer),
      ];
      expect(statements.writes, isEmpty, reason: 'no INSERT/UPDATE/DELETE');
      expect(
        statements.all.where(_mrMutation.hasMatch),
        isEmpty,
        reason: 'no MeritRank graph mutation',
      );
      final after = await _snapshotAllTables(session.writer);
      for (final table in before.keys) {
        expect(after[table], before[table], reason: '$table was written');
      }
      expect(after.keys, unorderedEquals(before.keys));
      final mutual = await session.writer.execute(
        Sql.named('''
SELECT public.person_are_mutually_visible_cached(@viewer, @person, '')
'''),
        parameters: {'viewer': _l, 'person': _b},
      );
      expect(mutual.single.single, isFalse);
      // The calls above must have served the whole tree, not a narrower one.
      for (final result in results) {
        expect(byId(result).keys, orderedEquals(_orderedEdges));
      }
    });

    for (final (blocker, blocked) in [(_l, _b), (_b, _l), (_a, _d)]) {
      test('when ${_names[blocker]} blocks ${_names[blocked]}, each of them '
          'sees the other as an anonymous node and everyone else sees both '
          'named', () async {
        await session.writer.execute(
          Sql.named('''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES (@blocker, @blocked, @blocker)
'''),
          parameters: {'blocker': blocker, 'blocked': blocked},
        );
        for (final viewer in _participants) {
          final hidden = viewer == blocker
              ? blocked
              : viewer == blocked
              ? blocker
              : null;
          if (hidden == _a) {
            // A block with the author hides the Request itself: the content
            // predicate keeps block restrictions, so no tree is served.
            await expectLater(
              projection(viewer),
              throwsA(isA<UnauthorizedException>()),
            );
            continue;
          }
          final result = await projection(viewer);
          for (final MapEntry(key: id, value: (sender, recipient))
              in _edgeEnds.entries) {
            final e = edge(result, id);
            for (final (side, who) in [
              ('sender', sender),
              ('recipient', recipient),
            ]) {
              expect(
                person(e, side),
                who == hidden ? anonymous : named(who),
                reason: '$id $side as seen by ${_names[viewer]}',
              );
            }
          }
          if (hidden != null) {
            expect(
              jsonEncode(result),
              isNot(contains(_names[hidden])),
              reason:
                  'the hidden name must not appear anywhere for '
                  '${_names[viewer]}',
            );
          }
        }
      });
    }

    test('read receipts distinguish unread from read only for the author and '
        'the sender of that edge', () async {
      for (final viewer in [_b, _a]) {
        expect(
          edge(await projection(viewer), 'Fbk'),
          containsPair('readAt', null),
        );
      }
      await ForwardEdgeRepository(db).markAsRead('Fbk', _k);
      final stamp =
          (await session.writer.execute(
                "SELECT recipient_read_at FROM public.beacon_forward_edge WHERE id = 'Fbk'",
              )).single.single!
              as DateTime;
      for (final viewer in [_b, _a]) {
        final value = edge(await projection(viewer), 'Fbk')['readAt'];
        expect(value, isA<String>());
        expect(DateTime.parse(value as String), stamp);
      }
      for (final viewer in [_r, _l, _k, _v, _d]) {
        expect(
          edge(await projection(viewer), 'Fbk'),
          containsPair('readAt', null),
        );
      }
      // Author status is global; sender status is specific to each edge.
      for (final viewer in [_a, _r]) {
        expect(
          edge(await projection(viewer), 'Frl'),
          containsPair(
            'readAt',
            _at.add(const Duration(minutes: 1)).toIso8601String(),
          ),
        );
      }
      expect(edge(await projection(_b), 'Frl'), containsPair('readAt', null));
    });

    test(
      'recipient rejection is visible only to the author and that edge sender',
      () async {
        for (final viewer in [_b, _a]) {
          final result = await projection(viewer);
          expect(edge(result, 'Fbd'), containsPair('declinedInvite', true));
          expect(edge(result, 'Fbv'), containsPair('declinedInvite', false));
        }
        for (final viewer in [_r, _l, _d, _v, _k]) {
          expect(
            edge(await projection(viewer), 'Fbd'),
            containsPair('declinedInvite', null),
          );
        }
      },
    );

    test('a declined author invitation is a private recipient state even '
        'without an inbox rejection', () async {
      await session.writer.execute(
        Sql.named('''
INSERT INTO public.beacon_forward_edge
  (id, beacon_id, sender_id, recipient_id, created_at)
VALUES ('Fak', @beacon, @author, @recipient, @at)
'''),
        parameters: {
          'beacon': _beacon,
          'author': _a,
          'recipient': _k,
          'at': _at.add(const Duration(minutes: 3)),
        },
      );
      await session.writer.execute(
        Sql.named('''
INSERT INTO public.beacon_author_invite
  (beacon_id, inviter_id, invitee_id, forward_edge_id, warm, status,
   resolved_at, resolved_by)
VALUES (@beacon, @author, @recipient, 'Fak', false, 2, now(), @recipient)
'''),
        parameters: {'beacon': _beacon, 'author': _a, 'recipient': _k},
      );
      final rejected = await session.writer.execute(
        "SELECT sender_id, recipient_rejected FROM public.beacon_forward_edge WHERE id = 'Fak'",
      );
      expect(rejected.single.toList(), [_a, false]);
      // An author invitation's delivery is sent by the author, so Anna
      // exercises both permitted roles here. Boris sent a different edge
      // to Kim and has no right to the private state of this delivery.
      expect(
        edge(await projection(_a), 'Fak'),
        containsPair('declinedInvite', true),
      );
      for (final viewer in [_b, _r, _l, _k, _v, _d]) {
        expect(
          edge(await projection(viewer), 'Fak'),
          containsPair('declinedInvite', null),
        );
      }
    });

    for (final status in [
      'none',
      'offered',
      'accepted',
      'withdrawn',
      'declinedByAuthor',
    ]) {
      test(
        'every chain participant sees recipient offer status $status',
        () async {
          if (status != 'none' && status != 'accepted') {
            await _offer(
              session.writer,
              _k,
              status: status == 'withdrawn' ? 1 : 0,
            );
            if (status == 'declinedByAuthor') {
              await session.writer.execute(
                Sql.named('''
INSERT INTO public.beacon_help_offer_coordination
  (offer_beacon_id, offer_user_id, author_user_id, response_type)
VALUES (@beacon, @helper, @author, 4)
'''),
                parameters: {'beacon': _beacon, 'helper': _k, 'author': _a},
              );
              await session.writer.execute(
                Sql.named('''
INSERT INTO public.beacon_help_offer_admission_event
  (id, beacon_id, offer_user_id, actor_user_id, action, reason)
VALUES ('Edeclinekim', @beacon, @helper, @author, 2, 'Different help needed')
'''),
                parameters: {'beacon': _beacon, 'helper': _k, 'author': _a},
              );
            }
          }
          for (final viewer in [_b, _a, _r, _v, _d, _k, _l]) {
            final result = await query(viewer, withOfferStatus: true);
            expect(
              edge(result, 'Fbv'),
              allOf(
                containsPair('recipientId', _v),
                containsPair('offerStatus', 'accepted'),
              ),
              reason: 'Vera has her own accepted offer for $viewer',
            );
            expect(
              edge(result, 'Fbk'),
              allOf(
                containsPair('recipientId', _k),
                containsPair(
                  'offerStatus',
                  status == 'accepted' ? 'none' : status,
                ),
              ),
              reason: 'Kim has her own recipient state for $viewer',
            );
          }
        },
      );
    }

    test('offer status follows each edge recipient when Vera is declined '
        'and Kim is accepted', () async {
      // Reset Vera's acceptance fixture before giving her a declined offer.
      // Kim's separate offer is accepted, so a beacon-wide status cannot
      // satisfy these assertions for both incoming edges.
      await session.writer.execute(
        Sql.named('''
DELETE FROM public.beacon_help_offer_admission_event
WHERE beacon_id = @beacon AND offer_user_id = @helper
'''),
        parameters: {'beacon': _beacon, 'helper': _v},
      );
      await session.writer.execute(
        Sql.named('''
UPDATE public.beacon_participant SET room_access = 1
WHERE beacon_id = @beacon AND user_id = @helper
'''),
        parameters: {'beacon': _beacon, 'helper': _v},
      );
      await session.writer.execute(
        Sql.named('''
UPDATE public.beacon_help_offer_coordination SET response_type = 4
WHERE offer_beacon_id = @beacon AND offer_user_id = @helper
'''),
        parameters: {'beacon': _beacon, 'helper': _v},
      );
      await _offer(session.writer, _k);
      await session.writer.execute(
        Sql.named('''
INSERT INTO public.beacon_help_offer_coordination
  (offer_beacon_id, offer_user_id, author_user_id, response_type)
VALUES (@beacon, @helper, @author, 0)
'''),
        parameters: {'beacon': _beacon, 'helper': _k, 'author': _a},
      );
      await session.writer.execute(
        Sql.named('''
INSERT INTO public.beacon_help_offer_admission_event
  (id, beacon_id, offer_user_id, actor_user_id, action, reason)
VALUES ('Edeclinevera', @beacon, @vera, @author, 2, 'Different help needed'),
       ('Eacceptkim', @beacon, @kim, @author, 1, NULL)
'''),
        parameters: {'beacon': _beacon, 'vera': _v, 'kim': _k, 'author': _a},
      );
      await session.writer.execute(
        Sql.named('''
INSERT INTO public.beacon_participant
  (beacon_id, user_id, role, status, room_access)
VALUES (@beacon, @helper, 2, 1, 3)
ON CONFLICT (beacon_id, user_id) DO UPDATE SET room_access = 3
'''),
        parameters: {'beacon': _beacon, 'helper': _k},
      );
      for (final viewer in [_b, _a, _r, _v, _d, _k, _l]) {
        final result = await query(viewer, withOfferStatus: true);
        expect(edge(result, 'Fbv'), containsPair('recipientId', _v));
        expect(
          edge(result, 'Fbv'),
          containsPair('offerStatus', 'declinedByAuthor'),
        );
        expect(edge(result, 'Fbk'), containsPair('recipientId', _k));
        expect(edge(result, 'Fbk'), containsPair('offerStatus', 'accepted'));
      }
    });

    test(
      'forwarded-on states include live children and ignore cancelled children',
      () async {
        for (final viewer in [_a, _b, _r, _v, _d, _k, _l]) {
          final result = await projection(viewer);
          expect(edge(result, 'Fab'), containsPair('forwardedOn', true));
          expect(edge(result, 'Far'), containsPair('forwardedOn', true));
          expect(edge(result, 'Fbv'), containsPair('forwardedOn', false));
          expect(edge(result, 'Fbk'), containsPair('forwardedOn', false));
        }
      },
    );

    test(
      'edge creation timestamps allow replay in chronological order',
      () async {
        final result = await projection(_a);
        // First prove timestamps are actually delivered, not merely sorted
        // inside the server and discarded by its wire mapper.
        for (final row in byId(result).values) {
          expect(row, contains('createdAt'));
          expect(row['createdAt'], isA<String>());
        }
        expect(byId(result).keys, orderedEquals(_orderedEdges));
        for (final (second, id) in _orderedEdges.indexed) {
          expect(
            DateTime.parse(edge(result, id)['createdAt'] as String),
            _at.add(Duration(seconds: second)),
          );
        }
      },
    );

    test(
      'reading a larger complete tree uses a constant number of database reads',
      () async {
        // Warm the executor before measuring. Fixture writes bypass it.
        await query(_b);
        counter.reset();
        final small = await projection(_b);
        final smallCount = counter.count;
        for (var i = 0; i < 20; i++) {
          final id = 'Utreeextra$i';
          await session.writer.execute(
            Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
            parameters: {
              'id': id,
              'key': pgTestPublicKey('${String.fromCharCode(97 + i)}x', 1),
            },
          );
          await session.writer.execute(
            Sql.named('''
INSERT INTO public.beacon_forward_edge
  (id, beacon_id, sender_id, recipient_id, parent_edge_id, created_at)
VALUES (@id, @beacon, @sender, @recipient, 'Far', @at)
'''),
            parameters: {
              'id': 'Fextra$i',
              'beacon': _beacon,
              'sender': _r,
              'recipient': id,
              'at': _at.add(Duration(minutes: i + 10)),
            },
          );
          await _offer(session.writer, id, status: i.isEven ? 0 : 1);
        }
        counter.reset();
        final large = await projection(_b);
        final largeCount = counter.count;
        expect(smallCount, greaterThan(0));
        expect(
          largeCount,
          smallCount,
          reason: 'no per-edge or per-offer round trips',
        );
        expect(byId(small).keys, orderedEquals(_orderedEdges));
        expect(byId(large), hasLength(26));
        expect(edge(large, 'Fbv'), containsPair('offerStatus', 'accepted'));
        expect(edge(large, 'Fab'), containsPair('forwardedOn', true));
        for (var i = 0; i < 20; i++) {
          expect(
            edge(large, 'Fextra$i'),
            containsPair('offerStatus', i.isEven ? 'offered' : 'withdrawn'),
          );
        }
      },
    );
  });
}

Future<void> _offer(Connection writer, String user, {int status = 0}) =>
    writer.execute(
      Sql.named('''
INSERT INTO public.beacon_help_offer (beacon_id, user_id, status)
VALUES (@beacon, @user, @status)
'''),
      parameters: {'beacon': _beacon, 'user': user, 'status': status},
    );

// Visibility, Field, anchor and trust stores that must exist in the
// snapshot; guards against the enumeration silently missing them.
const _storesThatMustStayUntouched = [
  'public.person_visible_set_cache',
  'public.person_mutual_visibility_cache',
  'public.person_field_first_seen',
  'public.constellation_anchor',
  'public.user_trust_edge',
  'public.trust_evidence',
  'public.trust_publish_queue',
  'public.vote_user',
  'public.user_contact',
];

// Complete row contents of every table and materialized view outside the
// system schemas, so an UPDATE is caught as well as an INSERT or DELETE.
Future<Map<String, Object?>> _snapshotAllTables(Connection writer) async {
  final relations = await writer.execute('''
SELECT format('%I.%I', n.nspname, c.relname)
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind IN ('r', 'p', 'm')
  AND n.nspname NOT IN ('pg_catalog', 'information_schema')
  AND n.nspname NOT LIKE 'pg_toast%'
  AND n.nspname NOT LIKE 'pg_temp%'
ORDER BY 1
''');
  return {
    for (final row in relations)
      row.single! as String: (await writer.execute('''
SELECT coalesce(jsonb_agg(row ORDER BY row::text), '[]'::jsonb)
FROM (SELECT to_jsonb(t) AS row FROM ${row.single} t) snapshot
''')).single.single,
  };
}

// Records every statement Drift sends, and which of them are writes.
class _StatementLog extends QueryInterceptor {
  final all = <String>[];
  final writes = <String>[];

  void clear() {
    all.clear();
    writes.clear();
  }

  void _write(String statement) {
    all.add(statement);
    writes.add(statement);
  }

  @override
  Future<void> runBatched(
    QueryExecutor executor,
    BatchedStatements statements,
  ) {
    statements.statements.forEach(_write);
    return super.runBatched(executor, statements);
  }

  @override
  Future<void> runCustom(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    all.add(statement);
    if (RegExp(
      r'^\s*(insert|update|delete|merge|truncate)\b',
      caseSensitive: false,
    ).hasMatch(statement)) {
      writes.add(statement);
    }
    return super.runCustom(executor, statement, args);
  }

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _write(statement);
    return super.runInsert(executor, statement, args);
  }

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _write(statement);
    return super.runUpdate(executor, statement, args);
  }

  @override
  Future<int> runDelete(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _write(statement);
    return super.runDelete(executor, statement, args);
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    all.add(statement);
    return super.runSelect(executor, statement, args);
  }
}
