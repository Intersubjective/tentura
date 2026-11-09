@Tags(['pg'])
library;

import 'dart:convert';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/entity/auth_request_intent.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura_server/domain/entity/constellation_field.dart';
import 'package:tentura_server/domain/entity/account_credential_entity.dart';
import 'package:tentura_server/domain/port/constellation_field_repository_port.dart';
import 'package:tentura_server/domain/use_case/auth_case.dart';
import 'package:tentura_server/domain/use_case/credential_auth_case.dart';
import 'package:tentura_server/domain/use_case/invitation_case.dart';
import 'package:tentura_server/domain/use_case/people_tags_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

const _anna = 'Uinhfanna001';
const _boris = 'Uinhfboris01';
const _carol = 'Uinhfcarol01';

/// Membership source of a tag a newcomer inherited from their inviter.
const _inherited = 4;

/// A signed device auth request carrying [invitationId], as the client sends
/// it to sign up through an invite.
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

/// Anna tags Boris, Boris invites Nova, Nova signs up through the invite and
/// later shows up on Anna's Field: the Field read that first meets Nova puts
/// Nova into Anna's tags that hold Boris, marked as inherited. Everything
/// runs through the production use cases and the Field repository the
/// GraphQL Field query uses; nothing about the invite is hand-inserted.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_FIELD_NEWCOMER_INHERITS_TAGS_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_field_inh',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  late DisposablePgWriterSession session;
  late Connection writer;
  var opCounter = 0;

  String nextOp() => 'op-field-inh-${opCounter++}';

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
      (_carol, 'Carol'),
    ].indexed) {
      await writer.execute(
        Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @name, @key)
'''),
        parameters: {
          'id': id,
          'name': name,
          'key': pgTestPublicKey('fieldinh', slot + 1),
        },
      );
    }
    // Anna and Boris know each other; Carol is only Anna's contact.
    await mutualTrust(writer, _anna, _boris);
    await mutualTrust(writer, _anna, _carol);
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

  Future<String> createTag(String owner, String name) async =>
      (await getIt<PeopleTagsCase>().create(
        ownerId: owner,
        name: name,
        clientOpId: nextOp(),
      )).id;

  Future<void> addToTag(String owner, String tagId, String person) =>
      getIt<PeopleTagsCase>().applyMembers(
        ownerId: owner,
        clientOpId: nextOp(),
        ops: [
          {
            'tagId': tagId,
            'personId': person,
            'op': 'add',
            'source': kPersonTagSourceManual,
          },
        ],
      );

  /// Boris invites a newcomer, who signs up through that invite (with a
  /// device key, or with [email] through the email sign-in); returns the
  /// newcomer's id.
  Future<String> borisInvitesNova({String? email}) async {
    final invitation = await getIt<InvitationCase>().create(
      userId: _boris,
      addresseeName: 'Nova',
    );
    if (email != null) {
      return (await getIt<CredentialAuthCase>().resolveOrCreate(
        type: CredentialType.emailOtp,
        identifier: email,
        displayName: 'Nova',
        inviteId: invitation.id,
      )).accountId;
    }
    return (await getIt<AuthCase>().signUp(
      authRequestToken: _signUpRequest(invitation.id),
      displayName: 'Nova',
    )).sub;
  }

  /// Rows of [owner]'s tags holding [person], as `(tag id, source)`.
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

  Future<List<(String, int)>> inheritedMembershipsOf(
    String owner,
    String person,
  ) async => [
    for (final m in await membershipsOf(owner, person))
      if (m.$2 == _inherited) m,
  ];

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

  Future<void> block(String blocker, String blocked) => writer.execute(
    Sql.named(
      'INSERT INTO public.user_block (blocker_id, blocked_id, origin_id) '
      'VALUES (@blocker, @blocked, @blocked)',
    ),
    parameters: {'blocker': blocker, 'blocked': blocked},
  );

  for (final (route, email) in [
    ('device key', null),
    ('email', 'nova-field-inherit@example.test'),
  ]) {
    group(
      'a newcomer signed up by $route and first seen live on the Field',
      () {
        late String tagT;
        late String nova;
        late ConstellationFieldSnapshot meetsNova;

        setUp(() async {
          // Anna has used her Field before Nova exists, so Nova is a live
          // arrival, not part of her initial backfill.
          final earlier = await readField(_anna);
          expect(
            earlier.peers.map((p) => p.id),
            containsAll([_boris, _carol]),
            reason:
                'precondition: Anna already meets her contacts on the Field',
          );
          tagT = await createTag(_anna, 'T');
          await addToTag(_anna, tagT, _boris);

          nova = await borisInvitesNova(email: email);
          // Anna and Nova connect, which puts Nova on Anna's Field.
          await mutualTrust(writer, _anna, nova);

          meetsNova = await readField(_anna);
        });

        test(
          'the invite signup records Boris as the inviter of Nova',
          () async {
            final rows = await writer.execute(
              Sql.named('''
SELECT ancestor_user_id FROM public.invite_genealogy
 WHERE descendant_user_id = @nova
'''),
              parameters: {'nova': nova},
            );
            expect(rows.map((r) => r.single), [_boris]);
          },
        );

        test(
          'meets Nova as a New person with a real first-seen time',
          () async {
            final novaPeer = meetsNova.peers.where((p) => p.id == nova);
            expect(
              novaPeer,
              hasLength(1),
              reason: "Nova is on Anna's Field after they connect",
            );
            expect(novaPeer.single.isNew, isTrue);
            final seenAt = await firstSeenOf(_anna, nova);
            expect(seenAt, isNotNull);
            expect(seenAt, isNot('-infinity'));
          },
        );

        test("puts Nova into Anna's tag that holds Boris, marked inherited, "
            'exactly once', () async {
          expect(await membershipsOf(_anna, nova), [(tagT, _inherited)]);
        });

        test(
          'a later Field read keeps exactly one inherited membership',
          () async {
            final again = await readField(_anna);

            expect(again.peers.map((p) => p.id), contains(nova));
            expect(await membershipsOf(_anna, nova), [(tagT, _inherited)]);
          },
        );
      },
    );
  }

  group('a newcomer first seen live on the Field inherits nothing', () {
    test('when the viewer is the inviter', () async {
      final earlier = await readField(_boris);
      expect(earlier.peers.map((p) => p.id), contains(_anna));
      final borisTag = await createTag(_boris, 'Mine');
      await addToTag(_boris, borisTag, _anna);

      final nova = await borisInvitesNova();
      final meets = await readField(_boris);

      expect(
        meets.peers.map((p) => p.id),
        contains(nova),
        reason: "precondition: Nova is on Boris's Field",
      );
      expect(await firstSeenOf(_boris, nova), isNot('-infinity'));
      expect(await inheritedMembershipsOf(_boris, nova), isEmpty);
    });

    test("when the inviter is in none of the viewer's tags", () async {
      await readField(_anna);
      final tagT = await createTag(_anna, 'T');
      await addToTag(_anna, tagT, _carol);

      final nova = await borisInvitesNova();
      await mutualTrust(writer, _anna, nova);
      final meets = await readField(_anna);

      expect(
        meets.peers.map((p) => p.id),
        contains(nova),
        reason: "precondition: Nova is on Anna's Field",
      );
      expect(await firstSeenOf(_anna, nova), isNot('-infinity'));
      expect(await membershipsOf(_anna, nova), isEmpty);
    });

    for (final (label, blockerOf, blockedOf) in [
      (
        'when the viewer blocked the inviter',
        (String nova) => _anna,
        (String nova) => _boris,
      ),
      (
        'when the inviter blocked the viewer',
        (String nova) => _boris,
        (String nova) => _anna,
      ),
      (
        'when the viewer blocked the newcomer',
        (String nova) => _anna,
        (String nova) => nova,
      ),
      (
        'when the newcomer blocked the viewer',
        (String nova) => nova,
        (String nova) => _anna,
      ),
    ]) {
      test(label, () async {
        await readField(_anna);
        final tagT = await createTag(_anna, 'T');
        await addToTag(_anna, tagT, _boris);
        final nova = await borisInvitesNova();
        await mutualTrust(writer, _anna, nova);
        await block(blockerOf(nova), blockedOf(nova));

        await readField(_anna);

        expect(await inheritedMembershipsOf(_anna, nova), isEmpty);
      });
    }

    test("when Nova is part of the viewer's first-ever Field population "
        '(backfill), now and on a later read', () async {
      final tagT = await createTag(_anna, 'T');
      await addToTag(_anna, tagT, _boris);
      final nova = await borisInvitesNova();
      await mutualTrust(writer, _anna, nova);

      final first = await readField(_anna);

      expect(
        first.peers.map((p) => p.id),
        contains(nova),
        reason: "precondition: Nova is on Anna's very first Field",
      );
      expect(await firstSeenOf(_anna, nova), '-infinity');
      expect(await membershipsOf(_anna, nova), isEmpty);

      await readField(_anna);

      expect(await membershipsOf(_anna, nova), isEmpty);
    });
  });
}

Future<void> mutualTrust(Connection writer, String a, String b) =>
    writer.execute(
      Sql.named('''
INSERT INTO public.vote_user (subject, object, amount)
VALUES (@a, @b, 1), (@b, @a, 1)
ON CONFLICT (subject, object) DO UPDATE SET amount = EXCLUDED.amount
'''),
      parameters: {'a': a, 'b': b},
    );
