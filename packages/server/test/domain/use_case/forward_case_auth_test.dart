import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/env.dart';
import 'package:tentura_server/domain/entity/forward_edge_created.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/use_case/forward_case.dart';

import '../../support/fake_beacon_access_guard.dart';
import '../../support/fake_user_block_repository.dart';
import '../../support/test_attention_harness.dart';
import 'forward_case_mocks.mocks.dart';

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
      logger: Logger('ForwardCaseAuthTest'),
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
      return [
        for (var i = 0; i < recipientIds.length; i++)
          ForwardEdgeCreated(
            edgeId: 'E${i + 1}',
            recipientId: recipientIds[i],
          ),
      ];
    });
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

  test('denies forward when sender cannot read beacon content', () async {
    guard.contentAllowed = false;
    await expectLater(
      case_.forward(
        senderId: 'U1',
        beaconId: 'B1',
        recipientIds: ['R1'],
      ),
      throwsA(
        isA<UnauthorizedException>().having(
          (e) => e.description,
          'description',
          'Sender cannot read request content',
        ),
      ),
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

  group('forward — mutual visibility authorization', () {
    void stubMutuallyVisible(Set<String> ids) {
      when(
        personVisibilityRepo.mutuallyVisiblePeerIds(
          viewerId: anyNamed('viewerId'),
          peerIds: anyNamed('peerIds'),
          context: anyNamed('context'),
        ),
      ).thenAnswer((invocation) async {
        final peerIds = invocation.namedArguments[#peerIds] as Iterable<String>;
        return peerIds.where(ids.contains).toSet();
      });
    }

    test('authorized set inserts all remaining recipients', () async {
      stubMutuallyVisible({'R1', 'R2'});

      await case_.forward(
        senderId: 'U1',
        beaconId: 'B1',
        recipientIds: ['R1', 'R2'],
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
      expect(captured, ['R1', 'R2']);
    });

    test('one-way outgoing trust rejects without side effects', () async {
      stubMutuallyVisible({});

      await expectLater(
        case_.forward(
          senderId: 'U1',
          beaconId: 'B1',
          recipientIds: ['R1'],
        ),
        throwsA(
          isA<UnauthorizedException>().having(
            (e) => e.description,
            'description',
            'Direct request routing requires mutual visibility',
          ),
        ),
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
      verifyNever(
        inboxRepo.upsertWatchingForSender(
          senderId: anyNamed('senderId'),
          beaconId: anyNamed('beaconId'),
          context: anyNamed('context'),
        ),
      );
      verifyZeroInteractions(forwardAttributionRepo);
      verifyZeroInteractions(capabilityEvidence);
      expect(attention.recorded, isEmpty);
    });

    test('one-way outgoing MR rejects', () async {
      stubMutuallyVisible({});

      await expectLater(
        case_.forward(
          senderId: 'U1',
          beaconId: 'B1',
          recipientIds: ['Rmr'],
        ),
        throwsA(
          isA<UnauthorizedException>().having(
            (e) => e.description,
            'description',
            'Direct request routing requires mutual visibility',
          ),
        ),
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

    test('one-way incoming trust rejects', () async {
      stubMutuallyVisible({});

      await expectLater(
        case_.forward(
          senderId: 'U1',
          beaconId: 'B1',
          recipientIds: ['Rincoming'],
        ),
        throwsA(
          isA<UnauthorizedException>().having(
            (e) => e.description,
            'description',
            'Direct request routing requires mutual visibility',
          ),
        ),
      );
    });

    test('one-way incoming MR rejects', () async {
      stubMutuallyVisible({});

      await expectLater(
        case_.forward(
          senderId: 'U1',
          beaconId: 'B1',
          recipientIds: ['RincomingMr'],
        ),
        throwsA(
          isA<UnauthorizedException>().having(
            (e) => e.description,
            'description',
            'Direct request routing requires mutual visibility',
          ),
        ),
      );
    });

    test('explicit mutual trust authorizes', () async {
      stubMutuallyVisible({'Rtrust'});

      await case_.forward(
        senderId: 'U1',
        beaconId: 'B1',
        recipientIds: ['Rtrust'],
      );

      verify(
        forwardEdgeRepo.createBatch(
          beaconId: anyNamed('beaconId'),
          senderId: anyNamed('senderId'),
          recipientIds: ['Rtrust'],
          batchId: anyNamed('batchId'),
          noteForRecipient: anyNamed('noteForRecipient'),
          context: anyNamed('context'),
          parentEdgeId: anyNamed('parentEdgeId'),
          onAfterEdgesInserted: anyNamed('onAfterEdgesInserted'),
        ),
      ).called(1);
    });

    test('mutual positive MR authorizes', () async {
      stubMutuallyVisible({'Rmr'});

      await case_.forward(
        senderId: 'U1',
        beaconId: 'B1',
        recipientIds: ['Rmr'],
      );

      verify(
        forwardEdgeRepo.createBatch(
          beaconId: anyNamed('beaconId'),
          senderId: anyNamed('senderId'),
          recipientIds: ['Rmr'],
          batchId: anyNamed('batchId'),
          noteForRecipient: anyNamed('noteForRecipient'),
          context: anyNamed('context'),
          parentEdgeId: anyNamed('parentEdgeId'),
          onAfterEdgesInserted: anyNamed('onAfterEdgesInserted'),
        ),
      ).called(1);
    });

    test('mixed trust and MR mechanisms authorize', () async {
      stubMutuallyVisible({'Rmixed'});

      await case_.forward(
        senderId: 'U1',
        beaconId: 'B1',
        recipientIds: ['Rmixed'],
      );

      verify(
        forwardEdgeRepo.createBatch(
          beaconId: anyNamed('beaconId'),
          senderId: anyNamed('senderId'),
          recipientIds: ['Rmixed'],
          batchId: anyNamed('batchId'),
          noteForRecipient: anyNamed('noteForRecipient'),
          context: anyNamed('context'),
          parentEdgeId: anyNamed('parentEdgeId'),
          onAfterEdgesInserted: anyNamed('onAfterEdgesInserted'),
        ),
      ).called(1);
    });

    test('mixed authorized and unauthorized batch inserts neither', () async {
      stubMutuallyVisible({'Rok'});

      await expectLater(
        case_.forward(
          senderId: 'U1',
          beaconId: 'B1',
          recipientIds: ['Rok', 'Rbad'],
        ),
        throwsA(
          isA<UnauthorizedException>().having(
            (e) => e.description,
            'description',
            'Direct request routing requires mutual visibility',
          ),
        ),
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

    test('authorization uses context coalesced to empty string', () async {
      stubMutuallyVisible({'R1'});

      await case_.forward(
        senderId: 'U1',
        beaconId: 'B1',
        recipientIds: ['R1'],
        context: null,
      );

      verify(
        personVisibilityRepo.mutuallyVisiblePeerIds(
          viewerId: 'U1',
          peerIds: ['R1'],
          context: '',
        ),
      ).called(1);
      verify(
        forwardEdgeRepo.createBatch(
          beaconId: anyNamed('beaconId'),
          senderId: anyNamed('senderId'),
          recipientIds: anyNamed('recipientIds'),
          batchId: anyNamed('batchId'),
          noteForRecipient: anyNamed('noteForRecipient'),
          context: null,
          parentEdgeId: anyNamed('parentEdgeId'),
          onAfterEdgesInserted: anyNamed('onAfterEdgesInserted'),
        ),
      ).called(1);
    });

    test(
      'blocked recipients stay hidden without leaking relationship state',
      () async {
        userBlocks.blockPair('U1', 'Rblocked');
        stubMutuallyVisible({'Rok'});

        await case_.forward(
          senderId: 'U1',
          beaconId: 'B1',
          recipientIds: ['Rblocked', 'Rok'],
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
        expect(captured, ['Rok']);
        verify(
          personVisibilityRepo.mutuallyVisiblePeerIds(
            viewerId: 'U1',
            peerIds: ['Rok'],
            context: '',
          ),
        ).called(1);
      },
    );
  });
}
