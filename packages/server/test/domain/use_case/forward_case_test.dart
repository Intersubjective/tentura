import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/env.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/forward_batch_create_result.dart';
import 'package:tentura_server/domain/entity/forward_delivery_result.dart';
import 'package:tentura_server/domain/entity/forward_edge_created.dart';
import 'package:tentura_server/domain/entity/forward_edge_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/domain/port/capability_evidence_port.dart';
import 'package:tentura_server/domain/use_case/forward_case.dart';

import 'package:tentura_server/domain/port/forward_attribution_repository_port.dart';

import 'forward_case_mocks.mocks.dart';
import '../../support/fake_beacon_access_guard.dart';
import '../../support/fake_user_block_repository.dart';
import '../../support/test_attention_harness.dart';

ForwardEdgeEntity _forwardEdge({
  required String id,
  String beaconId = 'B1',
  String senderId = 'U1',
  String recipientId = 'R1',
  DateTime? cancelledAt,
  DateTime? recipientReadAt,
  bool recipientRejected = false,
  DateTime? createdAt,
}) => ForwardEdgeEntity(
  id: id,
  beaconId: beaconId,
  senderId: senderId,
  recipientId: recipientId,
  createdAt: createdAt ?? DateTime.utc(2025),
  cancelledAt: cancelledAt,
  recipientReadAt: recipientReadAt,
  recipientRejected: recipientRejected,
);

Matcher _unauthorizedWithDescription(String description) => throwsA(
  predicate<UnauthorizedException>(
    (e) =>
        e.description == description &&
        e.code.codeNumber ==
            const AuthExceptionCodes(
              AuthExceptionCode.authUnauthorizedException,
            ).codeNumber,
  ),
);

