import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/domain/use_case/commitment_case.dart';

import 'commitment_case_mocks.mocks.dart';

void main() {
  late MockBeaconRepository beaconRepo;
  late MockCommitmentRepository commitmentRepo;
  late MockCoordinationRepository coordinationRepo;
  late CommitmentCase case_;

  final now = DateTime.utc(2025, 1, 1);
  BeaconEntity beacon({
    required String id,
    required int state,
    String authorId = 'Uauth',
  }) =>
      BeaconEntity(
        id: id,
        title: 't',
        author: UserEntity(id: authorId),
        createdAt: now,
        updatedAt: now,
        state: state,
      );

  void stubBeacon(BeaconEntity b) {
    when(
      beaconRepo.getBeaconById(beaconId: b.id, filterByUserId: null),
    ).thenAnswer((_) async => b);
  }

  setUp(() {
    beaconRepo = MockBeaconRepository();
    commitmentRepo = MockCommitmentRepository();
    coordinationRepo = MockCoordinationRepository();
    case_ = CommitmentCase(commitmentRepo, beaconRepo, coordinationRepo);
  });

  group('withdraw lifecycle', () {
    test('rejects CLOSED (1)', () async {
      stubBeacon(beacon(id: 'B1', state: 1));

      await expectLater(
        case_.withdraw(
          beaconId: 'B1',
          userId: 'U1',
          uncommitReason: 'other',
        ),
        throwsA(
          isA<CommitmentCoordinationException>().having(
            (e) =>
                (e.code as CommitmentCoordinationExceptionCodes).exceptionCode,
            'code',
            CommitmentCoordinationExceptionCode.beaconWithdrawForbidden,
          ),
        ),
      );
      verifyZeroInteractions(commitmentRepo);
    });

    test('rejects DELETED (2)', () async {
      stubBeacon(beacon(id: 'B1', state: 2));

      await expectLater(
        case_.withdraw(
          beaconId: 'B1',
          userId: 'U1',
          uncommitReason: 'other',
        ),
        throwsA(isA<CommitmentCoordinationException>()),
      );
    });

    test('rejects DRAFT (3)', () async {
      stubBeacon(beacon(id: 'B1', state: 3));

      await expectLater(
        case_.withdraw(
          beaconId: 'B1',
          userId: 'U1',
          uncommitReason: 'other',
        ),
        throwsA(isA<CommitmentCoordinationException>()),
      );
    });

    test('rejects CLOSED_REVIEW_COMPLETE (6)', () async {
      stubBeacon(beacon(id: 'B1', state: 6));

      await expectLater(
        case_.withdraw(
          beaconId: 'B1',
          userId: 'U1',
          uncommitReason: 'other',
        ),
        throwsA(isA<CommitmentCoordinationException>()),
      );
    });

    test('allows OPEN (0)', () async {
      stubBeacon(beacon(id: 'B1', state: 0));
      when(
        coordinationRepo.deleteForCommit(beaconId: 'B1', userId: 'U1'),
      ).thenAnswer((_) async {});
      when(
        commitmentRepo.withdraw(
          beaconId: 'B1',
          userId: 'U1',
          uncommitReason: 'other',
          message: '',
        ),
      ).thenAnswer((_) async {});
      when(
        coordinationRepo.recomputeAndPersistBeaconCoordinationStatus('B1'),
      ).thenAnswer((_) async {});

      await case_.withdraw(
        beaconId: 'B1',
        userId: 'U1',
        uncommitReason: 'other',
      );

      verify(
        commitmentRepo.withdraw(
          beaconId: 'B1',
          userId: 'U1',
          uncommitReason: 'other',
          message: '',
        ),
      ).called(1);
    });

    test('allows PENDING_REVIEW (4) and CLOSED_REVIEW_OPEN (5)', () async {
      for (final state in [4, 5]) {
        reset(beaconRepo);
        reset(commitmentRepo);
        reset(coordinationRepo);
        stubBeacon(beacon(id: 'B1', state: state));
        when(
          coordinationRepo.deleteForCommit(beaconId: 'B1', userId: 'U1'),
        ).thenAnswer((_) async {});
        when(
          commitmentRepo.withdraw(
            beaconId: 'B1',
            userId: 'U1',
            uncommitReason: 'timing',
            message: '',
          ),
        ).thenAnswer((_) async {});
        when(
          coordinationRepo.recomputeAndPersistBeaconCoordinationStatus('B1'),
        ).thenAnswer((_) async {});

        await case_.withdraw(
          beaconId: 'B1',
          userId: 'U1',
          uncommitReason: 'timing',
        );
        verify(
          commitmentRepo.withdraw(
            beaconId: 'B1',
            userId: 'U1',
            uncommitReason: 'timing',
            message: '',
          ),
        ).called(1);
      }
    });
  });

  group('commit', () {
    test('rejects when beacon not OPEN', () async {
      stubBeacon(beacon(id: 'B1', state: 1));

      await expectLater(
        case_.commit(beaconId: 'B1', userId: 'U1'),
        throwsA(
          isA<CommitmentCoordinationException>().having(
            (e) =>
                (e.code as CommitmentCoordinationExceptionCodes).exceptionCode,
            'code',
            CommitmentCoordinationExceptionCode.beaconNotOpen,
          ),
        ),
      );
    });

    test('rejects author on initial commit', () async {
      stubBeacon(beacon(id: 'B1', state: 0, authorId: 'Uauth'));
      when(
        commitmentRepo.hasActiveCommitment(
          beaconId: 'B1',
          userId: 'Uauth',
        ),
      ).thenAnswer((_) async => false);

      await expectLater(
        case_.commit(beaconId: 'B1', userId: 'Uauth'),
        throwsA(
          isA<CommitmentCoordinationException>().having(
            (e) =>
                (e.code as CommitmentCoordinationExceptionCodes).exceptionCode,
            'code',
            CommitmentCoordinationExceptionCode.authorCannotCommit,
          ),
        ),
      );
      verifyNever(
        commitmentRepo.upsert(
          beaconId: 'B1',
          userId: 'Uauth',
          message: '',
          helpType: null,
        ),
      );
    });

    test('allows upsert when already committed (update note)', () async {
      stubBeacon(beacon(id: 'B1', state: 0));
      when(
        commitmentRepo.hasActiveCommitment(
          beaconId: 'B1',
          userId: 'U1',
        ),
      ).thenAnswer((_) async => true);
      when(
        commitmentRepo.upsert(
          beaconId: 'B1',
          userId: 'U1',
          message: 'updated',
          helpType: null,
        ),
      ).thenAnswer((_) async {});
      when(
        coordinationRepo.recomputeAndPersistBeaconCoordinationStatus('B1'),
      ).thenAnswer((_) async {});

      await case_.commit(beaconId: 'B1', userId: 'U1', message: 'updated');

      verify(
        commitmentRepo.upsert(
          beaconId: 'B1',
          userId: 'U1',
          message: 'updated',
          helpType: null,
        ),
      ).called(1);
    });
  });
}
