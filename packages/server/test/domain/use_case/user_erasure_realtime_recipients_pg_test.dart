@Tags(['pg', 'multi-connection'])
library;

import 'dart:convert';

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/data/database/tentura_db.dart' show TenturaDb;
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_outbox_repository.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/domain/use_case/beacon_lifecycle_effects_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_notification_recorder.dart';
import '../../support/pg_test_public_keys.dart';
import '../../support/user_erasure_test_stack.dart';

const _survivor = 'Ue00000000001';
const _erasedMember = 'Ue00000000002';
const _forwardRecipient = 'Ue00000000003';
const _erasedAuthor = 'Ue00000000004';
const _admittedMember = 'Ue00000000005';
const _inboxOwner = 'Ue00000000006';
const _bystander = 'Ue00000000007';

const _survivingRequest = 'Be00000000001';
const _publishedRequest = 'Be00000000002';
const _erasedDraft = 'Be00000000004';
const _emptyDraft = 'Be00000000003';

const _affectedEntities = {'participant', 'forward', 'inbox_item'};

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_ERASURE_REALTIME_RECIPIENTS_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_erasure_realtime',
  );
  final skip = await pgSkipReason(target);
  DisposablePgWriterSession? session;
  late TenturaDb db;
  late Connection writer;

  setUpAll(() async {
    final pg = await setUpDisposablePgWriter(target: target);
    writer = pg.writer;
    db = openDisposablePgDatabase(target);
    session = pg;
    await _seed(writer);
  });

  tearDownAll(() async {
    if (session case final pg?) {
      await tearDownDisposablePgWriter(session: pg, drift: db);
    }
  });

  test(
    'erasure refreshes surviving Request participants, forward recipients '
    'and inbox owners affected by removed rows',
    () async {
      final logger = Logger('UserErasureRealtimeRecipientsPgTest');
      final erasure = buildUserErasureTestStack(
        db: db,
        userRepository: buildDefaultUserRepository(db),
        lifecycleEffects: BeaconLifecycleEffectsCase(
          BeaconHierarchyOutboxRepository(db),
          env: Env(environment: Environment.test),
          logger: logger,
        ),
        attention: TransactionalAttentionCase(
          MutatingUnitOfWork(db),
          AttentionDispatchRepository(db, logger),
        ),
      ).erasureCase;

      final listener = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      addTearDown(listener.close);
      await listener.execute('LISTEN entity_changes');
      final recorder = PgNotificationRecorder(
        listener.channels['entity_changes'],
      );
      addTearDown(recorder.cancel);

      Future<void> barrier(String token) => writer.execute(
        Sql.named("SELECT pg_notify('entity_changes', @payload)"),
        parameters: {
          'payload': jsonEncode({'entity': 'barrier', 'id': token}),
        },
      );

      Future<List<Map<String, dynamic>>> record(
        Future<void> Function() write,
      ) async {
        await recorder.drain(sendBarrier: barrier);
        // The use case awaits its commits before returning.
        await write();
        await recorder.flush(sendBarrier: barrier);
        return List.of(recorder.messages);
      }

      final memberHints = await record(() async {
        expect(await erasure.deleteById(id: _erasedMember), isTrue);
      });
      final survivingRequest = await writer.execute(
        "SELECT user_id, status FROM public.beacon WHERE id = '$_survivingRequest'",
      );
      expect(survivingRequest.single.toList(), [
        _survivor,
        BeaconStatus.open.smallintValue,
      ]);
      expect(
        memberHints.where((hint) => _recipients(hint).contains(_bystander)),
        isEmpty,
        reason: 'Erasing a member must send no hints to the bystander.',
      );

      final authorHints = await record(() async {
        expect(await erasure.deleteById(id: _erasedAuthor), isTrue);
      });
      final tombstone = await writer.execute(
        "SELECT status, user_id FROM public.beacon WHERE id = '$_publishedRequest'",
      );
      expect(tombstone.single.toList(), [
        BeaconStatus.deleted.smallintValue,
        null,
      ]);
      expect(
        await writer.execute(
          "SELECT id FROM public.beacon WHERE id = '$_erasedDraft'",
        ),
        isEmpty,
      );
      expect(
        authorHints.where((hint) => _recipients(hint).contains(_bystander)),
        isEmpty,
        reason: 'Erasing an author must send no hints to the bystander.',
      );

      final emptyDraftHints = await record(() async {
        final deleted = await writer.execute(
          "DELETE FROM public.beacon WHERE id = '$_emptyDraft'",
        );
        expect(deleted.affectedRows, 1);
      });
      expect(_deleteHints(emptyDraftHints, _emptyDraft), isEmpty);

      expect(
        {
          _survivingRequest: _deleteRecipients(
            memberHints,
            _survivingRequest,
            erasedUser: _erasedMember,
          ),
          _publishedRequest: _deleteRecipients(
            authorHints,
            _publishedRequest,
            erasedUser: _erasedAuthor,
          ),
          _erasedDraft: _deleteRecipients(
            authorHints,
            _erasedDraft,
            erasedUser: _erasedAuthor,
          ),
        },
        {
          _survivingRequest: const {
            ('participant', _survivor),
            ('forward', _forwardRecipient),
          },
          _publishedRequest: _authorErasureRecipients,
          _erasedDraft: _authorErasureRecipients,
        },
      );
    },
    skip: skip,
  );
}