void main() {
  late MockForwardEdgeRepositoryPort forwardEdgeRepo;
  late MockForwardAttributionRepositoryPort forwardAttributionRepo;
  late MockHelpOfferRepositoryPort helpOfferRepo;
  late MockInboxRepositoryPort inboxRepo;
  late MockCapabilityEvidencePort capabilityEvidence;
  late MockBeaconRepositoryPort beaconRepo;
  late MockPersonVisibilityRepositoryPort personVisibilityRepo;
  late FakeBeaconAccessGuard guard;
  late FakeUserBlockRepository userBlocks;
  late TestAttentionHarness attention;
  late ForwardCase case_;

  final now = DateTime.utc(2025);

  setUp(() {
    forwardEdgeRepo = MockForwardEdgeRepositoryPort();
    forwardAttributionRepo = MockForwardAttributionRepositoryPort();
    helpOfferRepo = MockHelpOfferRepositoryPort();
    inboxRepo = MockInboxRepositoryPort();
    capabilityEvidence = MockCapabilityEvidencePort();
    beaconRepo = MockBeaconRepositoryPort();
    personVisibilityRepo = MockPersonVisibilityRepositoryPort();
    guard = FakeBeaconAccessGuard();
    userBlocks = FakeUserBlockRepository();
    attention = TestAttentionHarness();

    case_ = ForwardCase(
      forwardEdgeRepo,
      forwardAttributionRepo,
      helpOfferRepo,
      inboxRepo,
      capabilityEvidence,
      beaconRepo,
      userBlocks,
      personVisibilityRepo,
      guard,
      attentionIntents: attention.intents,
      attention: attention.transactional,
      env: Env(environment: Environment.test),
      logger: Logger('ForwardCaseTest'),
    );

    when(
      beaconRepo.getBeaconById(beaconId: anyNamed('beaconId')),
    ).thenAnswer(
      (_) async => BeaconEntity(
        id: 'B1',
        title: 'Test beacon',
        author: const UserEntity(id: 'Uauthor'),
        createdAt: now,
        updatedAt: now,
      ),
    );

    when(
      forwardEdgeRepo.fetchActiveInboundEdges(
        beaconId: anyNamed('beaconId'),
        recipientId: anyNamed('recipientId'),
      ),
    ).thenAnswer((_) async => []);

    when(
      forwardEdgeRepo.lockActiveInboundEdges(
        beaconId: anyNamed('beaconId'),
        recipientId: anyNamed('recipientId'),
      ),
    ).thenAnswer((_) async => []);

    when(
      forwardEdgeRepo.countPriorOutgoingBatches(
        beaconId: anyNamed('beaconId'),
        senderId: anyNamed('senderId'),
        batchId: anyNamed('batchId'),
      ),
    ).thenAnswer((_) async => 0);

    when(
      helpOfferRepo.hasActiveHelpOffer(
        beaconId: anyNamed('beaconId'),
        userId: anyNamed('userId'),
      ),
    ).thenAnswer((_) async => false);

    when(
      inboxRepo.upsertWatchingForSender(
        senderId: anyNamed('senderId'),
        beaconId: anyNamed('beaconId'),
        context: anyNamed('context'),
      ),
    ).thenAnswer((_) async {});

    when(
      forwardEdgeRepo.createBatch(
        beaconId: anyNamed('beaconId'),
        senderId: anyNamed('senderId'),
        recipientIds: anyNamed('recipientIds'),
        batchId: anyNamed('batchId'),
        noteForRecipient: anyNamed('noteForRecipient'),
        context: anyNamed('context'),
        parentEdgeId: anyNamed('parentEdgeId'),
        onAfterEdgesInserted: anyNamed('onAfterEdgesInserted'),
      ),
    ).thenAnswer((invocation) async {
      final recipientIds =
          invocation.namedArguments[#recipientIds] as List<String>;
      final onAfter =
          invocation.namedArguments[#onAfterEdgesInserted]
              as Future<void> Function()?;
      await onAfter?.call();
      return ForwardBatchCreateResult(
        createdEdges: [
          for (var i = 0; i < recipientIds.length; i++)
            ForwardEdgeCreated(
              edgeId: 'E${i + 1}',
              recipientId: recipientIds[i],
            ),
        ],
        availabilitySkippedRecipientIds: const [],
      );
    });

    when(
      capabilityEvidence.reconcileForwardReasons(
        forwardEdgeId: anyNamed('forwardEdgeId'),
        observerId: anyNamed('observerId'),
        subjectId: anyNamed('subjectId'),
        slugs: anyNamed('slugs'),
      ),
    ).thenAnswer((_) async {});

    when(
      personVisibilityRepo.mutuallyVisiblePeerIds(
        viewerId: anyNamed('viewerId'),
        peerIds: anyNamed('peerIds'),
        context: anyNamed('context'),
      ),
    ).thenAnswer((invocation) async {
      final peerIds = invocation.namedArguments[#peerIds] as Iterable<String>;
      return peerIds.toSet();
    });
  });

  group('forward — reason routing', () {
    test('no reasons: capability evidence is not reconciled', () async {
      await case_.forward(
        senderId: 'U1',
        beaconId: 'B1',
        recipientIds: ['R1', 'R2'],
      );
      verifyZeroInteractions(capabilityEvidence);
    });

    test('shared reasons fan out to every recipient', () async {
      await case_.forward(
        senderId: 'U1',
        beaconId: 'B1',
        recipientIds: ['R1', 'R2'],
        sharedReasonSlugs: ['transport', 'tools'],
      );

      verify(
        capabilityEvidence.reconcileForwardReasons(
          forwardEdgeId: 'E1',
          observerId: 'U1',
          subjectId: 'R1',
          slugs: ['transport', 'tools'],
        ),
      ).called(1);
      verify(
        capabilityEvidence.reconcileForwardReasons(
          forwardEdgeId: 'E2',
          observerId: 'U1',
          subjectId: 'R2',
          slugs: ['transport', 'tools'],
        ),
      ).called(1);
      verifyNoMoreInteractions(capabilityEvidence);
    });

    test('per-recipient reasons override shared for that recipient', () async {
      await case_.forward(
        senderId: 'U1',
        beaconId: 'B1',
        recipientIds: ['R1', 'R2'],
        sharedReasonSlugs: ['transport'],
        perRecipientReasonSlugs: {
          'R1': ['calls', 'translation'],
        },
      );

      verify(
        capabilityEvidence.reconcileForwardReasons(
          forwardEdgeId: 'E1',
          observerId: 'U1',
          subjectId: 'R1',
          slugs: ['calls', 'translation'],
        ),
      ).called(1);
      verify(
        capabilityEvidence.reconcileForwardReasons(
          forwardEdgeId: 'E2',
          observerId: 'U1',
          subjectId: 'R2',
          slugs: ['transport'],
        ),
      ).called(1);
      verifyNoMoreInteractions(capabilityEvidence);
    });

    test('recipient with empty per-recipient override clears reasons', () async {
      await case_.forward(
        senderId: 'U1',
        beaconId: 'B1',
        recipientIds: ['R1', 'R2'],
        sharedReasonSlugs: ['transport'],
        perRecipientReasonSlugs: {
          'R1': [],
        },
      );

      verify(
        capabilityEvidence.reconcileForwardReasons(
          forwardEdgeId: 'E1',
          observerId: 'U1',
          subjectId: 'R1',
          slugs: const [],
        ),
      ).called(1);
      verify(
        capabilityEvidence.reconcileForwardReasons(
          forwardEdgeId: 'E2',
          observerId: 'U1',
          subjectId: 'R2',
          slugs: ['transport'],
        ),
      ).called(1);
      verifyNoMoreInteractions(capabilityEvidence);
    });
  });

  group('forward — push notifications', () {
    test('notifyForwardReceived is called after successful forward', () async {
      await case_.forward(
        senderId: 'U1',
        beaconId: 'B1',
        recipientIds: ['R1', 'R2'],
      );

      final intent = attention.recorded.single;
      expect(intent.eventType.name, 'relayReceived');
      expect(
        intent.recipients.map((recipient) => recipient.recipientId),
        ['R1', 'R2'],
      );
    });

    test('beacon fetch failure during validation propagates', () async {
      when(
        beaconRepo.getBeaconById(beaconId: 'B1'),
      ).thenThrow(Exception('DB error'));

      await expectLater(
        case_.forward(senderId: 'U1', beaconId: 'B1', recipientIds: ['R1']),
        throwsA(isA<Exception>()),
      );
      expect(attention.recorded, isEmpty);
    });

    test(
      'notifyForwardReceived skipped when all recipients are dupes',
      () async {
        when(
          forwardEdgeRepo.createBatch(
            beaconId: anyNamed('beaconId'),
            senderId: anyNamed('senderId'),
            recipientIds: anyNamed('recipientIds'),
            batchId: anyNamed('batchId'),
            noteForRecipient: anyNamed('noteForRecipient'),
            context: anyNamed('context'),
            parentEdgeId: anyNamed('parentEdgeId'),
            onAfterEdgesInserted: anyNamed('onAfterEdgesInserted'),
          ),
        ).thenAnswer((_) async => const ForwardBatchCreateResult(
          createdEdges: [],
          availabilitySkippedRecipientIds: [],
        ));

        await case_.forward(
          senderId: 'U1',
          beaconId: 'B1',
          recipientIds: ['R1', 'R2'],
          sharedReasonSlugs: ['transport'],
        );

        expect(attention.recorded, isEmpty);
        verifyZeroInteractions(capabilityEvidence);
      },
    );
  });

  group('updateForward — eligibility', () {
    setUp(() {
      when(forwardEdgeRepo.fetchById('E1')).thenAnswer(
        (_) async => _forwardEdge(id: 'E1'),
      );
      when(
        forwardEdgeRepo.updateNote('E1', 'U1', any),
      ).thenAnswer((_) async {});
    });

    test('returns false when edge is not found', () async {
      when(forwardEdgeRepo.fetchById('Emissing')).thenAnswer((_) async => null);

      expect(
        await case_.updateForward(
          edgeId: 'Emissing',
          senderId: 'U1',
          note: 'updated',
        ),
        isFalse,
      );
      verifyNever(forwardEdgeRepo.updateNote(any, any, any));
    });

    test('returns false when sender does not own edge', () async {
      expect(
        await case_.updateForward(
          edgeId: 'E1',
          senderId: 'Uother',
          note: 'updated',
        ),
        isFalse,
      );
      verifyNever(forwardEdgeRepo.updateNote(any, any, any));
    });

    test('returns false when edge is cancelled', () async {
      when(forwardEdgeRepo.fetchById('E1')).thenAnswer(
        (_) async => _forwardEdge(
          id: 'E1',
          cancelledAt: DateTime.utc(2025, 6, 1),
        ),
      );

      expect(
        await case_.updateForward(
          edgeId: 'E1',
          senderId: 'U1',
          note: 'updated',
        ),
        isFalse,
      );
      verifyNever(forwardEdgeRepo.updateNote(any, any, any));
    });

    test('updates note and returns true', () async {
      expect(
        await case_.updateForward(
          edgeId: 'E1',
          senderId: 'U1',
          note: 'updated note',
        ),
        isTrue,
      );
      verify(forwardEdgeRepo.updateNote('E1', 'U1', 'updated note')).called(1);
    });

    test('reconciles reason slugs when provided', () async {
      expect(
        await case_.updateForward(
          edgeId: 'E1',
          senderId: 'U1',
          note: 'updated note',
          reasonSlugs: ['transport', 'tools'],
        ),
        isTrue,
      );
      verify(
        capabilityEvidence.reconcileForwardReasons(
          forwardEdgeId: 'E1',
          observerId: 'U1',
          subjectId: 'R1',
          slugs: ['transport', 'tools'],
        ),
      ).called(1);
    });

    test('null reasonSlugs skips reconciliation', () async {
      expect(
        await case_.updateForward(
          edgeId: 'E1',
          senderId: 'U1',
          note: 'updated note',
        ),
        isTrue,
      );
      verifyNever(
        capabilityEvidence.reconcileForwardReasons(
          forwardEdgeId: anyNamed('forwardEdgeId'),
          observerId: anyNamed('observerId'),
          subjectId: anyNamed('subjectId'),
          slugs: anyNamed('slugs'),
        ),
      );
    });

    test('reason reconciliation failure propagates', () async {
      when(
        capabilityEvidence.reconcileForwardReasons(
          forwardEdgeId: anyNamed('forwardEdgeId'),
          observerId: anyNamed('observerId'),
          subjectId: anyNamed('subjectId'),
          slugs: anyNamed('slugs'),
        ),
      ).thenThrow(Exception('capability DB error'));

      await expectLater(
        case_.updateForward(
          edgeId: 'E1',
          senderId: 'U1',
          note: 'updated note',
          reasonSlugs: ['transport'],
        ),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('cancelForward — eligibility', () {
    setUp(() {
      when(forwardEdgeRepo.fetchById('E1')).thenAnswer(
        (_) async => _forwardEdge(id: 'E1'),
      );
      when(
        forwardEdgeRepo.existsWithParent('E1'),
      ).thenAnswer((_) async => false);
      when(forwardEdgeRepo.cancel('E1', 'U1')).thenAnswer((_) async {});
      when(
        inboxRepo.markForwardCancelledForRecipient(
          beaconId: anyNamed('beaconId'),
          recipientId: anyNamed('recipientId'),
        ),
      ).thenAnswer((_) async {});
    });

    test('returns false when edge is not found', () async {
      when(forwardEdgeRepo.fetchById('Emissing')).thenAnswer((_) async => null);

      expect(
        await case_.cancelForward(edgeId: 'Emissing', senderId: 'U1'),
        isFalse,
      );
      verifyNever(forwardEdgeRepo.cancel(any, any));
    });

    test('returns false when sender does not own edge', () async {
      expect(
        await case_.cancelForward(edgeId: 'E1', senderId: 'Uother'),
        isFalse,
      );
      verifyNever(forwardEdgeRepo.cancel(any, any));
    });

    test('returns false when edge is already cancelled', () async {
      when(forwardEdgeRepo.fetchById('E1')).thenAnswer(
        (_) async => _forwardEdge(
          id: 'E1',
          cancelledAt: DateTime.utc(2025, 6, 1),
        ),
      );

      expect(
        await case_.cancelForward(edgeId: 'E1', senderId: 'U1'),
        isFalse,
      );
      verifyNever(forwardEdgeRepo.cancel(any, any));
    });

    test('returns false when recipient has read the forward', () async {
      when(forwardEdgeRepo.fetchById('E1')).thenAnswer(
        (_) async => _forwardEdge(
          id: 'E1',
          recipientReadAt: DateTime.utc(2025, 6, 1),
        ),
      );

      expect(
        await case_.cancelForward(edgeId: 'E1', senderId: 'U1'),
        isFalse,
      );
      verifyNever(forwardEdgeRepo.cancel(any, any));
    });

    test('returns false when recipientRejected', () async {
      when(forwardEdgeRepo.fetchById('E1')).thenAnswer(
        (_) async => _forwardEdge(
          id: 'E1',
          recipientRejected: true,
        ),
      );

      expect(
        await case_.cancelForward(edgeId: 'E1', senderId: 'U1'),
        isFalse,
      );
      verifyNever(forwardEdgeRepo.cancel(any, any));
    });

    test('returns false when edge has been forwarded onward', () async {
      when(
        forwardEdgeRepo.existsWithParent('E1'),
      ).thenAnswer((_) async => true);

      expect(
        await case_.cancelForward(edgeId: 'E1', senderId: 'U1'),
        isFalse,
      );
      verifyNever(forwardEdgeRepo.cancel(any, any));
    });

    test('returns false when recipient has active help offer', () async {
      when(
        helpOfferRepo.hasActiveHelpOffer(
          beaconId: 'B1',
          userId: 'R1',
        ),
      ).thenAnswer((_) async => true);

      expect(
        await case_.cancelForward(edgeId: 'E1', senderId: 'U1'),
        isFalse,
      );
      verifyNever(forwardEdgeRepo.cancel(any, any));
    });

    test('cancels edge and marks inbox when eligible', () async {
      expect(
        await case_.cancelForward(edgeId: 'E1', senderId: 'U1'),
        isTrue,
      );
      verify(forwardEdgeRepo.cancel('E1', 'U1')).called(1);
      verify(
        inboxRepo.markForwardCancelledForRecipient(
          beaconId: 'B1',
          recipientId: 'R1',
        ),
      ).called(1);
    });
  });

  group('forward — parentEdgeId lineage', () {
    test('passes validated client parentEdgeId to createBatch', () async {
      when(
        forwardEdgeRepo.fetchActiveInboundEdges(
          beaconId: 'B1',
          recipientId: 'U1',
        ),
      ).thenAnswer(
        (_) async => [
          _forwardEdge(
            id: 'Eauthor',
            senderId: 'Uauthor',
            recipientId: 'U1',
          ),
        ],
      );

      await case_.forward(
        senderId: 'U1',
        beaconId: 'B1',
        recipientIds: ['R1'],
        parentEdgeId: 'Eauthor',
      );

      verify(
        forwardEdgeRepo.createBatch(
          beaconId: 'B1',
          senderId: 'U1',
          recipientIds: ['R1'],
          batchId: anyNamed('batchId'),
          noteForRecipient: anyNamed('noteForRecipient'),
          context: anyNamed('context'),
          parentEdgeId: 'Eauthor',
          onAfterEdgesInserted: anyNamed('onAfterEdgesInserted'),
        ),
      ).called(1);
    });

    test(
      'auto-resolves author inbound edge when client parent omitted',
      () async {
        when(
          forwardEdgeRepo.fetchActiveInboundEdges(
            beaconId: 'B1',
            recipientId: 'U1',
          ),
        ).thenAnswer(
          (_) async => [
            _forwardEdge(
              id: 'Ehop',
              senderId: 'Uhop',
              recipientId: 'U1',
              createdAt: DateTime.utc(2025, 2, 1),
            ),
            _forwardEdge(
              id: 'Eauthor',
              senderId: 'Uauthor',
              recipientId: 'U1',
              createdAt: DateTime.utc(2025, 1, 1),
            ),
          ],
        );

        await case_.forward(
          senderId: 'U1',
          beaconId: 'B1',
          recipientIds: ['R1'],
        );

        verify(
          forwardEdgeRepo.createBatch(
            beaconId: anyNamed('beaconId'),
            senderId: anyNamed('senderId'),
            recipientIds: anyNamed('recipientIds'),
            batchId: anyNamed('batchId'),
            noteForRecipient: anyNamed('noteForRecipient'),
            context: anyNamed('context'),
            parentEdgeId: 'Eauthor',
            onAfterEdgesInserted: anyNamed('onAfterEdgesInserted'),
          ),
        ).called(1);
      },
    );

    test('rejects invalid client parentEdgeId', () async {
      when(
        forwardEdgeRepo.fetchActiveInboundEdges(
          beaconId: 'B1',
          recipientId: 'U1',
        ),
      ).thenAnswer(
        (_) async => [
          _forwardEdge(
            id: 'E1',
            senderId: 'Uauthor',
            recipientId: 'Uother',
          ),
        ],
      );

      await expectLater(
        case_.forward(
          senderId: 'U1',
          beaconId: 'B1',
          recipientIds: ['R1'],
          parentEdgeId: 'Enope',
        ),
        _unauthorizedWithDescription('Invalid parent forward edge for sender'),
      );
      verifyNever(
        forwardEdgeRepo.createBatch(
          beaconId: anyNamed('beaconId'),
          senderId: anyNamed('senderId'),
          recipientIds: anyNamed('recipientIds'),
          batchId: anyNamed('batchId'),
          noteForRecipient: anyNamed('noteForRecipient'),
          context: anyNamed('context'),
          parentEdgeId: anyNamed('parentEdgeId'),
          onAfterEdgesInserted: anyNamed('onAfterEdgesInserted'),
        ),
      );
    });
  });

  group('forward — access guard failures', () {
    test('denies when sender cannot read beacon content', () async {
      guard.contentAllowed = false;

      await expectLater(
        case_.forward(
          senderId: 'U1',
          beaconId: 'B1',
          recipientIds: ['R1'],
        ),
        _unauthorizedWithDescription('Sender cannot read request content'),
      );
      verifyNever(
        forwardEdgeRepo.createBatch(
          beaconId: anyNamed('beaconId'),
          senderId: anyNamed('senderId'),
          recipientIds: anyNamed('recipientIds'),
          batchId: anyNamed('batchId'),
          noteForRecipient: anyNamed('noteForRecipient'),
          context: anyNamed('context'),
          parentEdgeId: anyNamed('parentEdgeId'),
          onAfterEdgesInserted: anyNamed('onAfterEdgesInserted'),
        ),
      );
    });

    test('denies when beacon does not allow forwarding', () async {
      when(
        beaconRepo.getBeaconById(beaconId: anyNamed('beaconId')),
      ).thenAnswer(
        (_) async => BeaconEntity(
          id: 'B1',
          title: 'Closed beacon',
          author: const UserEntity(id: 'Uauthor'),
          createdAt: now,
          updatedAt: now,
          status: BeaconStatus.closed,
        ),
      );

      await expectLater(
        case_.forward(
          senderId: 'U1',
          beaconId: 'B1',
          recipientIds: ['R1'],
        ),
        _unauthorizedWithDescription('Request does not allow forwarding'),
      );
      verifyNever(
        forwardEdgeRepo.createBatch(
          beaconId: anyNamed('beaconId'),
          senderId: anyNamed('senderId'),
          recipientIds: anyNamed('recipientIds'),
          batchId: anyNamed('batchId'),
          noteForRecipient: anyNamed('noteForRecipient'),
          context: anyNamed('context'),
          parentEdgeId: anyNamed('parentEdgeId'),
          onAfterEdgesInserted: anyNamed('onAfterEdgesInserted'),
        ),
      );
    });
  });

  group('forward — blocked recipients (E2)', () {
    test('drops recipient when sender blocked them', () async {
      userBlocks.blockPair('U1', 'Rblocked');

      await case_.forward(
        senderId: 'U1',
        beaconId: 'B1',
        recipientIds: ['Rblocked', 'Rok'],
      );

      final captured =
          verify(
                forwardEdgeRepo.createBatch(
                  beaconId: 'B1',
                  senderId: 'U1',
                  recipientIds: captureAnyNamed('recipientIds'),
                  batchId: anyNamed('batchId'),
                  noteForRecipient: anyNamed('noteForRecipient'),
                  context: anyNamed('context'),
                  parentEdgeId: anyNamed('parentEdgeId'),
                  onAfterEdgesInserted: anyNamed('onAfterEdgesInserted'),
                ),
              ).captured.single
              as List<String>;
      expect(captured, ['Rok']);
    });

    test('drops recipient when they blocked sender', () async {
      userBlocks.blockPair('Rblocked', 'U1');

      await case_.forward(
        senderId: 'U1',
        beaconId: 'B1',
        recipientIds: ['Rblocked'],
      );

      final captured =
          verify(
                forwardEdgeRepo.createBatch(
                  beaconId: anyNamed('beaconId'),
                  senderId: anyNamed('senderId'),
                  recipientIds: captureAnyNamed('recipientIds'),
                  batchId: anyNamed('batchId'),
                  noteForRecipient: anyNamed('noteForRecipient'),
                  context: anyNamed('context'),
                  parentEdgeId: anyNamed('parentEdgeId'),
                  onAfterEdgesInserted: anyNamed('onAfterEdgesInserted'),
                ),
              ).captured.single
              as List<String>;
      expect(captured, isEmpty);
    });
  });

  group('forward — inbox watching', () {
    test('upserts watching for sender when no active help offer', () async {
      await case_.forward(
        senderId: 'U1',
        beaconId: 'B1',
        recipientIds: ['R1'],
        context: 'ctx',
      );

      verify(
        inboxRepo.upsertWatchingForSender(
          senderId: 'U1',
          beaconId: 'B1',
          context: 'ctx',
        ),
      ).called(1);
    });

    test('skips watching when sender has active help offer', () async {
      when(
        helpOfferRepo.hasActiveHelpOffer(
          beaconId: 'B1',
          userId: 'U1',
        ),
      ).thenAnswer((_) async => true);

      await case_.forward(
        senderId: 'U1',
        beaconId: 'B1',
        recipientIds: ['R1'],
      );

      verifyNever(
        inboxRepo.upsertWatchingForSender(
          senderId: anyNamed('senderId'),
          beaconId: anyNamed('beaconId'),
          context: anyNamed('context'),
        ),
      );
    });
  });

  group('forward — band provenance telemetry (G1a)', () {
    test('logs conversion counts by tier and exploration, no recipient ids', () async {
      final records = <LogRecord>[];
      Logger('ForwardCaseTest').onRecord.listen(records.add);

      await case_.forward(
        senderId: 'U1',
        beaconId: 'B1',
        recipientIds: ['R1', 'R2', 'R3'],
        perRecipientBandProvenance: {
          'R1': (tier: 'networkOutcome', isExploration: false),
          'R2': (tier: null, isExploration: true),
          // R3 intentionally omitted: not selected from the band.
        },
      );

      final conversionRecords = records.where(
        (r) => r.message.startsWith('forward_band_conversion'),
      );
      expect(conversionRecords, hasLength(1));
      final message = conversionRecords.single.message;
      expect(message, contains('beacon=B1'));
      expect(message, contains('networkOutcome=1'));
      expect(message, contains('exploration=1'));
      expect(message, contains('main_list=1'));
      expect(message, isNot(contains('R1')));
      expect(message, isNot(contains('R2')));
      expect(message, isNot(contains('R3')));
    });

    test('does not log band conversion when provenance is omitted', () async {
      final records = <LogRecord>[];
      Logger('ForwardCaseTest').onRecord.listen(records.add);

      await case_.forward(
        senderId: 'U1',
        beaconId: 'B1',
        recipientIds: ['R1'],
      );

      expect(
        records.where((r) => r.message.startsWith('forward_band_conversion')),
        isEmpty,
      );
    });
  });

  group('forward — availability delivery result', () {
    test('returns typed result with batch id and delivery lists', () async {
      when(
        forwardEdgeRepo.createBatch(
          beaconId: anyNamed('beaconId'),
          senderId: anyNamed('senderId'),
          recipientIds: anyNamed('recipientIds'),
          batchId: captureAnyNamed('batchId'),
          noteForRecipient: anyNamed('noteForRecipient'),
          context: anyNamed('context'),
          parentEdgeId: anyNamed('parentEdgeId'),
          onAfterEdgesInserted: anyNamed('onAfterEdgesInserted'),
        ),
      ).thenAnswer((invocation) async {
        final recipientIds =
            invocation.namedArguments[#recipientIds] as List<String>;
        return ForwardBatchCreateResult(
          createdEdges: [
            ForwardEdgeCreated(edgeId: 'E1', recipientId: recipientIds.first),
          ],
          availabilitySkippedRecipientIds: [recipientIds.last],
        );
      });

      final result = await case_.forward(
        senderId: 'U1',
        beaconId: 'B1',
        recipientIds: ['R1', 'R2'],
      );

      final batchId =
          verify(
                forwardEdgeRepo.createBatch(
                  beaconId: anyNamed('beaconId'),
                  senderId: anyNamed('senderId'),
                  recipientIds: anyNamed('recipientIds'),
                  batchId: captureAnyNamed('batchId'),
                  noteForRecipient: anyNamed('noteForRecipient'),
                  context: anyNamed('context'),
                  parentEdgeId: anyNamed('parentEdgeId'),
                  onAfterEdgesInserted: anyNamed('onAfterEdgesInserted'),
                ),
              ).captured.single
              as String;
      expect(
        result,
        ForwardDeliveryResult(
          batchId: batchId,
          deliveredRecipientIds: ['R1'],
          availabilitySkippedRecipientIds: ['R2'],
        ),
      );
    });

    test('preserves repository delivery and skip order in typed result', () async {
      when(
        forwardEdgeRepo.createBatch(
          beaconId: anyNamed('beaconId'),
          senderId: anyNamed('senderId'),
          recipientIds: anyNamed('recipientIds'),
          batchId: anyNamed('batchId'),
          noteForRecipient: anyNamed('noteForRecipient'),
          context: anyNamed('context'),
          parentEdgeId: anyNamed('parentEdgeId'),
          onAfterEdgesInserted: anyNamed('onAfterEdgesInserted'),
        ),
      ).thenAnswer(
        (_) async => const ForwardBatchCreateResult(
          createdEdges: [
            ForwardEdgeCreated(edgeId: 'E1', recipientId: 'R1'),
            ForwardEdgeCreated(edgeId: 'E3', recipientId: 'R3'),
          ],
          availabilitySkippedRecipientIds: ['R2', 'R4'],
        ),
      );

      final result = await case_.forward(
        senderId: 'U1',
        beaconId: 'B1',
        recipientIds: ['R1', 'R2', 'R3', 'R4'],
      );

      expect(result.deliveredRecipientIds, ['R1', 'R3']);
      expect(result.availabilitySkippedRecipientIds, ['R2', 'R4']);
    });

    test('downstream effects only include delivered recipient ids', () async {
      when(
        forwardEdgeRepo.createBatch(
          beaconId: anyNamed('beaconId'),
          senderId: anyNamed('senderId'),
          recipientIds: anyNamed('recipientIds'),
          batchId: anyNamed('batchId'),
          noteForRecipient: anyNamed('noteForRecipient'),
          context: anyNamed('context'),
          parentEdgeId: anyNamed('parentEdgeId'),
          onAfterEdgesInserted: anyNamed('onAfterEdgesInserted'),
        ),
      ).thenAnswer(
        (_) async => const ForwardBatchCreateResult(
          createdEdges: [
            ForwardEdgeCreated(edgeId: 'E1', recipientId: 'Rdelivered'),
          ],
          availabilitySkippedRecipientIds: ['Rskipped'],
        ),
      );

      await case_.forward(
        senderId: 'U1',
        beaconId: 'B1',
        recipientIds: ['Rdelivered', 'Rskipped'],
        sharedReasonSlugs: ['transport'],
      );

      verify(
        capabilityEvidence.reconcileForwardReasons(
          forwardEdgeId: 'E1',
          observerId: 'U1',
          subjectId: 'Rdelivered',
          slugs: ['transport'],
        ),
      ).called(1);
      verifyNever(
        capabilityEvidence.reconcileForwardReasons(
          forwardEdgeId: anyNamed('forwardEdgeId'),
          observerId: anyNamed('observerId'),
          subjectId: 'Rskipped',
          slugs: anyNamed('slugs'),
        ),
      );

      final intent = attention.recorded.single;
      expect(
        intent.recipients.map((recipient) => recipient.recipientId),
        ['Rdelivered'],
      );
    });

    test('active-edge duplicate is not reported as availability skipped', () async {
      when(
        forwardEdgeRepo.createBatch(
          beaconId: anyNamed('beaconId'),
          senderId: anyNamed('senderId'),
          recipientIds: anyNamed('recipientIds'),
          batchId: anyNamed('batchId'),
          noteForRecipient: anyNamed('noteForRecipient'),
          context: anyNamed('context'),
          parentEdgeId: anyNamed('parentEdgeId'),
          onAfterEdgesInserted: anyNamed('onAfterEdgesInserted'),
        ),
      ).thenAnswer(
        (_) async => const ForwardBatchCreateResult(
          createdEdges: [],
          availabilitySkippedRecipientIds: [],
        ),
      );

      final result = await case_.forward(
        senderId: 'U1',
        beaconId: 'B1',
        recipientIds: ['Rdup'],
      );

      expect(result.deliveredRecipientIds, isEmpty);
      expect(result.availabilitySkippedRecipientIds, isEmpty);
      expect(attention.recorded, isEmpty);
    });

    test('limited-only skip list stays empty when edge is delivered', () async {
      when(
        forwardEdgeRepo.createBatch(
          beaconId: anyNamed('beaconId'),
          senderId: anyNamed('senderId'),
          recipientIds: anyNamed('recipientIds'),
          batchId: anyNamed('batchId'),
          noteForRecipient: anyNamed('noteForRecipient'),
          context: anyNamed('context'),
          parentEdgeId: anyNamed('parentEdgeId'),
          onAfterEdgesInserted: anyNamed('onAfterEdgesInserted'),
        ),
      ).thenAnswer(
        (_) async => const ForwardBatchCreateResult(
          createdEdges: [
            ForwardEdgeCreated(edgeId: 'E1', recipientId: 'Rlimited'),
          ],
          availabilitySkippedRecipientIds: [],
        ),
      );

      final result = await case_.forward(
        senderId: 'U1',
        beaconId: 'B1',
        recipientIds: ['Rlimited'],
      );

      expect(result.deliveredRecipientIds, ['Rlimited']);
      expect(result.availabilitySkippedRecipientIds, isEmpty);
    });
  });
}
