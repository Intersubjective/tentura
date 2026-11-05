@Tags(['pg'])
library;

import 'package:graphql_server2/graphql_server2.dart' show GraphQL;
import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/query/query_constellation_field.dart';
import 'package:tentura_server/api/controllers/graphql/schema.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/data/database/tentura_db.dart' show TenturaDb;
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_room_repository_port.dart';
import 'package:tentura_server/domain/port/forward_edge_repository_port.dart';
import 'package:tentura_server/domain/port/inbox_repository_port.dart';
import 'package:tentura_server/domain/port/help_offer_repository_port.dart';
import 'package:tentura_server/env.dart';

import '../../../support/constellation_anchor_batch_fixture.dart';
import '../../../support/disposable_pg_target.dart';
import '../../../support/pg_test_public_keys.dart';

const _viewer = 'Ufieldhide001';
const _other = 'Ufieldhide002';
const _author = 'Ufieldhide003';
const _stranger = 'Ufieldhide004';
const _request = 'Bfieldhide001';
const _post = 'Bfieldhide002';
const _private = 'Bfieldhide003';

// Coverage: real registered GraphQL mutations and queries, production DI and
// migrated PostgreSQL. Full Field reads include discoverable, own, admitted and
// pinned paths. Both content kinds, viewer isolation, freshness and rejection
// are covered below. Input device, viewport and locale are n/a (server only).
// targetKind follows beacon.kind: 0=Request, 1=Post. Hidden items use the usual
// GraphQL camelCase wire names (targetId, title, authorId, hiddenAt).
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_FIELD_PERSONAL_VISIBILITY_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_field_personal_visibility',
  );
  final unavailable = await pgSkipReason(target);
  if (unavailable != null) {
    test('Postgres unavailable', () {}, skip: unavailable);
    return;
  }

  late DisposablePgWriterSession session;
  late Connection writer;
  late GraphQL schema;

  setUpAll(() async {
    session = await setUpDisposablePgWriter(
      target: target,
      createPgmer2Extension: true,
    );
    writer = session.writer;
    final pg = target.databaseEnv;
    await configureDependencies(
      Env(
        environment: Environment.dev,
        serverUri: Uri.parse('http://127.0.0.1:2080'),
        publicKey: Env.kJwtPublicKey,
        privateKey: Env.kJwtPrivateKey,
        pgHost: pg.pgHost,
        pgPort: pg.pgPort,
        pgDatabase: pg.pgDatabase,
        pgUsername: pg.pgUsername,
        pgPassword: pg.pgPassword,
        publicOrigin: 'http://127.0.0.1:2080',
        workersCount: 1,
        printEnv: false,
        isDebugModeOn: false,
      ),
    );
    await getIt.allReady(ignorePendingAsyncCreation: true);
    schema = graphqlSchema;
  });

  tearDownAll(() async {
    await getIt.reset();
    await tearDownDisposablePgWriter(session: session);
  });

  Future<void> forward(String id, String recipient) =>
      getIt<ForwardEdgeRepositoryPort>().create(
        beaconId: id,
        senderId: _author,
        recipientId: recipient,
        note: 'Please take a look',
      );

  setUp(() async {
    await writer.execute('TRUNCATE public."user" CASCADE');
    for (final (index, id) in [_viewer, _other, _author, _stranger].indexed) {
      await writer.execute(
        Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
        parameters: {
          'id': id,
          'key': pgTestPublicKey('field-personal-visibility', index + 1),
        },
      );
    }
    for (final viewer in [_viewer, _other]) {
      await writer.execute(
        Sql.named('''
INSERT INTO public.vote_user (subject, object, amount)
VALUES (@viewer, @author, 1), (@author, @viewer, 1)
'''),
        parameters: {'viewer': viewer, 'author': _author},
      );
    }
    await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, is_discoverable,
   published_at, expires_at)
VALUES
  ('$_request', '$_author', 'Help with the garden', '', 0, 0, true, now(), NULL),
  ('$_post', '$_author', '', '', 0, 1, false,
   now() - interval '1 hour', now() + interval '71 hours'),
  ('$_private', '$_stranger', 'Private Request', '', 0, 0, false, now(), NULL)
''');
    await writer.execute('''
INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body)
VALUES ('Mfieldhide001', '$_post', '$_author', 'Garden news')
''');
    await writer.execute('''
