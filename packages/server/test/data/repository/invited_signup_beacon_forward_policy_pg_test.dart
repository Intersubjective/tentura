@Tags(['pg'])
library;

import 'dart:async';

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/domain/entity/account_credential_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

const _authorId = 'Usignupauth01';
const _helperId = 'Usignuphelp01';
const _post = 'Bsignuppost01';
const _request = 'Bsignupreq001';
const _invitation = 'Isignupinv001';
const _newcomerName = 'Newcomer';

const _statusOpen = 0;
const _statusCancelled = 1;
const _statusDeleted = 2;
const _kindRequest = 0;
const _kindPost = 1;
const _policyClosed = 0;
const _policyOpen = 1;

final _refusal = anyOf(
  isA<UnauthorizedException>(),
  isA<IdNotFoundException>(),
);

/// Signing up through an invite that carries a beacon forwards that beacon to
/// the new account. Both signup paths must apply the beacon's forward policy
/// to the invite's issuer, and for a Post must do it under the Post lock.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_INVITED_SIGNUP_POLICY_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_signup_policy',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  late DisposablePgWriterSession session;
  late Connection writer;
  late UserRepositoryPort users;

  setUpAll(() async {
    session = await setUpDisposablePgWriter(target: target);
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
        genealogyNodeKeySecret: 'test-genealogy-secret',
      ),
    );
    await getIt.allReady(ignorePendingAsyncCreation: true);
    users = getIt<UserRepositoryPort>();
  });

  tearDownAll(() async {
    await getIt.reset();
    await tearDownDisposablePgWriter(session: session);
  });

  setUp(() async {
    await writer.execute('''
TRUNCATE TABLE public.invitation, public.beacon_forward_edge,
  public.beacon, public."user" CASCADE
''');
    var slot = 1;
    for (final id in [_authorId, _helperId]) {
      await writer.execute(
        Sql.named(
          'INSERT INTO public."user" (id, display_name, public_key) '
          'VALUES (@id, @id, @key)',
        ),
        parameters: {'id': id, 'key': pgTestPublicKey('signup', slot++)},
      );
    }
  });

  Future<void> insertBeacon({
    required String id,
    required int kind,
    required int policy,
    int status = _statusOpen,
  }) => writer.execute(
    Sql.named(
      'INSERT INTO public.beacon '
      '(id, user_id, title, description, status, kind, forward_policy, '
      'is_discoverable, published_at) '
      'VALUES (@id, @author, @title, @description, @status, @kind, '
      '@policy, false, now())',
    ),
    parameters: {
      'id': id,
      'author': _authorId,
      'title': kind == _kindPost ? '' : 'Request title',
      'description': kind == _kindPost ? '' : 'Request description',
      'status': status,
      'kind': kind,
      'policy': policy,
    },
  );

  Future<void> insertInvitation({
    required String beaconId,
    required String issuerId,
  }) => writer.execute(
    Sql.named(
      'INSERT INTO public.invitation '
      '(id, user_id, beacon_id, addressee_name, created_at, updated_at) '
      'VALUES (@id, @issuer, @beacon, @name, now(), now())',
    ),
    parameters: {
      'id': _invitation,
      'issuer': issuerId,
      'beacon': beaconId,
      'name': _newcomerName,
    },
  );

  Future<int> scalar(String sql) async =>
      (await writer.execute(sql)).single.single! as int;

  Future<int> newcomerCount() => scalar(
    "SELECT count(*) FROM public.\"user\" WHERE display_name = '$_newcomerName'",
  );

  Future<int> forwardEdgeCount(String beaconId, String senderId) => scalar(
    'SELECT count(*) FROM public.beacon_forward_edge '
    "WHERE beacon_id = '$beaconId' AND sender_id = '$senderId' "
    'AND cancelled_at IS NULL',
  );

  Future<int> consumedInvitationCount() => scalar(
    'SELECT count(*) FROM public.invitation '
    "WHERE id = '$_invitation' AND invited_id IS NOT NULL",
  );

  final paths = <({String name, Future<void> Function() signUp})>[
    (
      name: 'createInvited',
      signUp: () => users.createInvited(
        invitationId: _invitation,
        publicKey: pgTestPublicKey('signup', 7),
        displayName: _newcomerName,
      ),
    ),
    (
      name: 'createInvitedWithCredential',
      signUp: () => users.createInvitedWithCredential(
        invitationId: _invitation,
        type: CredentialType.ed25519Device,
        identifier: pgTestPublicKey('signup', 8),
        displayName: _newcomerName,
      ),
    ),
  ];

  Future<void> expectNothingMaterialized(
    String beaconId,
    String senderId,
  ) async {
    expect(await newcomerCount(), 0, reason: 'no account was created');
    expect(await consumedInvitationCount(), 0, reason: 'invite stays unused');
    expect(await forwardEdgeCount(beaconId, senderId), 0);
  }

  for (final path in paths) {
    group('${path.name} with a beacon invite', () {
      test('refuses a non-author issuer of a Post with closed forwarding '
          'and creates no edge', () async {
        await insertBeacon(
          id: _post,
          kind: _kindPost,
          policy: _policyClosed,
        );
        await insertInvitation(beaconId: _post, issuerId: _helperId);

        await expectLater(path.signUp(), throwsA(_refusal));

        await expectNothingMaterialized(_post, _helperId);
      });

      test(
        'forwards the Post from its author when forwarding is closed',
        () async {
          await insertBeacon(
            id: _post,
            kind: _kindPost,
            policy: _policyClosed,
          );
          await insertInvitation(beaconId: _post, issuerId: _authorId);

          await path.signUp();

          expect(await newcomerCount(), 1);
          expect(await forwardEdgeCount(_post, _authorId), 1);
        },
      );

      test('forwards an open-forwarding Post from a non-author', () async {
        await insertBeacon(id: _post, kind: _kindPost, policy: _policyOpen);
        await insertInvitation(beaconId: _post, issuerId: _helperId);

        await path.signUp();

        expect(await newcomerCount(), 1);
        expect(await forwardEdgeCount(_post, _helperId), 1);
      });

      test('forwards an open Request from a non-author', () async {
        await insertBeacon(
          id: _request,
          kind: _kindRequest,
          policy: _policyOpen,
        );
        await insertInvitation(beaconId: _request, issuerId: _helperId);

        await path.signUp();

        expect(await newcomerCount(), 1);
        expect(await forwardEdgeCount(_request, _helperId), 1);
      });

      test(
        'refuses a Request that is no longer open and creates no edge',
        () async {
          await insertBeacon(
            id: _request,
            kind: _kindRequest,
            policy: _policyOpen,
            status: _statusCancelled,
          );
          await insertInvitation(beaconId: _request, issuerId: _helperId);

          await expectLater(path.signUp(), throwsA(_refusal));

          await expectNothingMaterialized(_request, _helperId);
        },
      );

      test(
        'refuses a Post that is no longer open and creates no edge',
        () async {
          await insertBeacon(
            id: _post,
            kind: _kindPost,
            policy: _policyOpen,
            status: _statusDeleted,
          );
          await insertInvitation(beaconId: _post, issuerId: _authorId);

          await expectLater(path.signUp(), throwsA(_refusal));

          await expectNothingMaterialized(_post, _authorId);
        },
      );

      test('waits for the Post lock and then judges the Post as it stands, '
          'when the Post is deleted while the lock is held', () async {
        await insertBeacon(id: _post, kind: _kindPost, policy: _policyOpen);
        await insertInvitation(beaconId: _post, issuerId: _authorId);

        final holder = await Connection.open(
          target.databaseEnv.pgEndpoint,
          settings: target.databaseEnv.pgEndpointSettings,
        );
        addTearDown(holder.close);
        await holder.execute('BEGIN');
        await holder.execute(
          "SELECT pg_advisory_xact_lock(hashtextextended('$_post', 4242))",
        );
        await holder.execute(
          'UPDATE public.beacon SET status = $_statusDeleted '
          "WHERE id = '$_post'",
        );

        var finished = false;
        Object? failure;
        final signUp = path
            .signUp()
            .then<void>((_) {})
            .catchError((Object e) {
              failure = e;
            })
            .whenComplete(() => finished = true);
        await Future<void>.delayed(const Duration(milliseconds: 800));
        expect(finished, isFalse, reason: 'sign-up waits for the Post lock');

        await holder.execute('COMMIT');
        await signUp.timeout(const Duration(seconds: 15));

        expect(failure, _refusal);
        await expectNothingMaterialized(_post, _authorId);
      });
    });
  }
}
