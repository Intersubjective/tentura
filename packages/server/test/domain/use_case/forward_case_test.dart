import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/env.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/forward_edge_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/domain/use_case/capability_case.dart';
import 'package:tentura_server/domain/use_case/forward_case.dart';

import 'forward_case_mocks.mocks.dart';
import '../../support/fake_beacon_access_guard.dart';

ForwardEdgeEntity _forwardEdge({
  required String id,
  String beaconId = 'B1',
  String senderId = 'U1',
  String recipientId = 'R1',
  DateTime? cancelledAt,
  DateTime? recipientReadAt,
  DateTime? createdAt,
}) =>
    ForwardEdgeEntity(
      id: id,
      beaconId: beaconId,
      senderId: senderId,
      recipientId: recipientId,
      createdAt: createdAt ?? DateTime.utc(2025),
      cancelledAt: cancelledAt,
      recipientReadAt: recipientReadAt,
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
  late MockHelpOfferRepositoryPort helpOfferRepo;
  late MockInboxRepositoryPort inboxRepo;
  late MockPersonCapabilityEventRepositoryPort capabilityRepo;
  late MockBeaconRepositoryPort beaconRepo;
  late MockBeaconRoomNotificationPort roomPush;
  late FakeBeaconAccessGuard guard;
  late CapabilityCase capabilityCase;
  late ForwardCase case_;

  final now = DateTime.utc(2025);

  setUp(() {
    forwardEdgeRepo = MockForwardEdgeRepositoryPort();
    helpOfferRepo = MockHelpOfferRepositoryPort();
    inboxRepo = MockInboxRepositoryPort();
    capabilityRepo = MockPersonCapabilityEventRepositoryPort();
    beaconRepo = MockBeaconRepositoryPort();
    roomPush = MockBeaconRoomNotificationPort();
    guard = FakeBeaconAccessGuard();

    capabilityCase = CapabilityCase(
      capabilityRepo,
      env: Env(environment: Environment.test),
      logger: Logger('CapabilityCaseTest'),
    );
    case_ = ForwardCase(
      forwardEdgeRepo,
      helpOfferRepo,
      inboxRepo,
      capabilityCase,
      beaconRepo,
      roomPush,
      guard,
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
      roomPush.notifyForwardReceived(
        beaconId: anyNamed('beaconId'),
        senderId: anyNamed('senderId'),
        beaconAuthorId: anyNamed('beaconAuthorId'),
        recipientIds: anyNamed('recipientIds'),
      ),
    ).thenAnswer((_) async {});

    when(
      forwardEdgeRepo.fetchActiveInboundEdges(
        beaconId: anyNamed('beaconId'),
        recipientId: anyNamed('recipientId'),
      ),
    ).thenAnswer((_) async => []);

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
      final onAfter = invocation.namedArguments[#onAfterEdgesInserted]
          as Future<void> Function()?;
      await onAfter?.call();
      return recipientIds;
    });

    when(
      capabilityRepo.insertForwardReasons(
        observerId: anyNamed('observerId'),
        subjectId: anyNamed('subjectId'),
        beaconId: anyNamed('beaconId'),
        slugs: anyNamed('slugs'),
        note: anyNamed('note'),
      ),
    ).thenAnswer((_) async {});
  });

  group('forward — reason routing', () {
    test('no reasons: capability repo is not called', () async {
      await case_.forward(
        senderId: 'U1',
        beaconId: 'B1',
        recipientIds: ['R1', 'R2'],
      );
      verifyZeroInteractions(capabilityRepo);
    });

    test('shared reasons fan out to every recipient', () async {
      await case_.forward(
        senderId: 'U1',
        beaconId: 'B1',
        recipientIds: ['R1', 'R2'],
        sharedReasonSlugs: ['transport', 'tools'],
      );

      verify(
        capabilityRepo.insertForwardReasons(
          observerId: 'U1',
          subjectId: 'R1',
          beaconId: 'B1',
          slugs: ['transport', 'tools'],
        ),
      ).called(1);
      verify(
        capabilityRepo.insertForwardReasons(
          observerId: 'U1',
          subjectId: 'R2',
          beaconId: 'B1',
          slugs: ['transport', 'tools'],
        ),
      ).called(1);
      verifyNoMoreInteractions(capabilityRepo);
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
        capabilityRepo.insertForwardReasons(
          observerId: 'U1',
          subjectId: 'R1',
          beaconId: 'B1',
          slugs: ['calls', 'translation'],
        ),
      ).called(1);
      verify(
        capabilityRepo.insertForwardReasons(
          observerId: 'U1',
          subjectId: 'R2',
          beaconId: 'B1',
          slugs: ['transport'],
        ),
      ).called(1);
      verifyNoMoreInteractions(capabilityRepo);
    });

    test('recipient with empty per-recipient override is skipped', () async {
      await case_.forward(
        senderId: 'U1',
        beaconId: 'B1',
        recipientIds: ['R1', 'R2'],
        sharedReasonSlugs: ['transport'],
        perRecipientReasonSlugs: {
          'R1': [],
        },
      );

      // R1 was overridden with empty list → no event for R1.
      verify(
        capabilityRepo.insertForwardReasons(
          observerId: 'U1',
          subjectId: 'R2',
          beaconId: 'B1',
          slugs: ['transport'],
        ),
      ).called(1);
      verifyNoMoreInteractions(capabilityRepo);
    });
  });

  group('forward — push notifications', () {
    test('notifyForwardReceived is called after successful forward', () async {
      await case_.forward(
        senderId: 'U1',
        beaconId: 'B1',
        recipientIds: ['R1', 'R2'],
      );

      verify(
        roomPush.notifyForwardReceived(
          beaconId: 'B1',
          senderId: 'U1',
          beaconAuthorId: 'Uauthor',
          recipientIds: ['R1', 'R2'],
        ),
      ).called(1);
    });

    test('beacon fetch failure during validation propagates', () async {
      when(
        beaconRepo.getBeaconById(beaconId: 'B1'),
      ).thenThrow(Exception('DB error'));

      await expectLater(
        case_.forward(senderId: 'U1', beaconId: 'B1', recipientIds: ['R1']),
        throwsA(isA<Exception>()),
      );
      verifyNever(
        roomPush.notifyForwardReceived(
          beaconId: anyNamed('beaconId'),
          senderId: anyNamed('senderId'),
          beaconAuthorId: anyNamed('beaconAuthorId'),
          recipientIds: anyNamed('recipientIds'),
        ),
      );
    });

    test('notifyForwardReceived skipped when all recipients are dupes', () async {
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
      ).thenAnswer((_) async => []);

      await case_.forward(
        senderId: 'U1',
        beaconId: 'B1',
        recipientIds: ['R1', 'R2'],
        sharedReasonSlugs: ['transport'],
      );

      verifyNever(
        roomPush.notifyForwardReceived(
          beaconId: anyNamed('beaconId'),
          senderId: anyNamed('senderId'),
          beaconAuthorId: anyNamed('beaconAuthorId'),
          recipientIds: anyNamed('recipientIds'),
        ),
      );
      verifyZeroInteractions(capabilityRepo);
    });
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

    test('records reason slugs when provided', () async {
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
        capabilityRepo.insertForwardReasons(
          observerId: 'U1',
          subjectId: 'R1',
          beaconId: 'B1',
          slugs: ['transport', 'tools'],
        ),
      ).called(1);
    });

    test('still returns true when reason recording fails', () async {
      when(
        capabilityRepo.insertForwardReasons(
          observerId: anyNamed('observerId'),
          subjectId: anyNamed('subjectId'),
          beaconId: anyNamed('beaconId'),
          slugs: anyNamed('slugs'),
          note: anyNamed('note'),
        ),
      ).thenThrow(Exception('capability DB error'));

      expect(
        await case_.updateForward(
          edgeId: 'E1',
          senderId: 'U1',
          note: 'updated note',
          reasonSlugs: ['transport'],
        ),
        isTrue,
      );
      verify(forwardEdgeRepo.updateNote('E1', 'U1', 'updated note')).called(1);
    });
  });

  group('cancelForward — eligibility', () {
    setUp(() {
      when(forwardEdgeRepo.fetchById('E1')).thenAnswer(
        (_) async => _forwardEdge(id: 'E1'),
      );
      when(forwardEdgeRepo.existsWithParent('E1')).thenAnswer((_) async => false);
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

    test('returns false when edge has been forwarded onward', () async {
      when(forwardEdgeRepo.existsWithParent('E1')).thenAnswer((_) async => true);

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

    test('auto-resolves author inbound edge when client parent omitted', () async {
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
    });

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
        _unauthorizedWithDescription('Sender cannot read beacon content'),
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
        _unauthorizedWithDescription('Beacon does not allow forwarding'),
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
}