UPDATE public.beacon SET post_root_message_id = 'Mfieldhide001'
WHERE id = '$_post'
''');
    await writer.execute('''
INSERT INTO public.beacon_participant
  (beacon_id, user_id, role, status, room_access)
VALUES ('$_post', '$_viewer', 6, 0, 3), ('$_post', '$_other', 6, 0, 3)
''');
  });

  Future<Map<String, dynamic>> run(
    String document, {
    String viewer = _viewer,
    Map<String, dynamic> variables = const {},
  }) async =>
      await schema.parseAndExecute(
            document,
            variableValues: variables,
            globalVariables: {kGlobalInputQueryJwt: JwtEntity(sub: viewer)},
          )
          as Map<String, dynamic>;

  Future<void> changeHide(
    String operation,
    String id,
    int kind, {
    String viewer = _viewer,
  }) async {
    final result = await run(
      'mutation { $operation(targetKind: $kind, targetId: "$id") }',
      viewer: viewer,
    );
    expect(
      result[operation],
      isTrue,
      reason: '$operation must be registered and acknowledge the viewer action',
    );
  }

  Future<void> hide(String id, int kind, {String viewer = _viewer}) =>
      changeHide('fieldHide', id, kind, viewer: viewer);
  Future<void> unhide(String id, int kind, {String viewer = _viewer}) =>
      changeHide('fieldUnhide', id, kind, viewer: viewer);

  Future<List<Map<String, dynamic>>> hidden({String viewer = _viewer}) async {
    final result = await run('''
query { fieldHiddenItems { targetKind targetId title authorId hiddenAt } }
''', viewer: viewer);
    expect(
      result['fieldHiddenItems'],
      isA<List<Object?>>(),
      reason: 'fieldHiddenItems must return the viewers effective hides',
    );
    return (result['fieldHiddenItems'] as List).cast<Map<String, dynamic>>();
  }

  // The public resolver uses the production case, snapshot reader and mapper;
  // direct invocation keeps this helper independent of unrelated selections.
  Future<Map<String, dynamic>> field({String viewer = _viewer}) async =>
      await QueryConstellationField().constellationField.resolve!(null, {
            kGlobalInputQueryJwt: JwtEntity(sub: viewer),
            'showClosed': false,
            'participatedOnly': false,
            'projection': 'FULL',
          })
          as Map<String, dynamic>;

  Future<void> expectVisible(
    String id,
    int kind, {
    required bool visible,
    String viewer = _viewer,
  }) async {
    final payload = await field(viewer: viewer);
    final projection = payload['anchorProjection'] as Map;
    final rows = [
      ...payload[kind == 0 ? 'requests' : 'posts'] as List,
      ...(projection['pinnedRequests'] as List).where(
        (row) => (row as Map)['kind'] == kind,
      ),
    ];
    expect(
      rows.map((row) => (row as Map)['id']),
      visible ? contains(id) : isNot(contains(id)),
      reason: '$id must ${visible ? "appear" : "stay absent"} for $viewer',
    );
  }

  Future<List<String>> hiddenStorage() async => (await writer.execute('''
SELECT to_jsonb(h)::text FROM public.field_hidden h
ORDER BY viewer_id, target_kind, target_id
''')).map((row) => row.single! as String).toList();

  Future<List<String>> inboxAndNotifications() async =>
      (await writer.execute('''
