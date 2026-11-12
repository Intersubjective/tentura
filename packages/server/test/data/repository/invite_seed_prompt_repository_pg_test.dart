@Tags(['pg'])
library;

import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/invite_seed_prompt_repository.dart';
import 'package:tentura_server/domain/capability/capability_evidence_models.dart';

import '../../support/disposable_pg_target.dart';

/// `markAnswered` / `markSkipped` store their state on the existing row and
/// raise when the (inviter, invitee) row is missing.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_INVITE_SEED_PROMPT_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_isp',
  );
  final postgresReachable = await canReachPostgresAdmin(target);
  final skipReason = postgresReachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  const inviterId = 'Uispinviter01';
  const inviteeId = 'Uispinvitee01';
  const otherId = 'Uispother0001';
  const ids = "'$inviterId', '$inviteeId', '$otherId'";

  late DisposablePgWriterSession session;
  late TenturaDb db;
  late InviteSeedPromptRepository repo;

  Future<void> cleanup() async {
    await db.customStatement(
      'DELETE FROM public.invite_seed_prompt_state '
      'WHERE inviter_user_id IN ($ids) OR invitee_user_id IN ($ids)',
    );
    await db.customStatement('DELETE FROM public."user" WHERE id IN ($ids)');
  }

  Future<int> storedState() async {
    final rows = await db
        .customSelect(
          'SELECT state FROM public.invite_seed_prompt_state '
          "WHERE invitee_user_id = '$inviteeId'",
        )
        .get();
    return rows.single.read<int>('state');
  }

  Matcher missingRow(String inviter) => throwsA(
    isA<StateError>().having(
      (e) => e.message,
      'message',
      'invite_seed_prompt_state row missing for inviter=$inviter '
          'invitee=$inviteeId',
    ),
  );

  if (skipReason == false) {
    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      db = openDisposablePgDatabase(target);
      repo = InviteSeedPromptRepository(db);
    });

    setUp(() async {
      await cleanup();
      for (final id in [inviterId, inviteeId, otherId]) {
        await db.customStatement(
          'INSERT INTO public."user" '
          '(id, display_name, public_key, created_at, updated_at) '
          "VALUES ('$id', '$id', 'pk-$id', now(), now())",
        );
      }
    });

    tearDown(cleanup);

    tearDownAll(() async {
      await db.close();
      await tearDownDisposablePgWriter(session: session);
    });
  }

  test(
    'markAnswered stores state 1 on the pending row',
    () async {
      await repo.insertPending(inviterId: inviterId, inviteeId: inviteeId);
      await repo.markAnswered(inviterId: inviterId, inviteeId: inviteeId);
      expect(await storedState(), 1);
      final state = await repo.stateFor(
        inviterId: inviterId,
        inviteeId: inviteeId,
      );
      expect(state?.state, PromptStateValue.answered);
    },
    skip: skipReason,
  );

  test(
    'markSkipped stores state 2 on the pending row',
    () async {
      await repo.insertPending(inviterId: inviterId, inviteeId: inviteeId);
      await repo.markSkipped(inviterId: inviterId, inviteeId: inviteeId);
      expect(await storedState(), 2);
      final state = await repo.stateFor(
        inviterId: inviterId,
        inviteeId: inviteeId,
      );
      expect(state?.state, PromptStateValue.skipped);
    },
    skip: skipReason,
  );

  test(
    'markAnswered raises when the row is missing',
    () async {
      await expectLater(
        repo.markAnswered(inviterId: inviterId, inviteeId: inviteeId),
        missingRow(inviterId),
      );
    },
    skip: skipReason,
  );

  test(
    'markSkipped raises when the row is missing',
    () async {
      await expectLater(
        repo.markSkipped(inviterId: inviterId, inviteeId: inviteeId),
        missingRow(inviterId),
      );
    },
    skip: skipReason,
  );

  test(
    'both raise and leave the row untouched for another inviter',
    () async {
      await repo.insertPending(inviterId: inviterId, inviteeId: inviteeId);
      await expectLater(
        repo.markAnswered(inviterId: otherId, inviteeId: inviteeId),
        missingRow(otherId),
      );
      await expectLater(
        repo.markSkipped(inviterId: otherId, inviteeId: inviteeId),
        missingRow(otherId),
      );
      expect(await storedState(), 0);
    },
    skip: skipReason,
  );
}
