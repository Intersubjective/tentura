@Tags(['pg'])
library;

import 'package:graphql_schema2/graphql_schema2.dart';
import 'package:graphql_server2/graphql_server2.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_child_group.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_root/domain/entity/beacon_parent_reference.dart';

import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/query/query_beacon_hierarchy.dart';
import 'package:tentura_server/consts/beacon_hierarchy_consts.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_repository.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';

import '../../support/beacon_hierarchy_fixture.dart';
import '../../support/disposable_pg_target.dart';
import '../../support/post_bud_privacy_fixture.dart';
import '../../support/pg_test_public_keys.dart';
import 'beacon_hierarchy_pg_helpers.dart';

Future<void> main() async {
  await _postChildren();
  final reachable = await canConnectBeaconHierarchyPostgres();
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for beaconChildren authorization PG test';

  group('BeaconHierarchyRepository.listChildren authorization — disposable Postgres', () {
    late BeaconHierarchyDisposablePgTarget target;
    late Connection writer;
    late BeaconHierarchyFixture fixture;
    late BeaconHierarchyRepository repository;

    setUpAll(() async {
      if (skipReason != false) {
        return;
      }
      target = BeaconHierarchyDisposablePgTarget.fromEnvironment();
      await target.recreate();
      final session = await openBeaconHierarchyPgSession(target);
      writer = session.writer;
      fixture = BeaconHierarchyFixture(writer: writer, db: session.db);
      repository = BeaconHierarchyRepository(session.db);
    });

    tearDown(() async {
      if (skipReason != false) {
        return;
      }
      await writer.execute(
        "DELETE FROM public.user_block WHERE blocker_id LIKE 'Uhier%' "
        "OR blocked_id LIKE 'Uhier%'",
      );
      await fixture.tearDown();
    });

    tearDownAll(() async {
      if (skipReason != false) {
        return;
      }
      await fixture.db.close();
      await writer.close();
      await target.drop();
    });

    // seedPublishedHierarchyTree re-creates B/C/D, which drops their
    // participant rows; restore the fixture admissions afterwards.
    Future<void> seedTree() async {
      await fixture.seedFullTopology();
      await seedPublishedHierarchyTree(writer);
      for (final row in <(String, String, String)>[
        ('PhierbobB01', BeaconHierarchyTopology.beaconB, BeaconHierarchyTopology.bobId),
        ('PhiercarolC01', BeaconHierarchyTopology.beaconC, BeaconHierarchyTopology.carolId),
        ('PhieraliceA01', BeaconHierarchyTopology.beaconA, BeaconHierarchyTopology.aliceId),
      ]) {
        await writer.execute(
          Sql.named('''
INSERT INTO public.beacon_participant (
  id, beacon_id, user_id, role, status, room_access, created_at, updated_at
) VALUES (
  @id, @beaconId, @userId, 0, 0, @roomAccess,
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'
)
ON CONFLICT (id) DO UPDATE SET room_access = EXCLUDED.room_access
'''),
          parameters: {
            'id': row.$1,
            'beaconId': row.$2,
            'userId': row.$3,
            'roomAccess': RoomAccessBits.admitted,
          },
        );
      }
    }

    Future<bool> sqlPredicate(String fn, String beaconId, String viewerId) async {
      final row = await writer.execute(
        Sql.named('SELECT public.$fn(@beaconId, @viewerId)'),
        parameters: {'beaconId': beaconId, 'viewerId': viewerId},
      );
      return row.first.first! as bool;
    }

    Future<List<String>> childIds(
      String viewerId,
      BeaconHierarchyChildGroup group,
    ) async {
      final page = await repository.listChildren(
        parentBeaconId: BeaconHierarchyTopology.beaconA,
        viewerId: viewerId,
        group: group,
        first: 20,
      );
      return page.summaries.map((s) => s.beaconId).toList();
    }

    test('stranger who cannot read the parent gets an empty page', () async {
      await seedTree();
      // Dave owns grandchild C, a descendant of A, so since issue-146 T09 he
      // reads A via contextAncestor — he is no longer a genuine stranger to
      // A. Use a freshly seeded user with no relationship to the tree at all.
      const strangerId = 'Uhierstranger';
      await writer.execute(
        Sql.named(r'''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES (@id, @id, @publicKey, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
'''),
        parameters: {
          'id': strangerId,
          'publicKey': pgTestPublicKey('stranger', 1),
        },
      );
      expect(
        await sqlPredicate(
          'beacon_can_read_content',
          BeaconHierarchyTopology.beaconA,
          strangerId,
        ),
        isFalse,
        reason: 'precondition: the fresh stranger has no access to A',
      );

      final page = await repository.listChildren(
        parentBeaconId: BeaconHierarchyTopology.beaconA,
        viewerId: strangerId,
        group: BeaconHierarchyChildGroup.active,
        first: 20,
      );
      expect(page.summaries, isEmpty);
      expect(page.nextCursor, isNull);
    }, skip: skipReason);

    test('admitted member of A gets B and D; non-admitted reader only B', () async {
      await seedTree();

      expect(
        await childIds(
          BeaconHierarchyTopology.aliceId,
          BeaconHierarchyChildGroup.active,
        ),
        [BeaconHierarchyTopology.beaconB, BeaconHierarchyTopology.beaconD],
      );

      // Bob reads A only through his admission to child B; he is not
      // admitted to A, so sibling D stays hidden.
      expect(
        await sqlPredicate(
          'beacon_effective_admission',
          BeaconHierarchyTopology.beaconA,
          BeaconHierarchyTopology.bobId,
        ),
        isFalse,
        reason: 'precondition: bob is not admitted to A',
      );
      expect(
        await childIds(
          BeaconHierarchyTopology.bobId,
          BeaconHierarchyChildGroup.active,
        ),
        [BeaconHierarchyTopology.beaconB],
      );
    }, skip: skipReason);

    test('viewer blocked by D owner does not get D', () async {
      await seedTree();
      await writer.execute(
        Sql.named('''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES (@blocker, @blocked, @blocked)
ON CONFLICT DO NOTHING
'''),
        parameters: {
          'blocker': BeaconHierarchyTopology.eveId,
          'blocked': BeaconHierarchyTopology.aliceId,
        },
      );

      expect(
        await childIds(
          BeaconHierarchyTopology.aliceId,
          BeaconHierarchyChildGroup.active,
        ),
        [BeaconHierarchyTopology.beaconB],
      );
    }, skip: skipReason);

    test('deleted child tombstone is listed only for admitted members of A', () async {
      await seedTree();
      const deletedId = 'Bhierdelete01';
      await insertPublishedChildBeacon(
        writer: writer,
        childId: deletedId,
        parentId: BeaconHierarchyTopology.beaconA,
        ownerId: BeaconHierarchyTopology.eveId,
        title: 'Deleted child',
        status: BeaconStatus.deleted,
        publishedAt: DateTime.utc(2026, 1, 2),
      );

      final aliceDeleted = await repository.listChildren(
        parentBeaconId: BeaconHierarchyTopology.beaconA,
        viewerId: BeaconHierarchyTopology.aliceId,
        group: BeaconHierarchyChildGroup.deleted,
        first: 20,
      );
      expect(aliceDeleted.summaries.map((s) => s.beaconId), [deletedId]);
      expect(aliceDeleted.summaries.single.isTombstone, isTrue);
      expect(aliceDeleted.summaries.single.title, isNull);

      expect(
        await childIds(
          BeaconHierarchyTopology.bobId,
          BeaconHierarchyChildGroup.deleted,
        ),
        isEmpty,
        reason: 'bob reads A via child B but is not admitted to A',
      );
      expect(
        await childIds(
          BeaconHierarchyTopology.frankId,
          BeaconHierarchyChildGroup.deleted,
        ),
        isEmpty,
        reason: 'frank reads A via his help offer but is not admitted to A',
      );
      expect(
        await childIds(
          BeaconHierarchyTopology.daveId,
          BeaconHierarchyChildGroup.deleted,
        ),
        isEmpty,
      );
    }, skip: skipReason);
  });
}