SELECT 'inbox:' || to_jsonb(i)::text AS row FROM public.inbox_item i
UNION ALL
SELECT 'notification:' || to_jsonb(n)::text FROM public.notification_outbox n
ORDER BY row
''')).map((row) => row.single! as String).toList();

  Future<void> pin(String id) =>
      constellationAnchorRepositoryFor(getIt<TenturaDb>()).applyAnchorUpsert(
        viewerId: _viewer,
        context: '',
        target: ConstellationAnchorTarget.beacon(id),
        position: const ConstellationAnchorPosition(
          xUnits: 1,
          yUnits: 2,
          coordinateSpaceVersion: 1,
        ),
      );

  Future<void> admit(String id, {String viewer = _viewer}) =>
      getIt<BeaconRoomRepositoryPort>().inviteOfferUserToBeaconRoom(
        beaconId: id,
        offerUserId: viewer,
        authorUserId: _author,
      );

  Future<void> prepareOffers() async {
    for (final viewer in [_viewer, _other]) {
      await getIt<HelpOfferRepositoryPort>().upsert(
        beaconId: _request,
        userId: viewer,
        message: 'I can help',
      );
    }
  }

  Future<void> answerOffer({
    required bool accept,
    String viewer = _viewer,
  }) async {
    final result = await run(
      accept
          ? 'mutation { acceptHelpOffer(id: "$_request", offerUserId: "$viewer") { status } }'
          : 'mutation { declineHelpOffer(id: "$_request", offerUserId: "$viewer", reason: "other") { status } }',
      viewer: _author,
    );
    expect(result[accept ? 'acceptHelpOffer' : 'declineHelpOffer'], isNotNull);
  }

  group('Personal Field visibility', () {
    for (final (id, kind, label) in [
      (_request, 0, 'Request'),
      (_post, 1, 'Post'),
    ]) {
      test('hiding a $label affects only the callers Field', () async {
        await expectVisible(id, kind, visible: true);
        await expectVisible(id, kind, visible: true, viewer: _other);
        await hide(id, kind);
        await expectVisible(id, kind, visible: false);
        await expectVisible(id, kind, visible: true, viewer: _other);
      });

      test('unhiding a $label restores it after refetch', () async {
        await expectVisible(id, kind, visible: true);
        await hide(id, kind);
        await expectVisible(id, kind, visible: false);
        await unhide(id, kind);
        await expectVisible(id, kind, visible: true);
        expect(await hidden(), isEmpty);
      });

      test('repeating a $label hide preserves its original time', () async {
        await expectVisible(id, kind, visible: true);
        await hide(id, kind);
        final first = await hidden();
        expect(first, hasLength(1));
        expect(first.single['hiddenAt'], isNotNull);
        await hide(id, kind);
        expect(await hidden(), first);
        expect(await hiddenStorage(), hasLength(1));
        await expectVisible(id, kind, visible: false);
      });

      test('repeating a $label unhide leaves it visible', () async {
        await expectVisible(id, kind, visible: true);
        // Unhiding an item that has never been hidden is also idempotent.
        await unhide(id, kind);
        await unhide(id, kind);
        await expectVisible(id, kind, visible: true);
        await hide(id, kind);
        await unhide(id, kind);
        await unhide(id, kind);
        await expectVisible(id, kind, visible: true);
        expect(await hiddenStorage(), isEmpty);
      });

      test('an author can hide their own $label', () async {
        await expectVisible(id, kind, visible: true, viewer: _author);
        await hide(id, kind, viewer: _author);
        await expectVisible(id, kind, visible: false, viewer: _author);
        await expectVisible(id, kind, visible: true);
      });

      test(
        'a hidden pinned $label is absent from every Field item list',
        () async {
          await pin(id);
          final before = (await field())['anchorProjection'] as Map;
          expect(
            (before['pinnedRequests'] as List).map((row) => (row as Map)['id']),
            contains(id),
          );
          await hide(id, kind);
          await expectVisible(id, kind, visible: false);
          final after = (await field())['anchorProjection'] as Map;
          expect(
            (after['pinnedRequests'] as List).map((row) => (row as Map)['id']),
            isNot(contains(id)),
          );
        },
      );

      test(
        'an authors ordinary $label chat message does not undo a hide',
        () async {
          if (kind == 0) await admit(id);
          await expectVisible(id, kind, visible: true);
          await hide(id, kind);
          await getIt<BeaconRoomRepositoryPort>().insertRoomMessage(
            beaconId: id,
            authorId: _author,
            body: 'A normal chat update',
          );
          await expectVisible(id, kind, visible: false);
          expect((await hidden()).map((row) => row['targetId']), contains(id));
        },
      );

      test(
        'a new $label forward to the viewer makes a hidden item return',
        () async {
          await expectVisible(id, kind, visible: true);
          await hide(id, kind);
          final stored = await hiddenStorage();
          await forward(id, _viewer);
          await expectVisible(id, kind, visible: true);
          expect(await hidden(), isEmpty);
          expect(
            await hiddenStorage(),
            stored,
            reason: 'auto-return is a read-time decision, not a hide write',
          );
        },
      );

      test('a $label forward to another viewer does not undo a hide', () async {
        await hide(id, kind);
        await forward(id, _other);
        await expectVisible(id, kind, visible: false);
        expect((await hidden()).map((row) => row['targetId']), contains(id));
      });

      test(
        'a $label forward received before hiding does not undo the hide',
        () async {
          await forward(id, _viewer);
          await expectVisible(id, kind, visible: true);
          await hide(id, kind);
          await expectVisible(id, kind, visible: false);
          expect((await hidden()).map((row) => row['targetId']), contains(id));
        },
      );

      test('admission to a $label room makes a hidden item return', () async {
        await expectVisible(id, kind, visible: true);
        await hide(id, kind);
        await expectVisible(id, kind, visible: false);
        expect((await hidden()).map((row) => row['targetId']), [id]);
        final stored = await hiddenStorage();
        if (kind == 1) {
          // A Post is already admitted to enter the Field. Model the viewer
          // awaiting re-admission, then run the real admission operation.
          await writer.execute('''
