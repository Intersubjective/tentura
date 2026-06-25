import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/env.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/use_case/forward_case.dart';
import 'package:tentura_server/domain/use_case/capability_case.dart';

import '../../support/fake_beacon_access_guard.dart';
import 'forward_case_mocks.mocks.dart';

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
      return recipientIds;
    });
    when(
      roomPush.notifyForwardReceived(
        beaconId: anyNamed('beaconId'),
        senderId: anyNamed('senderId'),
        beaconAuthorId: anyNamed('beaconAuthorId'),
        recipientIds: anyNamed('recipientIds'),
      ),
    ).thenAnswer((_) async {});
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
          'Sender cannot read beacon content',
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
}
