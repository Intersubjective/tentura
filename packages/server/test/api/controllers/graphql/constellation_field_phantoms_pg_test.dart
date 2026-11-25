@Tags(['pg'])
library;

import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:shelf_plus/shelf_plus.dart' show Request;
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/mappers/constellation_gql_maps.dart';
import 'package:tentura_server/api/controllers/graphql_controller.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/consts/constellation_consts.dart';
import 'package:tentura_server/domain/entity/constellation_field.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/use_case/constellation_field_case.dart';
import 'package:tentura_server/env.dart';
import 'package:tentura_server/utils/id.dart';

import '../../../support/disposable_pg_target.dart';
import '../../../support/session_database_di_harness.dart';

const _owner = 'Ufieldowner01';
const _other = 'Ufieldowner02';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_CONSTELLATION_FIELD_PHANTOMS_TEST_DB',
    defaultNamePrefix: 'tentura_test_field_phantoms',
  );
  final skip = await pgSkipReason(target);

  group('Field entries for people not on Tentura yet', () {
    late _FieldFixture fixture;
    late GraphqlController controller;

    setUpAll(() async {
      final previousWarning =
          driftRuntimeOptions.dontWarnAboutMultipleDatabases;
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      addTearDown(() {
        driftRuntimeOptions.dontWarnAboutMultipleDatabases = previousWarning;
      });
      final session = await setUpDisposablePgWriter(
        target: target,
        createPgmer2Extension: true,
      );
      addTearDown(() => tearDownDisposablePgWriter(session: session));
      addTearDown(() async {
        getIt.skipDoubleRegistration = false;
        await getIt.reset();
      });
      fixture = _FieldFixture(session.writer);

      const origin = 'http://127.0.0.1:2080';
      final db = target.databaseEnv;
      final env = Env(
        environment: Environment.dev,
        serverUri: Uri.parse(origin),
        publicOrigin: origin,
        publicKey: Env.kJwtPublicKey,
        privateKey: Env.kJwtPrivateKey,
        pgHost: db.pgHost,
        pgPort: db.pgPort,
        pgDatabase: db.pgDatabase,
        pgUsername: db.pgUsername,
        pgPassword: db.pgPassword,
        maxConnectionCount: 1,
        workersCount: 1,
        printEnv: false,
        isDebugModeOn: false,
      );
      await configureSessionDatabaseTestGraph(env);
      controller = GraphqlController(env);
    });

    setUp(() => fixture.reset());

    Future<ConstellationFieldSnapshot> field({
      String viewer = _owner,
      List<String> visiblePeers = const [],
    }) async {
      await fixture.cacheVisiblePeers(viewer, visiblePeers);
      return getIt<ConstellationFieldCase>().load(
        viewerId: viewer,
        context: kConstellationContext,
      );
    }

    Future<Object?> mutate(
      String operation,
      String resultField,
      Map<String, Object?> variables,
    ) async {
      final response = await controller.handler(
        Request(
          'POST',
          Uri.parse('http://localhost/api/v2/graphql'),
          headers: {'content-type': 'application/json'},
          context: {kContextJwtKey: const JwtEntity(sub: _owner)},
          body: jsonEncode({'query': operation, 'variables': variables}),
        ),
      );
      final body = await response.readAsString();
      expect(response.statusCode, 200, reason: body);
      final payload = jsonDecode(body) as Map<String, Object?>;
      expect(payload['errors'], isNull, reason: body);
      return (payload['data']! as Map<String, Object?>)[resultField];
    }

    test(
      'shows the owner the name, emoji and original creation time',
      () async {
        final id = await fixture.addPhantom(name: 'Anna K.', emoji: '🌻');
        final createdAt = await fixture.phantomCreatedAt(id);

        expect(_phantoms(await field()), [
          allOf(
            _entry(id, 'displayName', 'Anna K.'),
            containsPair('emoji', '🌻'),
            containsPair('createdAt', createdAt.toUtc().toIso8601String()),
            containsPair('hasPrivateAvatar', false),
          ),
        ]);
      },
    );

    test(
      'shows exactly the assigned tags and an empty list for untagged entries',
      () async {
        final tagged = await fixture.addPhantom();
        final untagged = await fixture.addPhantom();
        final firstTag = await fixture.addTag('Neighbours', tagged);
        final secondTag = await fixture.addTag('Friends', tagged);

        expect(
          _phantoms(await field()),
          unorderedEquals([
            _entry(tagged, 'ownTagIds', unorderedEquals([firstTag, secondTag])),
            _entry(untagged, 'ownTagIds', isEmpty),
          ]),
        );
      },
    );

    test(
      'reports pinned state only for an entry with a live Field pin',
      () async {
        final pinned = await fixture.addPhantom();
        final unpinned = await fixture.addPhantom();
        await fixture.pin(pinned);

        final snapshot = await field();

        expect(
          snapshot.anchorProjection.anchors.map(
            (anchor) => (anchor.target.kind.wireValue, anchor.target.id),
          ),
          [('PHANTOM', pinned)],
        );
        expect(
          _phantoms(snapshot),
          unorderedEquals([
            _entry(pinned, 'pinState', 'pinned'),
            _entry(unpinned, 'pinState', isNull),
          ]),
        );
      },
    );

    test(
      'shows a live invite on the first read after copying a link',
      () async {
        final id = await fixture.addPhantom();
        final before = await field();

        final invitation = await mutate(
          r'mutation($id: String!) { phantomInviteEnsure(id: $id) }',
          'phantomInviteEnsure',
          {'id': id},
        );
        expect(invitation, allOf(isA<String>(), isNotEmpty));
        final after = await field();

        expect(_phantoms(before), [_entry(id, 'inviteState', 'none')]);
        expect(_phantoms(after), [_entry(id, 'inviteState', 'live')]);
      },
    );

    test('reports the live invitation creation time for invite age', () async {
      final withInvite = await fixture.addPhantom();
      final withoutInvite = await fixture.addPhantom();
      final inviteCreatedAt = await fixture.addLiveInvitation(withInvite);

      final snapshot = await field();
      final invited = snapshot.phantoms.singleWhere(
        (person) => person.id == withInvite,
      );
      final uninvited = snapshot.phantoms.singleWhere(
        (person) => person.id == withoutInvite,
      );
      expect(invited.inviteCreatedAt, inviteCreatedAt);
      expect(invited.inviteCreatedAt?.isUtc, isTrue);
      expect(invited.inviteState, PhantomInviteState.live);
      expect(uninvited.inviteCreatedAt, isNull);
      expect(uninvited.inviteState, PhantomInviteState.none);
      expect(
        _phantoms(snapshot),
        unorderedEquals([
          _entry(
            withInvite,
            'inviteCreatedAt',
            inviteCreatedAt.toIso8601String(),
          ),
          _entry(withoutInvite, 'inviteCreatedAt', isNull),
        ]),
      );
    });

    test(
      'keeps private entries separate even when both owners are visible',
      () async {
        final own = await fixture.addPhantom();
        final foreign = await fixture.addPhantom(owner: _other);

        final ownField = await field(visiblePeers: [_other]);
        final otherField = await field(viewer: _other, visiblePeers: [_owner]);

        expect(ownField.peers.map((peer) => peer.id), [_other]);
        expect(otherField.peers.map((peer) => peer.id), [_owner]);
        expect(_phantoms(ownField), [containsPair('id', own)]);
        expect(_phantoms(otherField), [containsPair('id', foreign)]);
      },
    );

    test(
      'linking an entry to an account removes it and frees a peer slot',
      () async {
        final candidates = await fixture.addPeerCandidates();
        final willMerge = await fixture.addPhantom();
        final active = await fixture.addPhantom();
        final before = await field(visiblePeers: candidates);
        final linkedUser = candidates.first;

        await fixture.cacheVisiblePeers(_owner, candidates);
        expect(
          await mutate(
            r'mutation($id: String!, $user: String!) { phantomLink(phantomId: $id, userId: $user) }',
            'phantomLink',
            {'id': willMerge, 'user': linkedUser},
          ),
          isTrue,
        );
        final after = await field(visiblePeers: candidates);

        _expectPeerBudget(after, candidates, 399);
        _expectPeerBudget(before, candidates, 398);
        expect(_phantoms(after), [containsPair('id', active)]);
        expect(
          _phantoms(before),
          unorderedEquals([
            containsPair('id', active),
            containsPair('id', willMerge),
          ]),
        );
      },
    );

    for (final (count, budget) in [(150, 250), (200, 200)]) {
      test('$count private entries leave $budget peer slots', () async {
        final candidates = await fixture.addPeerCandidates();
        final withoutEntries = await field(visiblePeers: candidates);
        _expectPeerBudget(withoutEntries, candidates, 400);

        final ids = await fixture.addPhantoms(count);
        final withEntries = await field(visiblePeers: candidates);

        _expectPeerBudget(withEntries, candidates, budget);
        expect(
          _phantoms(withEntries),
          unorderedEquals([
            for (final id in ids) containsPair('id', id),
          ]),
        );
        expect(_phantoms(withoutEntries), isEmpty);
      });
    }

    test(
      'private entries leave a Field with no real contacts or peer records',
      () async {
        final ids = await fixture.addPhantoms(3);
        await fixture.pin(ids.first);

        final snapshot = await field();

        expect(snapshot.directContactIds, isEmpty);
        expect(snapshot.peers, isEmpty);
        expect(snapshot.edges, isEmpty);
        expect(snapshot.anchorProjection.pinnedPeers, isEmpty);
        expect(snapshot.anchorProjection.supportPeers, isEmpty);
        expect(
          _phantoms(snapshot),
          unorderedEquals([
            for (final id in ids) containsPair('id', id),
          ]),
        );
      },
    );
  }, skip: skip);
}

