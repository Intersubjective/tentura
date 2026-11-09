@Tags(['pg', 'mr'])
library;

import 'dart:convert';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/entity/auth_request_intent.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/trust_publish_repository.dart';
import 'package:tentura_server/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura_server/domain/entity/constellation_field.dart';
import 'package:tentura_server/domain/port/constellation_field_repository_port.dart';
import 'package:tentura_server/domain/use_case/auth_case.dart';
import 'package:tentura_server/domain/use_case/invitation_case.dart';
import 'package:tentura_server/domain/use_case/people_tags_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

const _anna = 'Uinhmranna01';
const _boris = 'Uinhmrboris1';

/// Membership source of a tag a newcomer inherited from their inviter.
const _inherited = 4;

String _signUpRequest(String invitationId) {
  final publicKey = EdDSAPublicKey.fromPEM(
    Env.kJwtPublicKey.replaceAll(r'\n', '\n'),
  );
  final privateKey = EdDSAPrivateKey.fromPEM(
    Env.kJwtPrivateKey.replaceAll(r'\n', '\n'),
  );
  return JWT({
    AuthRequestIntent.keyPublicKey: base64UrlEncode(publicKey.bytes),
    AuthRequestIntentSignUp.keyCode: invitationId,
  }).sign(
    privateKey,
    algorithm: JWTAlgorithm.EdDSA,
    expiresIn: const Duration(minutes: 5),
  );
}

