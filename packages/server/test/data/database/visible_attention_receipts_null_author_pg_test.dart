@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_repository.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

/// A Request whose author row is gone (`beacon.user_id` is `ON DELETE SET
/// NULL`) must stay readable for the people the content wall still admits:
/// room participants, stewards and helpers with a live offer. The attention
/// feed hides a receipt whose Request the viewer cannot read, so reading it
/// through `visible_attention_receipts` and the real [AttentionRepository]
/// shows what the viewer would actually see.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_ATTENTION_NULL_AUTHOR_TEST_DB',
    defaultNamePrefix: 'tentura_test_attn_null_author',
  );
  final skipReason = await pgSkipReason(target);

  group(
    'visible attention receipts on a Request whose author is gone',
    skip: skipReason,
    () {
      late DisposablePgWriterSession session;
      TenturaDb? database;
      late AttentionRepository repository;

      setUpAll(() async {
        session = await setUpDisposablePgWriter(target: target);
        await _seed(session.writer);
        database = TenturaDb(target.databaseEnv);
        repository = AttentionRepository(database!);
      });

      tearDownAll(
        () => tearDownDisposablePgWriter(session: session, drift: database),
      );

      Future<List<Map<String, Object?>>> visibleRows(String viewer) async {
        final result = await session.writer.execute(
          Sql.named(
            'SELECT receipt_id, tombstone_copy '
            'FROM public.visible_attention_receipts(@viewer) '
            'ORDER BY receipt_id',
          ),
          parameters: {'viewer': viewer},
        );
        return [for (final row in result) row.toColumnMap()];
      }

      test(
        'the content wall admits each of them to the Request with no author '
        'and keeps outsiders out',
        () async {
          Future<Object?> admitted(String viewer) async {
            final result = await session.writer.execute(
              Sql.named(
                'SELECT public.beacon_can_read_content(@beacon, @viewer)',
              ),
              parameters: {'beacon': _requestId, 'viewer': viewer},
            );
            return result.single.first;
          }

          for (final scenario in _readers) {
            expect(
              await admitted(scenario.viewer),
              isTrue,
              reason: scenario.who,
            );
          }
          for (final scenario in _outsiders) {
            expect(
              await admitted(scenario.viewer),
              isFalse,
              reason: scenario.who,
            );
          }
        },
      );

      for (final scenario in _readers) {
        test(
          '${scenario.who} reads the content receipt of a Request with no '
          'author, not as a tombstone copy',
          () async {
            expect(
              await visibleRows(scenario.viewer),
              [
                {
                  'receipt_id': _receiptId(scenario.viewer),
                  'tombstone_copy': false,
                },
              ],
            );
          },
        );
      }

      test(
        'a participant sees the receipt of a Request with no author in the '
        'attention feed',
        () async {
          final feed = await repository.attentionFeed(
            accountId: _participantId,
            view: AttentionFeedView.all,
          );
          expect(
            [for (final item in feed.page.items) item.id],
            [_receiptId(_participantId)],
          );
        },
      );

      for (final scenario in _outsiders) {
        test(
          '${scenario.who} gets none of the content receipts of a Request '
          'with no author',
          () async {
            expect(await visibleRows(scenario.viewer), isEmpty);
            final feed = await repository.attentionFeed(
              accountId: scenario.viewer,
              view: AttentionFeedView.all,
            );
            expect(feed.page.items, isEmpty);
          },
        );
      }
    },
  );

  final upgradeTarget = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_ATTENTION_NULL_AUTHOR_UPGRADE_TEST_DB',
    defaultNamePrefix: 'tentura_test_attn_null_author_up',
  );
  final upgradeSkipReason = await pgSkipReason(upgradeTarget);

  group(
    'a database migrated before the fix keeps no Request with no author '
    'unreadable once it is upgraded to head',
    skip: upgradeSkipReason,
    () {
      late DisposablePgWriterSession session;

      setUpAll(() async {
        session = await setUpDisposablePgWriter(
          target: upgradeTarget,
          lastInclusiveVersion: schemaVersionBeforeNullAuthorFix,
        );
        await _seed(session.writer);
      });

      tearDownAll(() => tearDownDisposablePgWriter(session: session));

      Future<List<Object?>> visibleReceiptIds(String viewer) async {
        final result = await session.writer.execute(
          Sql.named(
            'SELECT receipt_id FROM public.visible_attention_receipts(@viewer)',
          ),
          parameters: {'viewer': viewer},
        );
        return [for (final row in result) row.first];
      }

      test(
        'the schema before the fix hides the receipt from every kind of '
        'reader (the defect the fixture reproduces)',
        () async {
          for (final scenario in _readers) {
            expect(
              await visibleReceiptIds(scenario.viewer),
              isEmpty,
              reason: scenario.who,
            );
          }
        },
      );

      test(
        'upgrading to head makes the receipt readable for every kind of '
        'reader and keeps outsiders out',
        () async {
          await migrateDbSchema(session.writer);
          for (final scenario in _readers) {
            expect(
              await visibleReceiptIds(scenario.viewer),
              [_receiptId(scenario.viewer)],
              reason: scenario.who,
            );
          }
          for (final scenario in _outsiders) {
            expect(
              await visibleReceiptIds(scenario.viewer),
              isEmpty,
              reason: scenario.who,
            );
          }
        },
      );
    },
  );
}