Iterable<String> _recipients(Map<String, dynamic> hint) =>
    (hint['user_ids'] as List<dynamic>? ?? const []).cast<String>();

const _authorErasureRecipients = {
  ('participant', _admittedMember),
  ('forward', _forwardRecipient),
  ('inbox_item', _inboxOwner),
};

Iterable<Map<String, dynamic>> _deleteHints(
  List<Map<String, dynamic>> hints,
  String requestId,
) => hints.where(
  (hint) =>
      hint['id'] == requestId &&
      hint['event'] == 'delete' &&
      _affectedEntities.contains(hint['entity']),
);

Set<(String, String)> _deleteRecipients(
  List<Map<String, dynamic>> hints,
  String requestId, {
  required String erasedUser,
}) => {
  for (final hint in _deleteHints(hints, requestId))
    for (final recipient in _recipients(hint))
      // A removed participant or forward sender may name their own account.
      // The recipient contract concerns the accounts that survive the erasure.
      if (recipient != erasedUser || hint['entity'] == 'inbox_item')
        (hint['entity'] as String, recipient),
};

Future<void> _seed(Connection writer) async {
  final users = [
    _survivor,
    _erasedMember,
    _forwardRecipient,
    _erasedAuthor,
    _admittedMember,
    _inboxOwner,
    _bystander,
  ];
  for (final (index, id) in users.indexed) {
    await writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
      parameters: {'id': id, 'key': pgTestPublicKey('erasureHints', index + 1)},
    );
  }

  // Erasure hard-deletes drafts and preserves published Request tombstones.
  await writer.execute('''
INSERT INTO public.beacon (id, user_id, title, description, status, published_at)
VALUES
  ('$_survivingRequest', '$_survivor', 'Surviving Request', '',
   ${BeaconStatus.open.smallintValue}, now()),
  ('$_publishedRequest', '$_erasedAuthor', 'Published Request', '',
   ${BeaconStatus.open.smallintValue}, now()),
  ('$_erasedDraft', '$_erasedAuthor', 'Erased draft', '',
   ${BeaconStatus.draft.smallintValue}, NULL),
  ('$_emptyDraft', '$_survivor', 'Empty draft', '',
   ${BeaconStatus.draft.smallintValue}, NULL)
''');
  await writer.execute('''
INSERT INTO public.beacon_participant (beacon_id, user_id, role, status, room_access)
VALUES ('$_survivingRequest', '$_erasedMember', 2, 0, 3),
       ('$_publishedRequest', '$_admittedMember', 2, 0, 3),
       ('$_erasedDraft', '$_admittedMember', 2, 0, 3)
''');
  await writer.execute('''
INSERT INTO public.beacon_forward_edge (beacon_id, sender_id, recipient_id)
VALUES ('$_survivingRequest', '$_erasedMember', '$_forwardRecipient'),
       ('$_publishedRequest', '$_erasedAuthor', '$_forwardRecipient'),
       ('$_erasedDraft', '$_erasedAuthor', '$_forwardRecipient')
''');
  await writer.execute('''
DELETE FROM public.inbox_item
WHERE user_id = '$_forwardRecipient'
  AND beacon_id IN ('$_publishedRequest', '$_erasedDraft')
''');
  await writer.execute('''
INSERT INTO public.inbox_item (user_id, beacon_id, status, forward_count, latest_forward_at)
VALUES ('$_inboxOwner', '$_publishedRequest', 0, 1, now()),
       ('$_inboxOwner', '$_erasedDraft', 0, 1, now())
''');
}
