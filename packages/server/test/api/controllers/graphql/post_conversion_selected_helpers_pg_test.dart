@Tags(['pg'])
library;

import 'package:graphql_server2/graphql_server2.dart' show GraphQL;
import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/schema.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/consts/beacon_participant_status_bits.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/beacon_room_case.dart';
import 'package:tentura_server/domain/use_case/forward_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/env.dart';

import '../../../support/disposable_pg_target.dart';
import '../../../support/pg_test_public_keys.dart';

const _author = 'Ucf0000000a01';
const _steward = 'Ucf0000000a02';
const _memberA = 'Ucf0000000a0a';
const _memberB = 'Ucf0000000a0b';
const _memberC = 'Ucf0000000a0c';
const _outsider = 'Ucf0000000a0d';
const _post = 'Bcf0000000a01';
const _rootMessage = 'Rconvertpickroot';
const _members = [_memberA, _memberB, _memberC];
const _users = [_author, _steward, ..._members, _outsider];
const _relayEventKey = 'post_member_delivery_before_conversion';

const _convert = r'''
mutation ConvertPost($id: String!, $helperIds: [String!]) {
  beaconConvertToRequest(
    id: $id
    title: "Help move a piano"
    description: "Carry a piano down three floors on Saturday."
    isDiscoverable: true
    helperIds: $helperIds
  ) {
    id
  }
}
''';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_POST_CONVERSION_HELPERS_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_convert_helpers',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  group('author-selected helpers during post conversion', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late GraphQL schema;
    late BeaconRoomCase room;

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
        ),
      );
      await getIt.allReady(ignorePendingAsyncCreation: true);
      schema = graphqlSchema;
      room = getIt<BeaconRoomCase>();
    });

    setUp(() async {
      await _seed(writer);
      await getIt<TransactionalAttentionCase>().runAction<void>(
        actorUserId: _steward,
        action: (transaction) async {
          await transaction.record(
            await getIt<AttentionIntentCase>().relayReceived(
              beaconId: _post,
              senderId: _steward,
              beaconAuthorId: _author,
              recipientIds: _members,
              sourceEventKey: _relayEventKey,
              beaconKind: BeaconKind.post,
            ),
          );
        },
      );
      // Verify that later cleanup assertions have live state to remove.
      expect(await _activeRelayRecipients(writer), unorderedEquals(_members));
    });

    tearDownAll(() async {
      await getIt.reset();
      await tearDownDisposablePgWriter(session: session);
    });

    Future<Map<String, dynamic>> convert(List<String> helperIds) async =>
        await schema.parseAndExecute(
              _convert,
              variableValues: {'id': _post, 'helperIds': helperIds},
              globalVariables: {
                kGlobalInputQueryJwt: const JwtEntity(sub: _author),
              },
            )
            as Map<String, dynamic>;

    Future<void> expectCanPost(String userId) async {
      final message = await room.createMessage(
        beaconId: _post,
        userId: userId,
        body: 'Room message from $userId after conversion',
      );
      expect(message['id'], isA<String>());
    }

    Future<void> expectCannotPost(String userId) => expectLater(
      room.createMessage(
        beaconId: _post,
        userId: userId,
        body: 'An unselected member cannot post',
      ),
      throwsA(isA<UnauthorizedException>()),
    );

    test(
      'admits only the selected member and permits forwarding to a removed member',
      () async {
        expect(await _participant(writer, _post, _author), isNull);
        final stewardBefore = await _participant(writer, _post, _steward);

        final data = await convert([_memberA]);
        expect(
          (data['beaconConvertToRequest']! as Map<String, dynamic>)['id'],
          _post,
        );
        expect(
          await _participant(writer, _post, _memberA),
          [
            BeaconParticipantRoleBits.helper,
            BeaconParticipantStatusBits.admitted,
            RoomAccessBits.admitted,
          ],
        );
        expect(await _participant(writer, _post, _memberB), isNull);
        expect(await _participant(writer, _post, _memberC), isNull);
        expect(
          await _participant(writer, _post, _steward),
          stewardBefore,
        );
        expect(await _participant(writer, _post, _author), isNull);

        final helpers = await writer.execute(
          Sql.named(
            'SELECT user_id FROM public.beacon_admitted_helper '
            'WHERE beacon_id = @beacon',
          ),
          parameters: {'beacon': _post},
        );
        final helperIds = helpers.map((row) => row.single).toSet();
        expect(helperIds, contains(_memberA));
        expect(helperIds, isNot(contains(_memberB)));
        expect(helperIds, isNot(contains(_memberC)));

        await expectCanPost(_memberA);
        // Authors commonly have no participant row; access is intrinsic.
        await expectCanPost(_author);
        await expectCanPost(_steward);
        await expectCannotPost(_memberB);
        await expectCannotPost(_memberC);

        final delivery = await getIt<ForwardCase>().forward(
          senderId: _author,
          beaconId: _post,
          recipientIds: const [_memberB],
        );
        expect(delivery.deliveredRecipientIds, [_memberB]);
        expect(delivery.availabilitySkippedRecipientIds, isEmpty);
        // Receiving a Request again does not automatically readmit a helper.
        expect(await _participant(writer, _post, _memberB), isNull);
        await expectCannotPost(_memberB);
      },
    );

    test(
      'records the normal admission attention for the selected helper',
      () async {
        await convert([_memberA]);

        final receipts = await writer.execute(
          Sql.named('''
SELECT receipt.account_id, occurrence.actor_user_id
FROM public.notification_outbox receipt
JOIN public.attention_occurrence occurrence
  ON occurrence.id = receipt.occurrence_id
WHERE receipt.beacon_id = @beacon AND occurrence.event_type = 'offerAccepted'
ORDER BY receipt.account_id
'''),
          parameters: {'beacon': _post},
        );
        expect(
          receipts.map((row) => row.toList()).toList(),
          [
            [_memberA, _author],
          ],
          reason:
              'Conversion must dispatch the same admission event as the author admitting a helper',
        );
      },
    );

    test(
      'cleans dropped members inbox attention and General read cursors',
      () async {
        final selectedCursorBefore = await _seenRows(writer, _memberA);
        expect(selectedCursorBefore, hasLength(1));
        for (final member in [_memberB, _memberC]) {
          expect(await _seenRows(writer, member), hasLength(1));
          expect(await _liveInboxRows(writer, member), hasLength(1));
        }

        await convert([_memberA]);

        for (final member in [_memberB, _memberC]) {
          expect(await _participant(writer, _post, member), isNull);
          expect(await _seenRows(writer, member), isEmpty);
          expect(await _liveInboxRows(writer, member), isEmpty);
        }
        expect(
          await _activeRelayRecipients(writer),
          isNot(anyOf(contains(_memberB), contains(_memberC))),
          reason:
              'Receipts from the former Post membership must stop appearing as live attention',
        );
        expect(await _seenRows(writer, _memberA), selectedCursorBefore);
      },
    );

    test(
      'an empty helper selection removes every member and keeps author and stewards',
      () async {
        await writer.execute(
          Sql.named('''
INSERT INTO public.beacon_participant
  (id, beacon_id, user_id, role, status, room_access)
VALUES ('Pconvertpickauthor', @beacon, @author, @role, 0, @access)
'''),
          parameters: {
            'beacon': _post,
            'author': _author,
            'role': BeaconParticipantRoleBits.author,
            'access': RoomAccessBits.admitted,
          },
        );
        final authorBefore = await _participant(writer, _post, _author);
        final stewardBefore = await _participant(writer, _post, _steward);

        await convert([]);

        for (final member in _members) {
          expect(await _participant(writer, _post, member), isNull);
          expect(await _seenRows(writer, member), isEmpty);
          expect(await _liveInboxRows(writer, member), isEmpty);
          await expectCannotPost(member);
        }
        expect(await _activeRelayRecipients(writer), isEmpty);
        expect(await _participant(writer, _post, _author), authorBefore);
        expect(await _participant(writer, _post, _steward), stewardBefore);
        await expectCanPost(_author);
        await expectCanPost(_steward);
      },
    );

    for (final (description, userId) in [
      ('a non-member', _outsider),
      ('the author without a member role', _author),
      ('a steward without a member role', _steward),
    ]) {
      for (final (selectionDescription, helperIds) in [
        ('the sole selected helper', [userId]),
        ('a helper selected alongside a post member', [_memberA, userId]),
      ]) {
        test(
          'rejects $description as $selectionDescription with a typed domain '
          'error and changes nothing',
          () async {
            final before = await _conversionSnapshot(writer);

            await expectLater(
              convert(helperIds),
              throwsA(
                allOf(
                  isA<ExceptionBase>(),
                  isNot(isA<UnspecifiedException>()),
                ),
              ),
            );

            expect(await _conversionSnapshot(writer), before);
          },
        );
      }
    }

    test(
      'member cleanup failure rolls back conversion and helper admission before a retry',
      () async {
        final before = await _conversionSnapshot(writer);
        await writer.execute(r'''
CREATE FUNCTION public.conversion_test_reject_member_delete()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'post conversion member cleanup failed';
END;
$$
''');
        await writer.execute('''
CREATE TRIGGER conversion_test_reject_member_delete_trg
BEFORE DELETE ON public.beacon_participant
FOR EACH ROW WHEN (OLD.beacon_id = '$_post' AND OLD.user_id = '$_memberB')
EXECUTE FUNCTION public.conversion_test_reject_member_delete()
''');
        try {
          await expectLater(
            convert([_memberA]),
            throwsA(
              predicate<Object>(
                (error) => error.toString().contains(
                  'post conversion member cleanup failed',
                ),
                'the injected participant cleanup failure',
              ),
            ),
          );
          expect(await _conversionSnapshot(writer), before);
        } finally {
          await writer.execute(
            'DROP TRIGGER conversion_test_reject_member_delete_trg ON public.beacon_participant',
          );
          await writer.execute(
            'DROP FUNCTION public.conversion_test_reject_member_delete()',
          );
        }

        await convert([_memberA]);
        expect(
          await _participant(writer, _post, _memberA),
          [
            BeaconParticipantRoleBits.helper,
            BeaconParticipantStatusBits.admitted,
            RoomAccessBits.admitted,
          ],
        );
        expect(await _participant(writer, _post, _memberB), isNull);
        expect(await _participant(writer, _post, _memberC), isNull);
      },
    );
  });
}