/// The newcomer of a tagged inviter as QA meets them: Anna never trusts Nova
/// herself, so Nova reaches Anna's Field only through MeritRank, by way of
/// Boris who invited Nova. The invite signup's own trust edges go to
/// MeritRank through the production trust publisher. The Field read that
/// first meets Nova live puts Nova into Anna's tag that holds Boris, marked
/// as inherited.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_FIELD_NEWCOMER_INHERITS_TAGS_MR_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_field_inh_mr',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  late DisposablePgWriterSession session;
  late Connection writer;
  late TrustPublishRepository publisher;
  final mrEdges = <(String, String)>[];
  var opCounter = 0;

  String nextOp() => 'op-field-inh-mr-${opCounter++}';

  setUpAll(() async {
    session = await setUpDisposablePgWriter(
      target: target,
      createPgmer2Extension: true,
    );
    writer = session.writer;
    final db = target.databaseEnv;
    await configureDependencies(
      Env(
        environment: Environment.dev,
        serverUri: Uri.parse('http://127.0.0.1:2080'),
        publicKey: Env.kJwtPublicKey,
        privateKey: Env.kJwtPrivateKey,
        pgHost: db.pgHost,
        pgPort: db.pgPort,
        pgDatabase: db.pgDatabase,
        pgUsername: db.pgUsername,
        pgPassword: db.pgPassword,
        publicOrigin: 'http://127.0.0.1:2080',
        workersCount: 1,
        printEnv: false,
        isDebugModeOn: false,
        isNeedInvite: true,
        genealogyNodeKeySecret: 'test-genealogy-secret',
      ),
    );
    await getIt.allReady(ignorePendingAsyncCreation: true);
    publisher = TrustPublishRepository(getIt<TenturaDb>());
  });

  tearDownAll(() async {
    if (!session.setupComplete) return;
    await getIt.reset();
    await tearDownDisposablePgWriter(session: session);
  });

  setUp(() async {
    await writer.execute('''
TRUNCATE TABLE public.attention_occurrence_recipient,
  public.attention_occurrence, public.invitation, public.invite_genealogy,
  public.person_visible_set_cache, public.beacon, public."user" CASCADE
''');
    for (final (slot, (id, name)) in [
      (_anna, 'Anna'),
      (_boris, 'Boris'),
    ].indexed) {
      await writer.execute(
        Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @name, @key)
'''),
        parameters: {
          'id': id,
          'name': name,
          'key': pgTestPublicKey('fieldinhmr', slot + 1),
        },
      );
    }
    // Anna and Boris have trusted each other for a while: explicit trust,
    // already published to MeritRank.
    await writer.execute(
      Sql.named('''
INSERT INTO public.vote_user (subject, object, amount)
VALUES (@a, @b, 1), (@b, @a, 1)
'''),
      parameters: {'a': _anna, 'b': _boris},
    );
    for (final (src, dst) in [(_anna, _boris), (_boris, _anna)]) {
      await writer.execute(
        Sql.named(
          "SELECT public.mr_put_edge(@src, @dst, 1.0::double precision, '', 0)",
        ),
        parameters: {'src': src, 'dst': dst},
      );
      mrEdges.add((src, dst));
    }
  });

  tearDown(() async {
    for (final (src, dst) in mrEdges) {
      await writer.execute(
        Sql.named('SELECT public.mr_delete_edge(@src, @dst)'),
        parameters: {'src': src, 'dst': dst},
      );
    }
    mrEdges.clear();
  });

  Future<ConstellationFieldSnapshot> readField(String viewer) =>
      getIt<ConstellationFieldRepositoryPort>().readSnapshot(
        viewerId: viewer,
        context: '',
        params: (
          filters: ConstellationFieldMembershipFilters.defaults,
          projection: ConstellationProjection.full,
        ),
      );

  /// Publishes every pending trust change to MeritRank, as the background
  /// trust publisher does.
  Future<void> publishPendingTrust() async {
    final token = await publisher.acquireLease('field-inherit-mr-test');
    expect(token, isNotNull, reason: 'the test owns the publish lease');
    final rows = await publisher.readBatch(100);
    for (final row in rows) {
      await publisher.publish(row);
      mrEdges.add((row.subject, row.object));
    }
    await publisher.sync();
    await publisher.ack(token!, rows);
  }

  Future<List<(String, int)>> membershipsOf(String owner, String person) async {
    final rows = await writer.execute(
      Sql.named('''
SELECT tag_id, source::int FROM public.person_tag_member
 WHERE owner_id = @owner AND person_id = @person
 ORDER BY tag_id, source
'''),
      parameters: {'owner': owner, 'person': person},
    );
    return [for (final r in rows) (r[0]! as String, r[1]! as int)];
  }

  Future<String?> firstSeenOf(String viewer, String peer) async {
    final rows = await writer.execute(
      Sql.named('''
SELECT first_seen_at::text FROM public.person_field_first_seen
 WHERE viewer_id = @viewer AND peer_id = @peer
'''),
      parameters: {'viewer': viewer, 'peer': peer},
    );
    return rows.isEmpty ? null : rows.single.single! as String;
  }

  test(
    "a newcomer reaching the viewer's Field only through their inviter "
    "joins the viewer's tag that holds the inviter, marked inherited",
    () async {
      final earlier = await readField(_anna);
      expect(
        earlier.peers.map((p) => p.id),
        contains(_boris),
        reason: 'precondition: Anna has met Boris on her Field before',
      );
      final tagT = (await getIt<PeopleTagsCase>().create(
        ownerId: _anna,
        name: 'T',
        clientOpId: nextOp(),
      )).id;
      await getIt<PeopleTagsCase>().applyMembers(
        ownerId: _anna,
        clientOpId: nextOp(),
        ops: [
          {
            'tagId': tagT,
            'personId': _boris,
            'op': 'add',
            'source': kPersonTagSourceManual,
          },
        ],
      );

      final invitation = await getIt<InvitationCase>().create(
        userId: _boris,
        addresseeName: 'Nova',
      );
      final nova = (await getIt<AuthCase>().signUp(
        authRequestToken: _signUpRequest(invitation.id),
        displayName: 'Nova',
      )).sub;
      await publishPendingTrust();

      final meets = await readField(_anna);

      final novaPeer = meets.peers.where((p) => p.id == nova);
      expect(
        novaPeer,
        hasLength(1),
        reason: "Nova reaches Anna's Field through Boris",
      );
      expect(novaPeer.single.isNew, isTrue);
      expect(await firstSeenOf(_anna, nova), isNot(anyOf(isNull, '-infinity')));
      expect(await membershipsOf(_anna, nova), [(tagT, _inherited)]);
    },
  );
}