UPDATE public.beacon_participant SET room_access = 0
WHERE beacon_id = '$_post' AND user_id = '$_viewer'
''');
        }
        await admit(id);
        await expectVisible(id, kind, visible: true);
        expect(
          await hidden(),
          isEmpty,
          reason:
              'room admission must also remove the now-ineffective hide '
              'from the hidden-items query',
        );
        expect(await hiddenStorage(), stored);
      });
    }

    for (final accept in [true, false]) {
      final decision = accept ? 'accepting' : 'declining';
      test(
        'the author $decision the viewers offer makes a hidden Request return',
        () async {
          await prepareOffers();
          await expectVisible(_request, 0, visible: true);
          await hide(_request, 0);
          final stored = await hiddenStorage();
          await prepareOffers();
          await expectVisible(_request, 0, visible: false);
          expect(
            (await hidden()).map((row) => row['targetId']),
            [_request],
            reason:
                'updating an offer is not an author decision and must '
                'leave the hide effective',
          );
          await answerOffer(accept: accept);
          await expectVisible(_request, 0, visible: true);
          expect(
            await hidden(),
            isEmpty,
            reason:
                'the author $decision the viewers offer must also remove '
                'the now-ineffective hide from the hidden-items query',
          );
          expect(await hiddenStorage(), stored);
        },
      );

      test(
        'the author $decision another helpers offer does not undo a hide',
        () async {
          await prepareOffers();
          await hide(_request, 0);
          await answerOffer(accept: accept, viewer: _other);
          await expectVisible(_request, 0, visible: false);
          expect((await hidden()).map((row) => row['targetId']), [_request]);
        },
      );

      test(
        'an offer decision made before hiding does not undo the hide after $decision',
        () async {
          await prepareOffers();
          await answerOffer(accept: accept);
          await expectVisible(_request, 0, visible: true);
          await hide(_request, 0);
          await expectVisible(_request, 0, visible: false);
          expect((await hidden()).map((row) => row['targetId']), [_request]);
        },
      );
    }

    test(
      'hiding and unhiding leave For-you rows and author notifications unchanged',
      () async {
        await forward(_request, _viewer);
        final before = await inboxAndNotifications();
        expect(before, isNotEmpty);
        await hide(_request, 0);
        await expectVisible(_request, 0, visible: false);
        expect(await inboxAndNotifications(), before);
        await unhide(_request, 0);
        await expectVisible(_request, 0, visible: true);
        expect(await inboxAndNotifications(), before);
      },
    );

    test('unhiding affects only the callers row for the same item', () async {
      await hide(_request, 0);
      await hide(_request, 0, viewer: _other);
      final otherRows = await hidden(viewer: _other);
      await unhide(_request, 0);
      await expectVisible(_request, 0, visible: true);
      await expectVisible(_request, 0, visible: false, viewer: _other);
      expect(await hidden(viewer: _other), otherRows);
    });

    test(
      'hiding an item preserves another viewers existing hide and time',
      () async {
        await hide(_request, 0, viewer: _other);
        final otherRows = await hidden(viewer: _other);
        expect(otherRows, hasLength(1));
        await hide(_request, 0);
        expect(await hidden(viewer: _other), otherRows);
        await expectVisible(_request, 0, visible: false);
        await expectVisible(_request, 0, visible: false, viewer: _other);
      },
    );

    test(
      'an unreadable target cannot be hidden and leaves all stored hides unchanged',
      () async {
        // Successful setup proves that a missing mutation is not mistaken for
        // the expected access denial on the private target.
        await hide(_request, 0, viewer: _other);
        final before = await hiddenStorage();
        final readable = await writer.execute('''