Future<List<Object?>?> _participant(
  Connection writer,
  String beaconId,
  String userId,
) async {
  final rows = await writer.execute(
    Sql.named('''
SELECT role, status, room_access FROM public.beacon_participant
WHERE beacon_id = @beacon AND user_id = @user
'''),
    parameters: {'beacon': beaconId, 'user': userId},
  );
  return rows.singleOrNull?.toList();
}

Future<List<List<Object?>>> _seenRows(Connection writer, String userId) async =>
    (await writer.execute(
      Sql.named('''
SELECT last_seen_at FROM public.beacon_room_seen
WHERE beacon_id = @beacon AND user_id = @user AND thread_item_id IS NULL
'''),
      parameters: {'beacon': _post, 'user': userId},
    )).map((row) => row.toList()).toList();

Future<List<List<Object?>>> _liveInboxRows(
  Connection writer,
  String userId,
) async => (await writer.execute(
  Sql.named('''
SELECT status FROM public.inbox_item
WHERE beacon_id = @beacon AND user_id = @user AND status IN (0, 1)
'''),
  parameters: {'beacon': _post, 'user': userId},
)).map((row) => row.toList()).toList();

Future<List<String>> _activeRelayRecipients(Connection writer) async =>
    (await writer.execute(
      Sql.named('''
SELECT account_id FROM public.notification_outbox
WHERE beacon_id = @beacon AND source_event_key = @event
  AND seen_at IS NULL AND cleared_at IS NULL AND settlement_kind IS NULL
ORDER BY account_id
'''),
      parameters: {'beacon': _post, 'event': _relayEventKey},
    )).map((row) => row.single! as String).toList();

