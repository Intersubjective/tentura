import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/env.dart';
import 'package:tentura_server/domain/use_case/capability_case.dart';
import 'package:tentura_server/domain/use_case/forward_case.dart';

import 'forward_case_mocks.mocks.dart';

void main() {
  late MockForwardEdgeRepositoryPort forwardEdgeRepo;
  late MockCommitmentRepositoryPort commitmentRepo;
  late MockInboxRepositoryPort inboxRepo;
  late MockPersonCapabilityEventRepositoryPort capabilityRepo;
  late CapabilityCase capabilityCase;
  late ForwardCase case_;

  setUp(() {
    forwardEdgeRepo = MockForwardEdgeRepositoryPort();
    commitmentRepo = MockCommitmentRepositoryPort();
    inboxRepo = MockInboxRepositoryPort();
    capabilityRepo = MockPersonCapabilityEventRepositoryPort();

    capabilityCase = CapabilityCase(
      capabilityRepo,
      env: Env(environment: Environment.test),
      logger: Logger('CapabilityCaseTest'),
    );
    case_ = ForwardCase(
      forwardEdgeRepo,
      commitmentRepo,
      inboxRepo,
      capabilityCase,
      env: Env(environment: Environment.test),
      logger: Logger('ForwardCaseTest'),
    );

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
    ).thenAnswer((_) async {});

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
}