Object? _phantoms(ConstellationFieldSnapshot snapshot) =>
    constellationFieldToGqlMap(snapshot)['phantoms'];

Matcher _entry(String id, String field, Object? value) =>
    allOf(containsPair('id', id), containsPair(field, value));

void _expectPeerBudget(
  ConstellationFieldSnapshot snapshot,
  List<String> candidates,
  int budget,
) {
  final ids = [for (final peer in snapshot.peers) peer.id];
  expect(ids.length, budget, reason: 'The number of non-reserved peers');
  expect(ids.toSet(), hasLength(ids.length));
  expect(ids, everyElement(isIn(candidates)));
  expect(snapshot.peersCapped, isTrue);
}

final class _FieldFixture {
  const _FieldFixture(this.writer);

  final Connection writer;

  Future<void> reset() async {
    await writer.execute(
      'TRUNCATE public."user", public.person_visible_set_cache CASCADE',
    );
    await _addUsers([_owner, _other]);
  }

  Future<void> _addUsers(List<String> ids) => writer.execute(
    Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
SELECT id, id, 'pk-' || id FROM unnest(@ids::text[]) AS id
'''),
    parameters: {'ids': ids},
  );

  Future<List<String>> addPeerCandidates() async {
    // These people are visible through MeritRank. There are no direct contacts
    // or other reserved peers, so each returned peer uses one capped slot.
    final ids = List.generate(401, (_) => generateId('U'));
    await _addUsers(ids);
    return ids;
  }

  // Seed the real cache at its current generation to isolate Field selection
  // from the shared MeritRank service.
  Future<void> cacheVisiblePeers(String viewer, List<String> peerIds) =>
      writer.execute(
        Sql.named('''
INSERT INTO public.person_visible_set_cache
    (viewer_id, ctx, mr_epoch, trust_gen, peer_ids)
VALUES (
  @viewer, @context,
  coalesce((SELECT epoch FROM public.mr_publish_epoch WHERE id = true), 0),
  (SELECT generation FROM public.visibility_trust_generation WHERE id = true),
  @peerIds::text[])
ON CONFLICT (viewer_id, ctx) DO UPDATE
SET mr_epoch = EXCLUDED.mr_epoch,
    trust_gen = EXCLUDED.trust_gen,
    peer_ids = EXCLUDED.peer_ids
'''),
        parameters: {
          'viewer': viewer,
          'context': kConstellationContext,
          'peerIds': peerIds,
        },
      );

  Future<String> addPhantom({
    String owner = _owner,
    String name = 'An acquaintance',
    String? emoji,
  }) async =>
      (await addPhantoms(1, owner: owner, name: name, emoji: emoji)).single;

  Future<List<String>> addPhantoms(
    int count, {
    String owner = _owner,
    String name = 'An acquaintance',
    String? emoji,
  }) async {
    final ids = List.generate(count, (_) => generateId('PH'));
    await writer.executeWithOwnerScopes(
      [owner],
      Sql.named('''
INSERT INTO public.phantom (id, owner_id, display_name, emoji, created_at)
SELECT id, @owner, @name, @emoji, '2026-01-02T03:04:05.123456Z'::timestamptz
FROM unnest(@ids::text[]) AS id
'''),
      parameters: {'ids': ids, 'owner': owner, 'name': name, 'emoji': emoji},
    );
    return ids;
  }

  Future<DateTime> phantomCreatedAt(String id) async =>
      (await writer.execute(
            Sql.named('SELECT created_at FROM public.phantom WHERE id = @id'),
            parameters: {'id': id},
          )).single.single!
          as DateTime;

  Future<DateTime> addLiveInvitation(String phantom) async {
    final rows = await writer.executeWithOwnerScopes(
      [_owner],
      Sql.named('''
INSERT INTO public.invitation
  (user_id, phantom_id, addressee_name, invited_id, created_at)
VALUES (
  @owner, @phantom, 'An acquaintance', NULL, '2026-02-03T04:05:06.765432+05:30'
)
RETURNING created_at
'''),
      parameters: {'owner': _owner, 'phantom': phantom},
    );
    final createdAt = rows.single.single;
    if (createdAt is! DateTime) {
      throw StateError('The invitation did not return its creation time');
    }
    return createdAt.toUtc();
  }

  Future<String> addTag(String name, String phantom) async {
    final id = generateId('PT');
    await withPgOwnerScopes(writer, [_owner], (tx) async {
      await tx.execute(
        Sql.named('''
INSERT INTO public.person_tag (id, owner_id, name, glyph, color, ord)
VALUES (@id, @owner, @name, 'T', 0, 0)
'''),
        parameters: {'id': id, 'owner': _owner, 'name': name},
      );
      await tx.execute(
        Sql.named('''
INSERT INTO public.phantom_tag_member (tag_id, owner_id, phantom_id, source)
VALUES (@tag, @owner, @phantom, 0)
'''),
        parameters: {'tag': id, 'owner': _owner, 'phantom': phantom},
      );
    });
    return id;
  }

  Future<void> pin(String phantom) => withPgOwnerScopes(writer, [_owner], (
    tx,
  ) async {
    await tx.execute(
      Sql.named('''
INSERT INTO public.constellation_anchor_cursor (viewer_id) VALUES (@owner)
ON CONFLICT (viewer_id) DO NOTHING
'''),
      parameters: {'owner': _owner},
    );
    await tx.execute(
      Sql.named('''
INSERT INTO public.constellation_anchor (
  id, viewer_id, phantom_id, x_units, y_units,
  coordinate_space_version, revision, placed_at
) VALUES (@id, @owner, @phantom, 1.25, 2.5, 1, 0, 'epoch')
'''),
      parameters: {'id': generateId('CA'), 'owner': _owner, 'phantom': phantom},
    );
  });
}
