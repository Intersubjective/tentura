@Tags(['pg'])
library;

import 'dart:async';

import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/capability_evidence_repository.dart';
import 'package:tentura_server/data/repository/forward_edge_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/inbox_repository.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/domain/port/attention_dispatch_port.dart';
import 'package:tentura_server/domain/port/forward_attribution_repository_port.dart';
import 'package:tentura_server/domain/port/person_visibility_repository_port.dart';
import 'package:tentura_server/domain/use_case/forward_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/fake_beacon_access_guard.dart';
import '../../support/fake_user_block_repository.dart';
import '../../support/pg_test_public_keys.dart';
import '../../support/pg_wait.dart';

const _sender = 'UreadcancelSender';
const _recipient = 'UreadcancelRecv';
const _beacon = 'Breadcancel001';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_FORWARD_READ_CANCEL_TEST_DB',
    defaultNamePrefix: 'tentura_test_forward_read_cancel',
  );
  final unavailable = await pgSkipReason(target);
  if (unavailable != null) {
    test('Forward read and cancellation require Postgres', () {
      fail(unavailable);
    });
    return;
  }

  group('Forward read and cancellation are mutually exclusive', () {
    late DisposablePgWriterSession session;
    late TenturaDb senderDb;
    late TenturaDb recipientDb;
    late _PausedEdges senderEdges;
    late _PausedEdges recipientEdges;
    late ForwardCase sender;
    late ForwardCase recipient;
    late String edgeId;

    ForwardCase makeCase(TenturaDb db, ForwardEdgeRepository edges) =>
        ForwardCase(
          edges,
          _UnusedAttribution(),
          HelpOfferRepository(db),
          InboxRepository(db),
          CapabilityEvidenceRepository(db),
          BeaconRepository(db),
          FakeUserBlockRepository(),
          _UnusedVisibility(),
          FakeBeaconAccessGuard(),
          attention: TransactionalAttentionCase(
            MutatingUnitOfWork(db),
            _UnusedDispatch(),
          ),
          env: target.databaseEnv,
          logger: Logger('ForwardReadCancelExclusionPgTest'),
        );

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      senderDb = openDisposablePgDatabase(target);
      recipientDb = openDisposablePgDatabase(target);
    });

    setUp(() async {
      await session.writer.execute(
        'TRUNCATE public.beacon, public."user" CASCADE',
      );
      for (final (i, id) in [_sender, _recipient].indexed) {
        await session.writer.execute(
          Sql.named(
            'INSERT INTO public."user" '
            '(id, display_name, public_key) VALUES (@id, @id, @key)',
          ),
          parameters: {'id': id, 'key': pgTestPublicKey('readcancel', i + 1)},
        );
      }
      await session.writer.execute(
        Sql.named(
          'INSERT INTO public.beacon '
          '(id, user_id, title, description) '
          "VALUES (@id, @sender, 'Help needed', '')",
        ),
        parameters: {'id': _beacon, 'sender': _sender},
      );
      senderEdges = _PausedEdges(senderDb);
      recipientEdges = _PausedEdges(recipientDb);
      sender = makeCase(senderDb, senderEdges);
      recipient = makeCase(recipientDb, recipientEdges);
      await senderEdges.create(
        beaconId: _beacon,
        senderId: _sender,
        recipientId: _recipient,
        note: 'Can you help?',
      );
      edgeId = (await senderEdges.findActiveEdge(
        beaconId: _beacon,
        senderId: _sender,
        recipientId: _recipient,
      ))!.id;
      // Forward creation's database trigger materializes the recipient row.
      final inbox = await InboxRepository(
        recipientDb,
      ).fetchByUserId(_recipient);
      expect(inbox, hasLength(1));
      expect(inbox.single.status, 0);
    });

    tearDownAll(() async {
      await recipientDb.close();
      await tearDownDisposablePgWriter(session: session, drift: senderDb);
    });

    test(
      'A committed read prevents an already eligible cancellation and preserves Activity access',
      () async {
        final gate = senderEdges.beforeCancel = _Barrier();
        final cancelling = sender.cancelForward(
          edgeId: edgeId,
          senderId: _sender,
        );
        late DateTime stamp;
        try {
          // cancelForward has completed its final eligibility checks, but has
          // not issued its UPDATE. The other connection now commits the read.
          await gate.reached.future.timeout(kStableStateWait);
          expect(
            await recipient.markForwardRead(
              beaconId: _beacon,
              userId: _recipient,
            ),
            isTrue,
          );
          final read = (await recipientEdges.fetchById(edgeId))!;
          expect(read.recipientReadAt, isNotNull);
          expect(read.cancelledAt, isNull);
          stamp = read.recipientReadAt!;
        } finally {
          gate.release.complete();
        }
        final cancelled = await cancelling.timeout(kCompletionWait);
        final edge = (await recipientEdges.fetchById(edgeId))!;
        expect(
          edge.cancelledAt,
          isNull,
          reason: 'The committed receipt wins over the stale eligibility check',
        );
        expect(edge.recipientReadAt, stamp);
        expect(cancelled, isFalse);
        final inbox = await InboxRepository(
          recipientDb,
        ).fetchByUserId(_recipient);
        expect(inbox, hasLength(1));
        expect(
          inbox.single.status,
          0,
          reason:
              'Losing cancellation must not withdraw the recipient Activity entry',
        );
      },
    );

    test(
      'A committed cancellation prevents an already selected first-open read stamp',
      () async {
        final gate = recipientEdges.beforeRead = _Barrier();
        final reading = recipient.markForwardRead(
          beaconId: _beacon,
          userId: _recipient,
        );
        late DateTime cancellation;
        try {
          // markForwardRead has selected the unread active inbound edge, but
          // has not issued the stamp UPDATE. Cancellation commits first.
          await gate.reached.future.timeout(kStableStateWait);
          expect(
            await sender.cancelForward(edgeId: edgeId, senderId: _sender),
            isTrue,
          );
          final cancelled = (await senderEdges.fetchById(edgeId))!;
          expect(cancelled.cancelledAt, isNotNull);
          expect(cancelled.recipientReadAt, isNull);
          cancellation = cancelled.cancelledAt!;
        } finally {
          gate.release.complete();
        }
        await reading.timeout(kCompletionWait);
        final edge = (await senderEdges.fetchById(edgeId))!;
        expect(
          edge.recipientReadAt,
          isNull,
          reason:
              'A stale first-open selection cannot acknowledge a cancelled forward',
        );
        expect(edge.cancelledAt, cancellation);
        expect(
          await senderEdges.fetchActiveInboundEdges(
            beaconId: _beacon,
            recipientId: _recipient,
          ),
          isEmpty,
        );
      },
    );
  });
}

// These barriers change only scheduling. Every query and write still uses
// the production repository, on independent connections to real Postgres.
class _PausedEdges extends ForwardEdgeRepository {
  _PausedEdges(super._database);

  _Barrier? beforeCancel;
  _Barrier? beforeRead;

  @override
  Future<void> cancel(String edgeId, String senderId) async {
    await beforeCancel?.pause();
    await super.cancel(edgeId, senderId);
  }

  @override
  Future<void> markAsRead(String edgeId, String recipientId) async {
    await beforeRead?.pause();
    await super.markAsRead(edgeId, recipientId);
  }
}

class _Barrier {
  final reached = Completer<void>();
  final release = Completer<void>();

  Future<void> pause() async {
    reached.complete();
    await release.future.timeout(kCompletionWait);
  }
}

class _UnusedAttribution extends Fake
    implements ForwardAttributionRepositoryPort {}

class _UnusedVisibility extends Fake
    implements PersonVisibilityRepositoryPort {}

class _UnusedDispatch extends Fake implements AttentionDispatchPort {}