SELECT public.beacon_can_read_content('$_private', '$_viewer')
''');
        expect(readable.single.single, isFalse);
        await expectLater(
          hide(_private, 0),
          throwsA(isA<UnauthorizedException>()),
        );
        expect(await hiddenStorage(), before);
        expect(await hidden(), isEmpty);
      },
    );

    test(
      'an unreadable target can still be unhidden, which removes only the stored hide',
      () async {
        await hide(_request, 0);
        await writer.execute('''
UPDATE public.beacon SET is_discoverable = false WHERE id = '$_request'
''');
        await writer.execute('''
DELETE FROM public.beacon_help_offer WHERE beacon_id = '$_request';
''');
        final readable = await writer.execute('''
SELECT public.beacon_can_read_content('$_request', '$_viewer')
''');
        expect(readable.single.single, isFalse);
        expect(await hiddenStorage(), isNotEmpty);
        await unhide(_request, 0);
        expect(await hiddenStorage(), isEmpty);
      },
    );
  });

  group('Hidden Field items', () {
    test('a viewer without effective hides receives an empty list', () async {
      expect(await hidden(), isEmpty);
    });

    test(
      'effective hides are newest first with the item title author and hide time',
      () async {
        await hide(_request, 0);
        // Give the older hide a distinct time without relying on wall-clock
        // progress or specifying the ordering of equal-time hides. No addressed
        // event has happened on this Request, so the older hide stays effective.
        final olderHiddenAt =
            (await writer.execute(
                  Sql.named('''
UPDATE public.field_hidden SET hidden_at = hidden_at - interval '1 hour'
WHERE viewer_id = @viewer AND target_kind = 0 AND target_id = @id
RETURNING hidden_at
'''),
                  parameters: {'viewer': _viewer, 'id': _request},
                )).single.single!
                as DateTime;
        await hide(_post, 1);
        final rows = await hidden();
        expect(rows.map((row) => row['targetId']), [_post, _request]);
        expect(rows.map((row) => row['targetKind']), [1, 0]);
        expect(rows.map((row) => row['authorId']), [_author, _author]);
        expect(rows.last['title'], 'Help with the garden');
        expect(rows.first['title'], 'Garden news');
        final times = rows
            .map((row) => DateTime.parse(row['hiddenAt'] as String))
            .toList();
        expect(times.last, olderHiddenAt);
        expect(times.first.isAfter(times.last), isTrue);
        expect(
          DateTime.now().toUtc().difference(times.first).abs(),
          lessThan(const Duration(minutes: 1)),
        );
        expect(await hidden(viewer: _other), isEmpty);
        await forward(_request, _viewer);
        expect((await hidden()).map((row) => row['targetId']), [_post]);
      },
    );
  });

  group('For-you rejection on the Field', () {
    Future<void> expectRequestSurfaces({
      required bool regular,
      required bool pinned,
      String viewer = _viewer,
    }) async {
      final payload = await field(viewer: viewer);
      expect(
        (payload['requests'] as List).map((row) => (row as Map)['id']),
        regular ? contains(_request) : isNot(contains(_request)),
        reason:
            'the ordinary Field list must ${regular ? "contain" : "exclude"} '
            'the Request for $viewer',
      );
      final projection = payload['anchorProjection'] as Map;
      expect(
        (projection['pinnedRequests'] as List).map((row) => (row as Map)['id']),
        pinned ? contains(_request) : isNot(contains(_request)),
        reason:
            'the pinned Field projection must ${pinned ? "contain" : "exclude"} '
            'the Request for $viewer',
      );
    }

    for (final pinned in [false, true]) {
      test(
        'a rejected ${pinned ? "pinned" : "discoverable"} Request is absent only for the rejecting viewer',
        () async {
          await forward(_request, _viewer);
          await expectRequestSurfaces(regular: true, pinned: false);
          if (pinned) await pin(_request);
          await expectRequestSurfaces(regular: !pinned, pinned: pinned);
          await expectRequestSurfaces(
            regular: true,
            pinned: false,
            viewer: _other,
          );
          await getIt<InboxRepositoryPort>().setStatus(
            userId: _viewer,
            beaconId: _request,
            status: 2,
            rejectionMessage: 'Busy this week',
          );
          await expectRequestSurfaces(regular: false, pinned: false);
          await expectRequestSurfaces(
            regular: true,
            pinned: false,
            viewer: _other,
          );
        },
      );
    }
  });
}
