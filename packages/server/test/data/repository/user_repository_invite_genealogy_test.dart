@Tags(['pg'])
library;

import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/data/repository/invitation_repository.dart';
import 'package:tentura_server/data/repository/invite_genealogy_repository.dart';
import 'package:tentura_server/data/repository/invite_seed_prompt_repository.dart';
import 'package:tentura_server/data/repository/user_block_repository.dart';
import 'package:tentura_server/data/repository/mock/trust_evidence_repository_mock.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/env.dart';

Future<void> main() async {
  final target = _DisposablePgTarget.fromEnvironment();
  final reachable = await _canConnect(target.adminEnv);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  late Connection writer;
  late TenturaDb db;
  late UserRepository repo;
  late InvitationRepository invitationRepo;
  late Env env;

  const ancestorId = 'Usigngeneanc01';
  const invitationId = 'Isigngene001';
  const ancestorPublicKey = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const descendantPublicKey = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

  String? descendantId;

  // Extra fixture ids used only by the bindMutual (handshake-accept) tests
  // below — created/cleaned per-test, independent of the createInvited
  // fixtures above.
  final extraUserIds = <String>[];
  final extraInvitationIds = <String>[];

  if (skipReason == false) {
    setUpAll(() async {
      await target.recreate();
      writer = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await writer.execute('SET check_function_bodies = false');
      await migrateDbSchema(writer);
      env = target.databaseEnv;
      db = TenturaDb(env);
      repo = UserRepository(
        env,
        db,
        const TrustEvidenceRepositoryMock(),
        InviteGenealogyRepository(env, db, UserBlockRepository(env, db)),
        InviteSeedPromptRepository(db),
      );
      invitationRepo = InvitationRepository(db);
    });

    tearDownAll(() async {
      await db.close();
      await writer.close();
      await target.drop();
    });

    setUp(() async {
      await db.customStatement(
        '''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES (
  '$ancestorId',
  'Ancestor',
  '$ancestorPublicKey',
  '2026-01-01T00:00:00Z',
  '2026-01-01T00:00:00Z'
)
ON CONFLICT (id) DO UPDATE SET
  display_name = EXCLUDED.display_name,
  public_key = EXCLUDED.public_key,
  created_at = EXCLUDED.created_at,
  updated_at = EXCLUDED.updated_at
''',
      );
      await db.customStatement(
        '''
INSERT INTO public.invitation (
  id,
  user_id,
  addressee_name,
  created_at,
  updated_at
) VALUES (
  '$invitationId',
  '$ancestorId',
  'Invitee',
  now(),
  now()
)
ON CONFLICT (id) DO UPDATE SET
  user_id = EXCLUDED.user_id,
  invited_id = NULL,
  addressee_name = EXCLUDED.addressee_name,
  created_at = now(),
  updated_at = now()
''',
      );
    });

    tearDown(() async {
      await db.customStatement(
        "DELETE FROM public.invite_genealogy WHERE invitation_id = '$invitationId'",
      );
      if (descendantId != null) {
        await db.customStatement(
          '''DELETE FROM public.vote_user WHERE subject IN ('$descendantId', '$ancestorId') OR object IN ('$descendantId', '$ancestorId')''',
        );
        await db.customStatement(
          '''DELETE FROM public.user_contact WHERE viewer_id = '$ancestorId' AND subject_id = '$descendantId' ''',
        );
        await db.customStatement(
          '''DELETE FROM public.account_credential WHERE account_id = '$descendantId' ''',
        );
        await db.customStatement(
          '''DELETE FROM public."user" WHERE id = '$descendantId' ''',
        );
        descendantId = null;
      }
      await db.customStatement(
        "DELETE FROM public.invitation WHERE id = '$invitationId'",
      );
      await db.customStatement(
        '''DELETE FROM public."user" WHERE id = '$ancestorId' ''',
      );

      for (final id in extraInvitationIds) {
        await db.customStatement(
          "DELETE FROM public.invitation WHERE id = '$id'",
        );
      }
      extraInvitationIds.clear();
      if (extraUserIds.isNotEmpty) {
        final ids = extraUserIds.map((id) => "'$id'").join(', ');
        await db.customStatement(
          'DELETE FROM public.vote_user WHERE subject IN ($ids) OR object IN ($ids)',
        );
        await db.customStatement(
          'DELETE FROM public.user_contact WHERE viewer_id IN ($ids) OR subject_id IN ($ids)',
        );
        await db.customStatement('DELETE FROM public."user" WHERE id IN ($ids)');
      }
      extraUserIds.clear();
    });
  }

  /// Inserts a standalone existing user (not created via createInvited) —
  /// used as the acceptor in bindMutual tests. Cleaned up by [tearDown].
  Future<String> insertExtraUser(String id, String publicKey) async {
    await db.customStatement(
      '''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ('$id', 'Extra $id', '$publicKey', now(), now())
ON CONFLICT (id) DO NOTHING
''',
    );
    extraUserIds.add(id);
    return id;
  }

  /// Inserts a standalone pending invitation from [issuerId] — used by
  /// bindMutual tests that need a second, independent invite. Cleaned up by
  /// [tearDown].
  Future<String> insertExtraInvitation(String id, String issuerId) async {
    await db.customStatement(
      '''
INSERT INTO public.invitation (id, user_id, addressee_name, created_at, updated_at)
VALUES ('$id', '$issuerId', 'Invitee', now(), now())
ON CONFLICT (id) DO NOTHING
''',
    );
    extraInvitationIds.add(id);
    return id;
  }

  test('createInvited appends invite_genealogy row in same transaction', () async {
    if (skipReason != false) {
      return;
    }
    final descendant = await repo.createInvited(
      invitationId: invitationId,
      publicKey: descendantPublicKey,
      displayName: 'Descendant',
    );
    descendantId = descendant.id;

    final rows = await db.customSelect(
      '''
SELECT ancestor_user_id, descendant_user_id, invitation_id
FROM public.invite_genealogy
WHERE invitation_id = '$invitationId'
''',
    ).get();

    expect(rows, hasLength(1));
    expect(rows.single.read<String>('ancestor_user_id'), ancestorId);
    expect(rows.single.read<String>('descendant_user_id'), descendantId);
  }, skip: skipReason);

  group('UserRepository.bindMutual (existing-user handshake accept)', () {
    test(
      'persists the invitation with existing_account origin and '
      'accepted_at, and does not delete the row',
      () async {
        final acceptorId = await insertExtraUser(
          'Ubindmutual0001',
          'c' * 44,
        );

        final accepted = await repo.bindMutual(
          invitationId: invitationId,
          userId: acceptorId,
        );
        expect(accepted, isTrue);

        final rows = await db.customSelect(
          '''
SELECT invited_id, invite_origin, accepted_at
FROM public.invitation
WHERE id = '$invitationId'
''',
        ).get();

        expect(
          rows,
          hasLength(1),
          reason: 'the row must persist, not be deleted',
        );
        final row = rows.single;
        expect(row.read<String>('invited_id'), acceptorId);
        expect(row.read<String>('invite_origin'), 'existing_account');
        expect(row.data['accepted_at'], isNotNull);
      },
      skip: skipReason,
    );

    test(
      'lets the same existing user accept invites from two different '
      'issuers (the invited_id UNIQUE constraint was dropped for this)',
      () async {
        final acceptorId = await insertExtraUser('Ubindmutual0002', 'd' * 44);
        final secondIssuerId = await insertExtraUser(
          'Ubindmutual0003',
          'e' * 44,
        );
        final secondInvitationId = await insertExtraInvitation(
          'Ibindmutual002',
          secondIssuerId,
        );

        final first = await repo.bindMutual(
          invitationId: invitationId,
          userId: acceptorId,
        );
        final second = await repo.bindMutual(
          invitationId: secondInvitationId,
          userId: acceptorId,
        );

        expect(first, isTrue);
        expect(
          second,
          isTrue,
          reason:
              'one user must be able to accept invites from multiple '
              'different inviters once invited_id is no longer UNIQUE',
        );

        final rows = await db.customSelect(
          '''SELECT id FROM public.invitation WHERE invited_id = '$acceptorId' ''',
        ).get();
        expect(
          rows.map((r) => r.read<String>('id')).toSet(),
          {invitationId, secondInvitationId},
        );
      },
      skip: skipReason,
    );

    test(
      'throws when re-accepting an already-consumed invitation, and does '
      'not overwrite the original acceptor',
      () async {
        final firstAcceptorId = await insertExtraUser(
          'Ubindmutual0004',
          'f' * 44,
        );
        final secondAcceptorId = await insertExtraUser(
          'Ubindmutual0005',
          'g' * 44,
        );

        final first = await repo.bindMutual(
          invitationId: invitationId,
          userId: firstAcceptorId,
        );
        expect(first, isTrue);

        await expectLater(
          repo.bindMutual(
            invitationId: invitationId,
            userId: secondAcceptorId,
          ),
          throwsA(isA<InvitationWrongException>()),
        );

        final rows = await db.customSelect(
          "SELECT invited_id FROM public.invitation WHERE id = '$invitationId'",
        ).get();
        expect(rows.single.read<String>('invited_id'), firstAcceptorId);
      },
      skip: skipReason,
    );

    test(
      'is race-safe: of two concurrent accepts on the same invitation, '
      'exactly one wins and only the winner gets contact/trust side effects',
      () async {
        final acceptorA = await insertExtraUser('Ubindmutual0006', 'h' * 44);
        final acceptorB = await insertExtraUser('Ubindmutual0007', 'i' * 44);

        // A second, independent connection/repository so the two accepts
        // race as genuinely concurrent transactions, not queued on one
        // connection.
        final db2 = TenturaDb(env);
        final repo2 = UserRepository(
          env,
          db2,
          const TrustEvidenceRepositoryMock(),
          InviteGenealogyRepository(env, db2, UserBlockRepository(env, db2)),
          InviteSeedPromptRepository(db2),
        );

        try {
          final results = await Future.wait<Object?>([
            repo
                .bindMutual(invitationId: invitationId, userId: acceptorA)
                .then<Object?>((v) => v)
                .catchError((Object e) => e),
            repo2
                .bindMutual(invitationId: invitationId, userId: acceptorB)
                .then<Object?>((v) => v)
                .catchError((Object e) => e),
          ]);

          final wins = results.whereType<bool>().where((v) => v).length;
          expect(wins, 1, reason: 'exactly one concurrent acceptor must win');

          final rows = await db.customSelect(
            "SELECT invited_id FROM public.invitation WHERE id = '$invitationId'",
          ).get();
          expect(rows, hasLength(1));
          final winnerId = rows.single.read<String>('invited_id');
          expect({acceptorA, acceptorB}, contains(winnerId));
          final loserId = winnerId == acceptorA ? acceptorB : acceptorA;

          // The loser must not have picked up a fabricated mutual-trust
          // edge for a claim that didn't actually win.
          final loserVotes = await db.customSelect(
            '''
SELECT count(*) AS n FROM public.vote_user
WHERE subject = '$loserId' OR object = '$loserId'
''',
          ).getSingle();
          expect(loserVotes.read<int>('n'), 0);
        } finally {
          await db2.close();
        }
      },
      skip: skipReason,
    );
  });

  group('InvitationRepository.deleteById guard', () {
    test(
      'does not delete an invitation that has already been accepted',
      () async {
        final acceptorId = await insertExtraUser('Ubindmutual0008', 'j' * 44);
        final accepted = await repo.bindMutual(
          invitationId: invitationId,
          userId: acceptorId,
        );
        expect(accepted, isTrue);

        final deleted = await invitationRepo.deleteById(
          invitationId: invitationId,
          userId: ancestorId,
        );
        expect(deleted, isFalse);

        final rows = await db.customSelect(
          "SELECT id FROM public.invitation WHERE id = '$invitationId'",
        ).get();
        expect(
          rows,
          hasLength(1),
          reason: 'an accepted invitation must survive a cancel attempt',
        );
      },
      skip: skipReason,
    );
  });
}