Future<void> _postChildren() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_POST_CHILD_REFERENCES_TEST_DB',
    defaultNamePrefix: 'tentura_test_post_child_refs',
  );
  final skip = await pgSkipReason(target);
  group('Post hierarchy authorization', () {
    late PostBudPrivacyFixture fixture;
    setUpAll(() async {
      final session = await setUpDisposablePgWriter(target: target);
      final database = openDisposablePgDatabase(target);
      addTearDown(
        () => tearDownDisposablePgWriter(session: session, drift: database),
      );
      fixture = PostBudPrivacyFixture(
        session.writer,
        database,
        target.databaseEnv,
      );
    });

    test(
      'Post child references respect Request access throughout its lifecycle',
      () async {
        await fixture.seedPost();
        final child = await fixture.bud();
        const post = PostBudPrivacyFixture.post;
        const bob = PostBudPrivacyFixture.bob;
        const carol = PostBudPrivacyFixture.carol;

        final query = QueryBeaconHierarchy(
          hierarchyRepository: fixture.hierarchy,
        );
        final graphQL = GraphQL(
          GraphQLSchema(
            queryType: GraphQLObjectType('Query', 'Query root')
              ..fields.add(query.beaconChildren),
          ),
        );

        Future<List<String>> ids(
          String viewer,
          BeaconHierarchyChildGroup group, {
          String parentId = post,
        }) async {
          final data = await graphQL.parseAndExecute(
            '''
query {
  beaconChildren(parentBeaconId: "$parentId", group: "${group.name}", first: 20) {
    nextCursor
    summaries { beaconId }
  }
}
''',
            globalVariables: {kGlobalInputQueryJwt: JwtEntity(sub: viewer)},
          );
          final page =
              (data as Map<String, dynamic>)['beaconChildren']
                  as Map<String, dynamic>;
          expect(
            page['nextCursor'],
            isNull,
            reason: 'The page is the full list',
          );
          return [
            for (final summary in page['summaries'] as List)
              (summary as Map<String, dynamic>)['beaconId'] as String,
          ];
        }

        Future<BeaconParentReference> parent(String viewer) => fixture.hierarchy
            .loadParentReference(childBeaconId: child, viewerId: viewer);

        final bobParent = await parent(bob);
        expect(bobParent.state, BeaconParentReferenceState.available);
        expect(bobParent.beaconId, post);
        expect(bobParent.isPost, isTrue);
        final carolParent = await parent(carol);
        expect(carolParent.state, BeaconParentReferenceState.none);
        expect(carolParent.beaconId, isNull);
        expect(carolParent.title, isNull);
        expect(
          await fixture.hierarchy.loadChildPreview(
            beaconId: child,
            viewerId: carol,
          ),
          isNull,
        );

        final bobActive = await ids(bob, BeaconHierarchyChildGroup.active);
        final carolActive = await ids(carol, BeaconHierarchyChildGroup.active);
        // V2 returns summaries and a cursor. These complete lists give the
        // number of children each viewer can see without an admin-side count.
        expect(bobActive.length, 1, reason: 'Bob sees one child of the Post');
        expect(
          carolActive.length,
          0,
          reason: 'Carol sees no children of the Post',
        );
        final (requestParent, requestChild) = await _seedRequestHierarchy(
          fixture,
        );
        for (final viewer in [bob, carol]) {
          expect(
            await ids(
              viewer,
              BeaconHierarchyChildGroup.active,
              parentId: requestParent,
            ),
            [requestChild],
            reason:
                'Request parent membership still reveals its child to $viewer',
          );
        }
        await fixture.closeRequest(requestChild);
        for (final viewer in [bob, carol]) {
          expect(
            await ids(
              viewer,
              BeaconHierarchyChildGroup.finished,
              parentId: requestParent,
            ),
            [requestChild],
          );
        }
        await _expectRequestHierarchyDelivery(
          fixture,
          requestParent,
          requestChild,
        );
        await fixture.closeRequest(child);
        final bobFinished = await ids(bob, BeaconHierarchyChildGroup.finished);
        final carolFinished = await ids(
          carol,
          BeaconHierarchyChildGroup.finished,
        );

        await fixture.beacons.recordBeaconStatusTransition(
          beaconId: child,
          fromStatus: BeaconStatus.closed,
          toStatus: BeaconStatus.deleted,
          reason: 'delete',
          actorId: PostBudPrivacyFixture.anna,
        );
        expect(
          {
            'Bob active': bobActive,
            'Carol active': carolActive,
            'Bob finished': bobFinished,
            'Carol finished': carolFinished,
            'Carol deleted': await ids(
              carol,
              BeaconHierarchyChildGroup.deleted,
            ),
          },
          {
            'Bob active': [child],
            'Carol active': isEmpty,
            'Bob finished': [child],
            'Carol finished': isEmpty,
            'Carol deleted': isEmpty,
          },
        );
      },
    );
  }, skip: skip ?? false);
}

