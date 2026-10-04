@Tags(['pg'])
library;

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_outbox_repository.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/domain/use_case/beacon_lifecycle_effects_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/domain/use_case/user_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';
import '../../support/user_erasure_test_stack.dart';

const _author = 'Uerasefrauthor1';
const _erased = 'Uerasefrerased1';
const _kept = 'Uerasefrkept001';
const _users = [_author, _erased, _kept];

const _post = 'Berasefrpost001';
const _erasedMessage = 'Rerasefrmsg0001';

/// Erasing an account (`UserCase.deleteById`, the production erasure path)
/// removes the account's first-response claims on Posts, whether the claim was
/// won by a message or a reaction, and leaves every other member's claim
/// alone. Real repositories over a disposable Postgres.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_POST_FIRST_RESPONSE_ERASURE_TEST_DB',
    defaultNamePrefix: 'tentura_test_post_first_resp_erase',
  );

  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  group('Account erasure and Post first-response claims', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb database;
    late UserCase userCase;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      database = openDisposablePgDatabase(target);
      final env = Env(environment: Environment.test);
      final logger = Logger('PostFirstResponseErasurePgTest');
      userCase = buildUserErasureTestStack(
        db: database,
        userRepository: buildDefaultUserRepository(database),
        lifecycleEffects: BeaconLifecycleEffectsCase(
          BeaconHierarchyOutboxRepository(database),
          env: env,
          logger: logger,
        ),
        attention: TransactionalAttentionCase(
          MutatingUnitOfWork(database),
          AttentionDispatchRepository(database, logger),
        ),
        logger: logger,
      ).userCase;
    });

    setUp(() async => _seed(writer));

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session, drift: database);
    });

    Future<List<String>> claimants() async => [
      for (final row in await writer.execute('''
SELECT user_id FROM public.post_first_response
WHERE beacon_id = '$_post' ORDER BY user_id
'''))
        row.single! as String,
    ];

    test('removes the erased account\'s claim and keeps other members\'', () async {
      expect(await claimants(), [_erased, _kept]);

      expect(await userCase.deleteById(id: _erased), isTrue);

      expect(await claimants(), [_kept]);
    });

    test('removes a claim won by a message whose text erasure also deletes',
        () async {
      await writer.execute('''
INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body)
VALUES ('$_erasedMessage', '$_post', '$_erased', 'Count me in')
''');
      await writer.execute('''
UPDATE public.post_first_response SET source_kind = 1, source_id = '$_erasedMessage'
WHERE beacon_id = '$_post' AND user_id = '$_erased'
''');

      await userCase.deleteById(id: _erased);

      expect(await claimants(), [_kept]);
      final messages = await writer.execute('''
SELECT count(*)::int FROM public.beacon_room_message WHERE id = '$_erasedMessage'
''');
      expect(messages.single.single, 0);
    });

    test('leaves the erased account with no claim on any Post', () async {
      await userCase.deleteById(id: _erased);

      final rows = await writer.execute('''
SELECT count(*)::int FROM public.post_first_response WHERE user_id = '$_erased'
''');
      expect(rows.single.single, 0);
    });
  });
}

Future<void> _seed(Connection writer) async {
  await writer.execute('''
TRUNCATE TABLE
  public.notification_outbox,
  public.attention_occurrence_recipient,
  public.attention_occurrence,
  public.inbox_item,
  public.beacon_room_message,
  public.beacon_forward_edge,
  public.beacon_participant,
  public.beacon,
  public."user"
CASCADE
''');
  for (var i = 0; i < _users.length; i++) {
    await writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
      parameters: {'id': _users[i], 'key': pgTestPublicKey('erasefr', i + 1)},
    );
  }
  await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, forward_policy,
   is_discoverable, published_at)
VALUES ('$_post', '$_author', '', '', 0, 1, 1, false, now())
''');
  await writer.execute('''
INSERT INTO public.beacon_forward_edge (id, beacon_id, sender_id, recipient_id)
VALUES
  ('Ferasefredge001', '$_post', '$_author', '$_erased'),
  ('Ferasefredge002', '$_post', '$_author', '$_kept')
''');
  // Claims are written by the real claim function: one by message, one by
  // reaction.
  await writer.execute(
    "SELECT public.post_claim_first_response('$_post', '$_erased', 2::smallint, 'Eerasefrreact01')",
  );
  await writer.execute(
    "SELECT public.post_claim_first_response('$_post', '$_kept', 1::smallint, 'Rerasefrkept001')",
  );
}