Future<bool> _canConnect(Env env) async {
  try {
    final connection = await Connection.open(
      env.pgEndpoint,
      settings: env.pgEndpointSettings,
    );
    await connection.close();
    return true;
  } on Object {
    return false;
  }
}

class _DisposablePgTarget {
  const _DisposablePgTarget({
    required this.adminEnv,
    required this.databaseEnv,
    required this.databaseName,
  });

  factory _DisposablePgTarget.fromEnvironment() {
    final host = Platform.environment['POSTGRES_HOST'] ?? '127.0.0.1';
    final port =
        int.tryParse(Platform.environment['POSTGRES_PORT'] ?? '') ?? 5432;
    final username = Platform.environment['POSTGRES_USERNAME'] ?? 'postgres';
    final password = Platform.environment['POSTGRES_PASSWORD'] ?? 'password';
    final adminDatabase =
        Platform.environment['POSTGRES_ADMIN_DBNAME'] ?? 'postgres';
    final databaseName =
        Platform.environment['TENTURA_INVITE_GENEALOGY_TEST_DB'] ??
        'tentura_test_invite_genealogy_${pid}_${DateTime.timestamp().microsecondsSinceEpoch}';
    if (!RegExp(r'^tentura_test_[a-z0-9_]+$').hasMatch(databaseName) ||
        databaseName.length > 63) {
      throw ArgumentError.value(
        databaseName,
        'TENTURA_INVITE_GENEALOGY_TEST_DB',
        'must match tentura_test_[a-z0-9_]+ and be at most 63 characters',
      );
    }

    Env envFor(String database) => Env(
      environment: Environment.test,
      pgHost: host,
      pgPort: port,
      pgDatabase: database,
      pgUsername: username,
      pgPassword: password,
      printEnv: false,
      isDebugModeOn: false,
      genealogyNodeKeySecret: 'test-genealogy-secret',
    );

    return _DisposablePgTarget(
      adminEnv: envFor(adminDatabase),
      databaseEnv: envFor(databaseName),
      databaseName: databaseName,
    );
  }

  final Env adminEnv;
  final Env databaseEnv;
  final String databaseName;

  Future<void> recreate() async {
    final connection = await Connection.open(
      adminEnv.pgEndpoint,
      settings: adminEnv.pgEndpointSettings,
    );
    try {
      await connection.execute(
        'DROP DATABASE IF EXISTS "$databaseName" WITH (FORCE)',
      );
      await connection.execute('CREATE DATABASE "$databaseName"');
    } finally {
      await connection.close();
    }
  }

  Future<void> drop() async {
    final connection = await Connection.open(
      adminEnv.pgEndpoint,
      settings: adminEnv.pgEndpointSettings,
    );
    try {
      await connection.execute(
        'DROP DATABASE IF EXISTS "$databaseName" WITH (FORCE)',
      );
    } finally {
      await connection.close();
    }
  }
}