Future<Map<String, String>> _conversionSnapshot(Connection writer) async {
  final snapshot = <String, String>{};
  for (final table in [
    'beacon',
    'beacon_participant',
    'beacon_forward_edge',
    'inbox_item',
    'beacon_room_seen',
    'beacon_room_message',
    'beacon_activity_event',
    'beacon_help_offer_admission_event',
    'attention_occurrence',
    'attention_occurrence_recipient',
    'attention_request_state',
    'notification_outbox',
  ]) {
    final rows = await writer.execute('''
SELECT COALESCE(jsonb_agg(to_jsonb(entry) ORDER BY to_jsonb(entry)::text), '[]'::jsonb)::text
FROM public.$table entry
''');
    snapshot[table] = rows.single.single! as String;
  }
  return snapshot;
}

Future<void> _seed(Connection writer) async {
  await writer.execute('''
TRUNCATE TABLE public.notification_outbox,
  public.attention_occurrence_recipient, public.attention_occurrence,
  public.beacon, public."user" CASCADE
''');
  for (var index = 0; index < _users.length; index++) {
    final id = _users[index];
    await writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
      parameters: {'id': id, 'key': pgTestPublicKey('cp', index + 1)},
    );
  }
  // The next forward tests membership, with mutual visibility already valid.
  await writer.execute(
    Sql.named('''
INSERT INTO public.vote_user (subject, object, amount)
VALUES (@author, @member, 1), (@member, @author, 1)
'''),
    parameters: {'author': _author, 'member': _memberB},
  );
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, forward_policy,
   is_discoverable, published_at)