const _participantId = 'Unullauth01';
const _roomGuestId = 'Unullauth02';
const _stewardId = 'Unullauth03';
const _helperId = 'Unullauth04';
const _unrelatedId = 'Unullauth05';
const _formerAuthorId = 'Unullauth06';
const _withdrawnHelperId = 'Unullauth07';
const _roomOutsiderId = 'Unullauth08';

/// The last schema version that still has the NULL-author gap (m0309 is the
/// newest migration before the fix).
const schemaVersionBeforeNullAuthorFix = '0309';
const _requestId = 'Bnullauth01';

const _readers = [
  (who: 'a participant with the participant role', viewer: _participantId),
  (who: 'a participant admitted to the room', viewer: _roomGuestId),
  (who: 'a steward', viewer: _stewardId),
  (who: 'a helper with a live offer', viewer: _helperId),
];

const _outsiders = [
  (who: 'a person with no link to the Request', viewer: _unrelatedId),
  (
    who: 'a helper whose offer was withdrawn',
    viewer: _withdrawnHelperId,
  ),
  (
    who:
        'a participant who is neither in the participant role nor admitted '
        'to the room',
    viewer: _roomOutsiderId,
  ),
];

String _receiptId(String viewer) => 'Nnullauth$viewer';

Future<void> _seed(Connection writer) async {
  final people = [
    _participantId,
    _roomGuestId,
    _stewardId,
    _helperId,
    _unrelatedId,
    _formerAuthorId,
    _withdrawnHelperId,
    _roomOutsiderId,
  ];
  for (final (slot, id) in people.indexed) {
    await writer.execute(
      Sql.named(
        'INSERT INTO public."user" (id, display_name, public_key) '
        'VALUES (@id, @id, @key)',
      ),
      parameters: {'id': id, 'key': pgTestPublicKey('nullauth', slot + 1)},
    );
  }
  // The schema allows a NULL author only on a deleted Request, so no open
  // Request can lose its author today. The disposable database drops that
  // check to stage the state `ON DELETE SET NULL` would leave if a user row
  // were ever hard-deleted.
  await writer.execute(
    'ALTER TABLE public.beacon DROP CONSTRAINT beacon_owner_or_deleted_ck',
  );
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon (id, user_id, title, description, status)
VALUES (@id, @author, 'Authorless request', 'Author row deleted', 0)
'''),
    parameters: {'id': _requestId, 'author': _formerAuthorId},
  );
  // What `ON DELETE SET NULL` leaves behind once the author row is gone.
  await writer.execute(
    Sql.named('UPDATE public.beacon SET user_id = NULL WHERE id = @id'),
    parameters: {'id': _requestId},
  );
  for (final (viewer, role, roomAccess) in [
    (_participantId, 1, 0),
    (_roomGuestId, 2, 3),
    (_roomOutsiderId, 2, 0),
  ]) {
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon_participant (id, beacon_id, user_id, role, room_access)
VALUES (@id, @beacon, @viewer, @role, @access)
'''),
      parameters: {
        'id': 'Pnullauth$viewer',
        'beacon': _requestId,
        'viewer': viewer,
        'role': role,
        'access': roomAccess,
      },
    );
  }
  await writer.execute(
    Sql.named(
      'INSERT INTO public.beacon_steward (beacon_id, user_id) '
      'VALUES (@beacon, @viewer)',
    ),
    parameters: {'beacon': _requestId, 'viewer': _stewardId},
  );
  await writer.execute(
    Sql.named(
      'INSERT INTO public.beacon_help_offer (beacon_id, user_id, status) '
      'VALUES (@beacon, @viewer, 0)',
    ),
    parameters: {'beacon': _requestId, 'viewer': _helperId},
  );
  await writer.execute(
    Sql.named(
      'INSERT INTO public.beacon_help_offer (beacon_id, user_id, status) '
      'VALUES (@beacon, @viewer, 1)',
    ),
    parameters: {'beacon': _requestId, 'viewer': _withdrawnHelperId},
  );
  for (final viewer in [
    _participantId,
    _roomGuestId,
    _stewardId,
    _helperId,
    _unrelatedId,
    _withdrawnHelperId,
    _roomOutsiderId,
  ]) {
    await writer.execute(
      Sql.named('''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, priority, title, body, action_url,
  dedup_key, beacon_id, source_event_key, destination_kind,
  presentation_key, presentation_payload, suppression_class, access_policy,
  requires_action, created_at
) VALUES (
  @id, @viewer, 'coordination', 'coordinationChanged', 'normal',
  'Fixture receipt', 'Null author fixture', '/attention',
  @id, @beacon, @id, 'beacon', 'request_status_changed', '{}'::jsonb,
  'standard', 'beacon_content', false, '2026-11-01T00:00:00Z'::timestamptz
)
'''),
      parameters: {
        'id': _receiptId(viewer),
        'viewer': viewer,
        'beacon': _requestId,
      },
    );
  }
}