Future<(String, String)> _seedRequestHierarchy(
  PostBudPrivacyFixture fixture,
) async {
  const parent = 'BbudprivacyQ';
  const child = 'BbudprivacyS';
  const anna = PostBudPrivacyFixture.anna;
  const bob = PostBudPrivacyFixture.bob;
  const carol = PostBudPrivacyFixture.carol;
  await fixture.writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, is_discoverable, parent_beacon_id, published_at)
VALUES
  ('$parent', '$anna', 'Prepare the community garden', '', 0, false, NULL, now()),
  ('$child', '$anna', 'Repair the gate', '', 0, false, '$parent', now())
''');
  await fixture.writer.execute('''
INSERT INTO public.beacon_participant
  (beacon_id, user_id, role, status, room_access)
VALUES ('$parent', '$bob', 0, 0, 3), ('$parent', '$carol', 0, 0, 3)
''');
  return (parent, child);
}

Future<void> _expectRequestHierarchyDelivery(
  PostBudPrivacyFixture fixture,
  String parent,
  String child,
) async {
  final targets = await fixture.writer.execute(
    Sql.named('''
SELECT d.event_id, d.target_beacon_id, d.direction, d.state, d.notice_message_id,
       e.occurred_at
FROM public.beacon_hierarchy_deliveries d
JOIN public.beacon_hierarchy_events e ON e.id = d.event_id
WHERE e.source_beacon_id = @child
'''),
    parameters: {'child': child},
  );
  expect(targets, hasLength(1));
  final target = targets.single.toColumnMap();
  expect(target, containsPair('target_beacon_id', parent));
  expect(target, containsPair('direction', 'child'));
  expect(target, containsPair('state', 'delivered'));
  expect(target['notice_message_id'], isA<String>());

  const bob = PostBudPrivacyFixture.bob;
  const carol = PostBudPrivacyFixture.carol;
  final utcDate = (target['occurred_at']! as DateTime)
      .toUtc()
      .toIso8601String()
      .split('T')
      .first;
  for (final viewer in [bob, carol]) {
    final room = await fixture.room.listMessages(
      beaconId: parent,
      userId: viewer,
    );
    final notices = room.where(
      (message) =>
          message['systemMessageKind'] ==
          BeaconRoomSystemMessageKind.hierarchyLifecycle,
    );
    expect(notices, hasLength(1));
    expect(notices.single['id'], target['notice_message_id']);
    expect(notices.single['body'], 'A child request was closed on $utcDate');
  }

  final recipients = await fixture.writer.execute(
    Sql.named('''
SELECT r.account_id
FROM public.attention_occurrence_recipient r
JOIN public.attention_occurrence o ON o.id = r.occurrence_id
WHERE o.source_event_key = @key
'''),
    parameters: {'key': "hierarchy:${target['event_id']}:$parent"},
  );
  expect(recipients.map((row) => row.single), unorderedEquals([bob, carol]));
}