VALUES (@beacon, @author, '', '', 0, 1, 1, false, now())
'''),
    parameters: {'beacon': _post, 'author': _author},
  );
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body)
VALUES (@message, @beacon, @author, 'A piano needs moving on Saturday.')
'''),
    parameters: {'message': _rootMessage, 'beacon': _post, 'author': _author},
  );
  await writer.execute(
    Sql.named(
      'UPDATE public.beacon SET post_root_message_id = @message WHERE id = @beacon',
    ),
    parameters: {'message': _rootMessage, 'beacon': _post},
  );
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon_participant
  (id, beacon_id, user_id, role, status, room_access)
VALUES ('Pconvertpicksteward', @beacon, @steward, @role, 0, @access)
'''),
    parameters: {
      'beacon': _post,
      'steward': _steward,
      'role': BeaconParticipantRoleBits.steward,
      'access': RoomAccessBits.admitted,
    },
  );
  for (final member in _members) {
    // Real Post admission triggers produce addressee participants. These edges
    // belong to the steward, so the author's later forward is a new delivery.
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon_forward_edge (id, beacon_id, sender_id, recipient_id)
VALUES (@edge, @beacon, @steward, @member)
'''),
      parameters: {
        'edge': 'Fconvertpick$member',
        'beacon': _post,
        'steward': _steward,
        'member': member,
      },
    );
    expect(
      await _participant(writer, _post, member),
      [
        BeaconParticipantRoleBits.addressee,
        BeaconParticipantStatusBits.watching,
        RoomAccessBits.admitted,
      ],
    );
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon_room_seen (beacon_id, user_id, last_seen_at)
VALUES (@beacon, @member, '2026-10-01T12:00:00Z')
'''),
      parameters: {'beacon': _post, 'member': member},
    );
  }
}
