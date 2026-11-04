@Tags(['pg'])
library;

import 'dart:async';
import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/forward_edge_repository.dart';
import 'package:tentura_server/data/repository/help_offer_admission_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/inbox_repository.dart';
import 'package:tentura_server/domain/use_case/beacon_involvement_case.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/fake_beacon_access_guard.dart';
import '../../support/pg_notification_recorder.dart';
import '../../support/pg_test_public_keys.dart';

const _author = 'Ureadhintauth';
const _sender = 'Ureadhintsend';
const _secondSender = 'Ureadhinttwo';
const _reader = 'Ureadhintrecv';
const _member = 'Ureadhintmemb';
const _beacon = 'Breadhint001';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_FORWARD_READ_HINT_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_forward_read_hint',
  );
  final skip = await pgSkipReason(target);
  late DisposablePgWriterSession session;
  late TenturaDb db;
  late Connection listener;
  late PgNotificationRecorder recorder;
  late ForwardEdgeRepository edges;
  late BeaconInvolvementCase involvement;

  Future<void> barrier(String token) => session.writer.execute(
    Sql.named("SELECT pg_notify('entity_changes', @payload)"),
    parameters: {
      'payload': jsonEncode({'entity': 'barrier', 'id': token}),
    },
  );

  List<Map<String, dynamic>> hints() => recorder.messages
      .where((m) => m['entity'] == 'forward' && m['id'] == _beacon)
      .toList();

  Future<void> openAs(String viewer) async {
    final result = await involvement.asMap(
      beaconId: _beacon,
      currentUserId: viewer,
    );
    expect(result.forwardedToIds, contains(_reader));
  }

  // Involvement intentionally starts read stamps without awaiting them. Wait
  // for their committed state before the NOTIFY barrier, never a fixed sleep.
  Future<void> waitForStamps(List<String> ids) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (true) {
      final rows = await Future.wait(ids.map(edges.fetchById));
      if (rows.every((row) => row?.recipientReadAt != null)) return;
      if (DateTime.now().isAfter(deadline)) {
        fail('Opening involvement did not persist every recipient read stamp');
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  group('Forward read receipts notify only the forwarder', () {
    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      db = openDisposablePgDatabase(target);
      edges = ForwardEdgeRepository(db);
      involvement = BeaconInvolvementCase(
        edges,
        HelpOfferRepository(db),
        HelpOfferAdmissionRepository(db),
        InboxRepository(db),
        FakeBeaconAccessGuard(),
        env: target.databaseEnv,
        logger: Logger('ForwardReadSenderNotificationPgTest'),
      );
      listener = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await listener.execute('LISTEN entity_changes');
      recorder = PgNotificationRecorder(listener.channels['entity_changes']);
    });

    setUp(() async {
      await session.writer.execute(
        'TRUNCATE public.beacon, public."user" CASCADE',
      );
      for (final (i, id) in [
        _author,
        _sender,
        _secondSender,
        _reader,
        _member,
      ].indexed) {
        await session.writer.execute(
          Sql.named(
            'INSERT INTO public."user" (id, display_name, public_key) '
            'VALUES (@id, @id, @key)',
          ),
          parameters: {
            'id': id,
            'key': pgTestPublicKey('forwardreadhint', i + 1),
          },
        );
      }
      await session.writer.execute(
        Sql.named(
          'INSERT INTO public.beacon (id, user_id, title, description) '
          "VALUES (@id, @author, 'Request with forwards', '')",
        ),
        parameters: {'id': _beacon, 'author': _author},
      );
      // The member is neither endpoint: over-broad Request fan-out must be
      // observable independently of sender/recipient delivery.
      for (final (i, id) in [_reader, _member].indexed) {
        await session.writer.execute(
          Sql.named('''
INSERT INTO public.beacon_participant
  (id, beacon_id, user_id, role, status, room_access, created_at, updated_at)
VALUES (@id, @beacon, @user, 0, 0, @admitted, now(), now())
'''),
          parameters: {
            'id': 'Preadhint$i',
            'beacon': _beacon,
            'user': id,
            'admitted': RoomAccessBits.admitted,
          },
        );
      }
    });

    tearDownAll(() async {
      await recorder.cancel();
      await listener.close();
      await tearDownDisposablePgWriter(session: session, drift: db);
    });

    for (final scenario in [
      'direct',
      'two forwarders',
      'onward chain',
      'author viewing',
    ]) {
      test(
        switch (scenario) {
          'direct' =>
            'first recipient open sends one read hint only to the sender',
          'two forwarders' =>
            'first recipient open sends each of two forwarders only their own read hint',
          'author viewing' =>
            'author opens preserve unread and read recipient receipts without sending hints',
          _ =>
            'first onward recipient open sends its read hint only to the immediate sender',
        },
        () async {
          String? parentId;
          if (scenario == 'onward chain') {
            await edges.create(
              beaconId: _beacon,
              senderId: _author,
              recipientId: _sender,
              note: 'Pass this on',
            );
            parentId = (await edges.findActiveEdge(
              beaconId: _beacon,
              senderId: _author,
              recipientId: _sender,
            ))!.id;
          }
          final senders = [
            _sender,
            if (scenario == 'two forwarders') _secondSender,
          ];
          final ids = <String>[];
          for (final sender in senders) {
            await edges.create(
              beaconId: _beacon,
              senderId: sender,
              recipientId: _reader,
              note: 'Could you help?',
              parentEdgeId: parentId,
            );
            ids.add(
              (await edges.findActiveEdge(
                beaconId: _beacon,
                senderId: sender,
                recipientId: _reader,
              ))!.id,
            );
          }
          await recorder.drain(sendBarrier: barrier);

          // In the chain the immediate sender is also the parent's recipient;
          // defer that person's open until after checking the child in isolation.
          for (final viewer in [_author, if (parentId == null) ...senders]) {
            await recorder.drain(sendBarrier: barrier);
            await openAs(viewer);
            await recorder.flush(sendBarrier: barrier);
            expect(
              hints(),
              isEmpty,
              reason: "$viewer cannot issue another person's receipt",
            );
            for (final id in ids) {
              expect((await edges.fetchById(id))!.recipientReadAt, isNull);
            }
          }
          if (parentId != null) {
            expect(
              (await edges.fetchById(parentId))!.recipientReadAt,
              isNull,
              reason:
                  'The parent sender opening their own forward does not stamp it',
            );
          }

          await recorder.drain(sendBarrier: barrier);
          await openAs(_reader);
          await waitForStamps(ids);
          await recorder.flush(sendBarrier: barrier);
          final readHints = hints();
          final stamps = [
            for (final id in ids) (await edges.fetchById(id))!.recipientReadAt,
          ];
          if (parentId != null) {
            expect(
              (await edges.fetchById(parentId))!.recipientReadAt,
              isNull,
              reason: 'The child recipient cannot create a parent-edge receipt',
            );
            expect(
              readHints,
              hasLength(1),
              reason:
                  'Only the child edge is stamped; no parent receipt is emitted',
            );
          }

          // Author viewing is checked separately both before and after receipt
          // creation, rather than sharing a notification window with senders.
          await recorder.drain(sendBarrier: barrier);
          await openAs(_author);
          await recorder.flush(sendBarrier: barrier);
          expect(
            hints(),
            isEmpty,
            reason: 'Author viewing after the read creates no receipt hint',
          );
          expect(
            [
              for (final id in ids)
                (await edges.fetchById(id))!.recipientReadAt,
            ],
            stamps,
            reason: 'Author viewing preserves the recipient receipts',
          );
          var parentReadHints = <Map<String, dynamic>>[];
          if (parentId != null) {
            expect(
              (await edges.fetchById(parentId))!.recipientReadAt,
              isNull,
              reason:
                  'Parent sender viewing still leaves the parent receipt unread',
            );
            await recorder.drain(sendBarrier: barrier);
            await openAs(_sender);
            await waitForStamps([parentId]);
            await recorder.flush(sendBarrier: barrier);
            parentReadHints = hints();
            expect(parentReadHints, hasLength(1));
            expect(parentReadHints.single['event'], 'update');
            expect(
              (await edges.fetchById(ids.single))!.recipientReadAt,
              stamps.single,
              reason: 'Reading the parent does not stamp the child again',
            );
          }
          // The sender can actually display the receipt from involvement.
          for (final sender in senders) {
            final result = await involvement.asMap(
              beaconId: _beacon,
              currentUserId: sender,
            );
            expect(result.myForwardedRecipients.single.readAt, isNotNull);
          }

          await recorder.drain(sendBarrier: barrier);
          await openAs(_reader);
          await recorder.flush(sendBarrier: barrier);
          expect(
            hints(),
            isEmpty,
            reason: 'Repeat opens do not write or notify',
          );
          expect(
            [
              for (final id in ids)
                (await edges.fetchById(id))!.recipientReadAt,
            ],
            stamps,
            reason: 'Repeat opens preserve the original read timestamps',
          );

          // Guard against suppressing every UPDATE. These operations on the
          // same edge must still update the reader and other open Requests.
          final expectedForwardRecipients = {
            _author,
            _sender,
            _reader,
            _member,
            if (scenario == 'two forwarders') _secondSender,
          };
          for (final change in [
            "note = 'Updated note'",
            "context = 'Updated context'",
            'contact_sweep_exempt = true',
          ]) {
            await recorder.drain(sendBarrier: barrier);
            await session.writer.execute(
              Sql.named(
                'UPDATE public.beacon_forward_edge SET $change WHERE id = @id',
              ),
              parameters: {'id': ids.first},
            );
            await recorder.flush(sendBarrier: barrier);
            final changeHints = hints();
            expect(
              changeHints,
              hasLength(1),
              reason: '$change emits exactly one forward hint',
            );
            expect(
              changeHints.single['event'],
              'update',
              reason:
                  '$change is an update, including rejection and cancellation',
            );
            expect(
              changeHints.single['user_ids'],
              unorderedEquals(expectedForwardRecipients),
              reason: '$change retains Request-wide fan-out',
            );
          }

          // Read edges cannot be cancelled. Replace the receipt fixture with
          // a fresh unread edge to exercise cancellation notification fan-out.
          await session.writer.execute(
            Sql.named('DELETE FROM public.beacon_forward_edge WHERE id = @id'),
            parameters: {'id': ids.first},
          );
          await edges.create(
            beaconId: _beacon,
            senderId: _sender,
            recipientId: _reader,
            note: 'Could you help again?',
            parentEdgeId: parentId,
          );
          final beforeCancel = (await edges.findActiveEdge(
            beaconId: _beacon,
            senderId: _sender,
            recipientId: _reader,
          ))!;
          expect(beforeCancel.cancelledAt, isNull);
          expect(beforeCancel.recipientReadAt, isNull);
          expect(beforeCancel.recipientRejected, isFalse);
          await recorder.drain(sendBarrier: barrier);
          await edges.cancel(beforeCancel.id, _sender);
          await recorder.flush(sendBarrier: barrier);
          expect(
            (await edges.fetchById(beforeCancel.id))!.cancelledAt,
            isNotNull,
          );
          expect(hints(), hasLength(1), reason: 'Cancellation emits one hint');
          expect(hints().single['event'], 'update');
          expect(
            hints().single['user_ids'],
            unorderedEquals(expectedForwardRecipients),
          );

          // Re-forward after cancellation, then remove that new edge. Neither
          // INSERT nor DELETE is a read receipt and both retain full fan-out.
          for (final event in ['insert', 'delete']) {
            await recorder.drain(sendBarrier: barrier);
            if (event == 'insert') {
              await edges.create(
                beaconId: _beacon,
                senderId: _sender,
                recipientId: _reader,
                note: 'Try again',
                parentEdgeId: parentId,
              );
            } else {
              final active = await edges.findActiveEdge(
                beaconId: _beacon,
                senderId: _sender,
                recipientId: _reader,
              );
              expect(active, isNotNull);
              await session.writer.execute(
                Sql.named(
                  'DELETE FROM public.beacon_forward_edge WHERE id = @id',
                ),
                parameters: {'id': active!.id},
              );
            }
            await recorder.flush(sendBarrier: barrier);
            final operationHints = hints();
            expect(operationHints, hasLength(1));
            expect(operationHints.single['event'], event);
            expect(
              operationHints.single['user_ids'],
              unorderedEquals(expectedForwardRecipients),
              reason: '$event retains Request-wide fan-out',
            );
            if (event == 'insert') {
              // Reject a fresh active edge, independent of the cancelled edge.
              final fresh = (await edges.findActiveEdge(
                beaconId: _beacon,
                senderId: _sender,
                recipientId: _reader,
              ))!;
              expect(fresh.id, isNot(ids.first));
              expect(fresh.cancelledAt, isNull);
              expect(fresh.recipientRejected, isFalse);
              await recorder.drain(sendBarrier: barrier);
              await session.writer.execute(
                Sql.named(
                  'UPDATE public.beacon_forward_edge SET recipient_rejected = true WHERE id = @id',
                ),
                parameters: {'id': fresh.id},
              );
              await recorder.flush(sendBarrier: barrier);
              expect(
                (await edges.fetchById(fresh.id))!.recipientRejected,
                isTrue,
              );
              expect(hints(), hasLength(1), reason: 'Rejection emits one hint');
              expect(hints().single['event'], 'update');
              expect(
                hints().single['user_ids'],
                unorderedEquals(expectedForwardRecipients),
              );
            }
          }

          if (scenario == 'onward chain') {
            expect(
              readHints.where(
                (hint) => (hint['user_ids'] as List).contains(_author),
              ),
              isEmpty,
              reason:
                  'The parent edge sender (the author) receives no hint '
                  'when the onward recipient reads the child edge',
            );
            expect(
              parentReadHints.single['user_ids'],
              [_author],
              reason:
                  'Reading the parent separately notifies only its own sender',
            );
          }

          expect(
            readHints,
            hasLength(senders.length),
            reason: 'Each stamped edge emits exactly one forward hint',
          );
          expect(
            readHints.map((hint) => hint['event']),
            everyElement('update'),
          );
          expect(
            readHints
                .map((hint) => (hint['user_ids'] as List).cast<String>())
                .toList(),
            unorderedEquals([
              for (final sender in senders) [sender],
            ]),
            reason:
                'Only the sender needs the read receipt; the reader, '
                'author, other members and ancestor forwarders must not refetch',
          );
        },
      );
    }
  }, skip: skip);
}
