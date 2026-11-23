@Tags(['pg'])
library;

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/entity/invite_acceptance.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/use_case/invitation_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

const _issuer = 'Uinviteissuer1';
const _invitee = 'Uinviteguest01';
const _origin = 'http://127.0.0.1:2080';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_INVITATION_ACCEPT_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_invitation_accept',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  late Connection writer;
  late InvitationCase invitations;
  const pair = {'issuer': _issuer, 'invitee': _invitee};

  setUpAll(() async {
    final session = await setUpDisposablePgWriter(target: target);
    addTearDown(() async {
      try {
        await getIt.reset();
      } finally {
        await tearDownDisposablePgWriter(session: session);
      }
    });
    writer = session.writer;
    final db = target.databaseEnv;
    await configureDependencies(
      Env(
        environment: Environment.dev,
        serverUri: Uri.parse(_origin),
        publicOrigin: _origin,
        publicKey: Env.kJwtPublicKey,
        privateKey: Env.kJwtPrivateKey,
        pgHost: db.pgHost,
        pgPort: db.pgPort,
        pgDatabase: db.pgDatabase,
        pgUsername: db.pgUsername,
        pgPassword: db.pgPassword,
        workersCount: 1,
        printEnv: false,
        isDebugModeOn: false,
        isNeedInvite: true,
        genealogyNodeKeySecret: 'test-genealogy-secret',
      ),
    );
    await getIt.allReady(ignorePendingAsyncCreation: true);
    invitations = getIt<InvitationCase>();
  });

  Future<Result> query(String sql, Map<String, Object?> parameters) =>
      writer.execute(Sql.named(sql), parameters: parameters);

  setUp(() async {
    await writer.execute('''
TRUNCATE public.attention_occurrence, public.invitation, public.beacon,
  public."user" CASCADE
''');
    for (final (index, id) in [_issuer, _invitee].indexed) {
      await query(
        '''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @name, @key)
''',
        {
          'id': id,
          'name': id == _issuer ? 'Inviter' : 'Invitee',
          'key': pgTestPublicKey('invitationaccept', index + 1),
        },
      );
    }
  });

  Future<String> createRequest() async =>
      (await getIt<BeaconRepositoryPort>().createBeacon(
        authorId: _issuer,
        title: 'Help with the community garden',
        description: 'Looking for help planting seedlings',
        kind: BeaconKind.request,
      )).id;

  Future<String> createInvite({String? beaconId}) async =>
      (await invitations.create(
        userId: _issuer,
        addresseeName: 'Guest',
        beaconId: beaconId,
      )).id;

  Future<void> backdateInvite(String id) async {
    await query(
      '''
UPDATE public.invitation SET created_at = now() - interval '8 days'
WHERE id = @id
''',
      {'id': id},
    );
  }

  Future<ResultRow> readClaim(String id) async => (await query(
    '''
SELECT invited_id, accepted_at FROM public.invitation WHERE id = @id
''',
    {'id': id},
  )).single;

  Future<Result> requestForwards(String beaconId) => query(
    '''
SELECT id FROM public.beacon_forward_edge
WHERE beacon_id = @beacon AND sender_id = @issuer AND recipient_id = @invitee
''',
    {...pair, 'beacon': beaconId},
  );

  Future<Result> friendshipVotes() => query(
    '''
SELECT subject, object, amount FROM public.vote_user
WHERE (subject = @issuer AND object = @invitee)
   OR (subject = @invitee AND object = @issuer)
''',
    pair,
  );

  Future<Result> friendshipEvents(String id) => query(
    '''
SELECT source_event_key FROM public.attention_occurrence
WHERE source_event_key IN (@accepted, @mutual)
''',
    {'accepted': 'invitation:$id:accepted', 'mutual': 'invitation:$id:mutual'},
  );

  Future<InviteAcceptance> accept(String id) =>
      invitations.accept(invitationId: id, userId: _invitee);

  // The exception exposes the requested ID through its public description.
  Matcher missingInvite(String id) => isA<IdNotFoundException>().having(
    (error) => error.description,
    'description',
    'Id not found: [$id]',
  );

  Future<String> acceptFreshRequestInvite() async {
    final requestId = await createRequest();
    final inviteId = await createInvite(beaconId: requestId);
    expect(await friendshipVotes(), isEmpty);

    expect(await accept(inviteId), InviteAcceptance.accepted);

    final claim = await readClaim(inviteId);
    expect(claim[0], _invitee);
    expect(claim[1], isNotNull);
    expect(await requestForwards(requestId), hasLength(1));
    return inviteId;
  }

  group('Accepting an invitation as an existing account', () {
    test(
      'a fresh Request invite grants admission without friendship votes',
      () async {
        await acceptFreshRequestInvite();

        expect(await friendshipVotes(), isEmpty);
      },
    );

    test(
      'a fresh Request invite grants admission without friendship notifications',
      () async {
        final inviteId = await acceptFreshRequestInvite();

        expect(await friendshipEvents(inviteId), isEmpty);
      },
    );

    test('only a fresh ordinary invite can create friendship', () async {
      final expiredId = await createInvite();
      await backdateInvite(expiredId);
      final refusal = throwsA(missingInvite(expiredId));
      await expectLater(
        invitations.acceptAsExisting(code: expiredId, userId: _invitee),
        refusal,
      );

      try {
        await expectLater(accept(expiredId), refusal);
      } finally {
        expect(await readClaim(expiredId), [null, null]);
        expect(await friendshipVotes(), isEmpty);

        final freshId = await createInvite();
        expect(await accept(freshId), InviteAcceptance.accepted);
        expect(
          await friendshipVotes(),
          unorderedEquals([
            [_issuer, _invitee, 1],
            [_invitee, _issuer, 1],
          ]),
        );
      }
    });

    test('an expired Request invite is refused without admission', () async {
      final requestId = await createRequest();
      final inviteId = await createInvite(beaconId: requestId);
      await backdateInvite(inviteId);

      try {
        await expectLater(accept(inviteId), throwsA(missingInvite(inviteId)));
      } finally {
        expect(await readClaim(inviteId), [null, null]);
        expect(await requestForwards(requestId), isEmpty);
      }
    });
  });
}
