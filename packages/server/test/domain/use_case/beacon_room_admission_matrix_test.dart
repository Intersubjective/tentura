import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/domain/coordination/coordination_response_type.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/help_offer_admission_event.dart';
import 'package:tentura_server/domain/entity/beacon_room_record.dart';
import 'package:tentura_server/domain/entity/gql_public/help_offer_with_coordination_row.dart';
import 'package:tentura_server/domain/entity/gql_public/user_public_record.dart';
import 'package:tentura_server/domain/entity/help_offer_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/domain/port/beacon_fact_card_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_room_notification_port.dart';
import 'package:tentura_server/domain/port/beacon_room_repository_port.dart';
import 'package:tentura_server/domain/port/evaluation_repository_port.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/polling_repository_port.dart';
import 'package:tentura_server/domain/port/remote_storage_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/port/upload_quota_repository_port.dart';
import 'package:tentura_server/domain/use_case/beacon_room_case.dart';
import 'package:tentura_server/domain/use_case/capability_case.dart';
import 'package:tentura_server/domain/use_case/coordination_case.dart';
import 'package:tentura_server/domain/use_case/help_offer_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/coordination_item_record_fixtures.dart';
import '../../support/fake_beacon_access_guard.dart';
import '../../support/noop_beacon_room_notification_port.dart';
import 'help_offer_case_mocks.mocks.dart';

const _beaconId = 'Bbbbbbbbbbbbb';
const _authorId = 'Uauthor000001';
const _stewardId = 'Usteward00001';
const _helperId = 'Uhelper000001';
const _outsiderId = 'Uoutsider0001';

final _now = DateTime.utc(2025);

BeaconEntity _beacon({BeaconStatus status = BeaconStatus.open}) => BeaconEntity(
  id: _beaconId,
  title: 't',
  author: UserEntity(id: _authorId),
  createdAt: _now,
  updatedAt: _now,
  status: status,
);

HelpOfferEntity _activeOffer() => HelpOfferEntity(
  beaconId: _beaconId,
  userId: _helperId,
  createdAt: _now,
  updatedAt: _now,
);

class _AdmitStubRoom extends Fake implements BeaconRoomRepositoryPort {
  _AdmitStubRoom({
    this.authorIds = const {},
    this.stewardIds = const {},
  });

  final Set<String> authorIds;
  final Set<String> stewardIds;

  String? admittedParticipantId;
  String? admitActorId;

  @override
  Future<bool> isBeaconAuthor({
    required String beaconId,
    required String userId,
  }) async => authorIds.contains(userId);

  @override
  Future<bool> isBeaconSteward({
    required String beaconId,
    required String userId,
  }) async => stewardIds.contains(userId);

  @override
  Future<void> admitParticipant({
    required String beaconId,
    required String participantUserId,
    required String actorUserId,
  }) async {
    admittedParticipantId = participantUserId;
    admitActorId = actorUserId;
  }
}

class _TrackingRoomAdmittedPush extends NoopBeaconRoomNotificationPort {
  String? receiverId;
  String? actorUserId;

  @override
  Future<void> notifyRoomAdmitted({
    required String receiverId,
    required String beaconId,
    required String actorUserId,
  }) async {
    this.receiverId = receiverId;
    this.actorUserId = actorUserId;
  }
}

class _MinimalCoordinationItems extends Fake
    implements CoordinationItemRepositoryPort {}

class _MinimalFactCards extends Fake implements BeaconFactCardRepositoryPort {}

class _MinimalImages extends Fake implements ImageRepositoryPort {}

class _MinimalTasks extends Fake implements TaskRepositoryPort {}

class _MinimalRemoteStorage extends Fake implements RemoteStoragePort {}

class _MinimalPolling extends Fake implements PollingRepositoryPort {}

class _MinimalUploadQuota extends Fake implements UploadQuotaRepositoryPort {}

class _MinimalEvaluationRepo extends Fake implements EvaluationRepositoryPort {}

void main() {
  group('room admission matrix (COV-051)', () {
    group('BeaconRoomCase.admit — actor matrix', () {
      late _AdmitStubRoom room;
      late _TrackingRoomAdmittedPush push;
      late BeaconRoomCase sut;

      setUp(() {
        room = _AdmitStubRoom(authorIds: {_authorId});
        push = _TrackingRoomAdmittedPush();
        sut = BeaconRoomCase(
          room,
          _MinimalCoordinationItems(),
          _MinimalFactCards(),
          push,
          _MinimalImages(),
          _MinimalTasks(),
          _MinimalRemoteStorage(),
          _MinimalPolling(),
          _MinimalUploadQuota(),
          env: Env(environment: Environment.test),
          logger: Logger('BeaconRoomAdmissionMatrixTest'),
        );
      });

      for (final row in <({String actorId, String label, bool isSteward})>[
        (actorId: _authorId, label: 'author', isSteward: false),
        (actorId: _stewardId, label: 'steward', isSteward: true),
      ]) {
        test('${row.label} admits participant and notifies', () async {
          if (row.isSteward) {
            room = _AdmitStubRoom(stewardIds: {row.actorId});
            push = _TrackingRoomAdmittedPush();
            sut = BeaconRoomCase(
              room,
              _MinimalCoordinationItems(),
              _MinimalFactCards(),
              push,
              _MinimalImages(),
              _MinimalTasks(),
              _MinimalRemoteStorage(),
              _MinimalPolling(),
              _MinimalUploadQuota(),
              env: Env(environment: Environment.test),
              logger: Logger('BeaconRoomAdmissionMatrixTest'),
            );
          }

          await sut.admit(
            beaconId: _beaconId,
            participantUserId: _helperId,
            actorUserId: row.actorId,
          );

          expect(room.admittedParticipantId, _helperId);
          expect(room.admitActorId, row.actorId);
          expect(push.receiverId, _helperId);
          expect(push.actorUserId, row.actorId);
        });
      }

      test('outsider is rejected', () async {
        room = _AdmitStubRoom();
        sut = BeaconRoomCase(
          room,
          _MinimalCoordinationItems(),
          _MinimalFactCards(),
          push,
          _MinimalImages(),
          _MinimalTasks(),
          _MinimalRemoteStorage(),
          _MinimalPolling(),
          _MinimalUploadQuota(),
          env: Env(environment: Environment.test),
          logger: Logger('BeaconRoomAdmissionMatrixTest'),
        );

        await expectLater(
          sut.admit(
            beaconId: _beaconId,
            participantUserId: _helperId,
            actorUserId: _outsiderId,
          ),
          throwsA(
            isA<UnauthorizedException>().having(
              (e) => e.description,
              'description',
              'Author or steward only',
            ),
          ),
        );
        expect(room.admittedParticipantId, isNull);
        expect(push.receiverId, isNull);
      });
    });

    group('CoordinationCase.setCoordinationResponse — room access matrix', () {
      late MockBeaconRepositoryPort beaconRepo;
      late MockHelpOfferRepositoryPort helpOfferRepo;
      late MockCoordinationRepositoryPort coordinationRepo;
      late MockBeaconRoomRepositoryPort roomRepo;
      late MockBeaconRoomNotificationPort roomPush;
      late CoordinationCase sut;

      setUp(() {
        beaconRepo = MockBeaconRepositoryPort();
        helpOfferRepo = MockHelpOfferRepositoryPort();
        coordinationRepo = MockCoordinationRepositoryPort();
        roomRepo = MockBeaconRoomRepositoryPort();
        roomPush = MockBeaconRoomNotificationPort();
        sut = CoordinationCase(
          beaconRepo,
          helpOfferRepo,
          coordinationRepo,
          roomRepo,
          _MinimalEvaluationRepo(),
          roomPush: roomPush,
          guard: FakeBeaconAccessGuard(),
          env: Env(environment: Environment.test),
          logger: Logger('BeaconRoomAdmissionMatrixTest'),
        );

        when(
          beaconRepo.getBeaconById(beaconId: _beaconId),
        ).thenAnswer((_) async => _beacon());
        when(
          helpOfferRepo.fetchByBeaconId(_beaconId),
        ).thenAnswer((_) async => [_activeOffer()]);
        when(
          coordinationRepo.upsertResponse(
            beaconId: anyNamed('beaconId'),
            offerUserId: anyNamed('offerUserId'),
            authorUserId: anyNamed('authorUserId'),
            responseType: anyNamed('responseType'),
          ),
        ).thenAnswer((_) async {});
        when(
          coordinationRepo.beaconStatusSnapshot(_beaconId),
        ).thenAnswer(
          (_) async => (
            status: BeaconStatus.enoughHelp,
            statusChangedAt: _now,
          ),
        );
        when(
          roomRepo.inviteOfferUserToBeaconRoom(
            beaconId: anyNamed('beaconId'),
            offerUserId: anyNamed('offerUserId'),
            authorUserId: anyNamed('authorUserId'),
          ),
        ).thenAnswer((_) async {});
        when(
          roomRepo.revokeOfferUserBeaconRoomAccess(
            beaconId: anyNamed('beaconId'),
            offerUserId: anyNamed('offerUserId'),
            authorUserId: anyNamed('authorUserId'),
          ),
        ).thenAnswer((_) async {});
      });

      Future<void> respond({
        required bool inviteToRoom,
        required bool removeFromRoom,
      }) => sut.setCoordinationResponse(
        beaconId: _beaconId,
        offerUserId: _helperId,
        authorUserId: _authorId,
        responseType: CoordinationResponseType.useful.smallintValue,
        inviteToRoom: inviteToRoom,
        removeFromRoom: removeFromRoom,
      );

      for (final row
          in <({bool invite, bool remove, String expected, String label})>[
            (
              invite: true,
              remove: false,
              expected: 'invite',
              label: 'author invite re-admits helper',
            ),
            (
              invite: false,
              remove: true,
              expected: 'revoke',
              label: 'author revoke removes helper',
            ),
            (
              invite: true,
              remove: true,
              expected: 'revoke',
              label: 'removeFromRoom wins over inviteToRoom',
            ),
            (
              invite: false,
              remove: false,
              expected: 'none',
              label: 'response only leaves room access unchanged',
            ),
          ]) {
        test(row.label, () async {
          await respond(inviteToRoom: row.invite, removeFromRoom: row.remove);

          switch (row.expected) {
            case 'invite':
              verify(
                roomRepo.inviteOfferUserToBeaconRoom(
                  beaconId: _beaconId,
                  offerUserId: _helperId,
                  authorUserId: _authorId,
                ),
              ).called(1);
              verifyNever(
                roomRepo.revokeOfferUserBeaconRoomAccess(
                  beaconId: anyNamed('beaconId'),
                  offerUserId: anyNamed('offerUserId'),
                  authorUserId: anyNamed('authorUserId'),
                ),
              );
            case 'revoke':
              verify(
                roomRepo.revokeOfferUserBeaconRoomAccess(
                  beaconId: _beaconId,
                  offerUserId: _helperId,
                  authorUserId: _authorId,
                ),
              ).called(1);
              verifyNever(
                roomRepo.inviteOfferUserToBeaconRoom(
                  beaconId: anyNamed('beaconId'),
                  offerUserId: anyNamed('offerUserId'),
                  authorUserId: anyNamed('authorUserId'),
                ),
              );
            case 'none':
              verifyNever(
                roomRepo.inviteOfferUserToBeaconRoom(
                  beaconId: anyNamed('beaconId'),
                  offerUserId: anyNamed('offerUserId'),
                  authorUserId: anyNamed('authorUserId'),
                ),
              );
              verifyNever(
                roomRepo.revokeOfferUserBeaconRoomAccess(
                  beaconId: anyNamed('beaconId'),
                  offerUserId: anyNamed('offerUserId'),
                  authorUserId: anyNamed('authorUserId'),
                ),
              );
          }
        });
      }
    });

    group('CoordinationCase admission actions', () {
      late MockBeaconRepositoryPort beaconRepo;
      late MockHelpOfferRepositoryPort helpOfferRepo;
      late MockCoordinationRepositoryPort coordinationRepo;
      late MockBeaconRoomRepositoryPort roomRepo;
      late MockBeaconRoomNotificationPort roomPush;
      late CoordinationCase sut;

      BeaconParticipantRecord participant({required int roomAccess}) =>
          testBeaconParticipant(
            beaconId: _beaconId,
            userId: _helperId,
            roomAccess: roomAccess,
          );

      Matcher throwsCoordinationCode(HelpOfferCoordinationExceptionCode code) =>
          throwsA(
            isA<HelpOfferCoordinationException>().having(
              (e) => e.code.codeNumber,
              'codeNumber',
              HelpOfferCoordinationExceptionCodes(code).codeNumber,
            ),
          );

      void buildSut({FakeBeaconAccessGuard? guard}) {
        sut = CoordinationCase(
          beaconRepo,
          helpOfferRepo,
          coordinationRepo,
          roomRepo,
          _MinimalEvaluationRepo(),
          roomPush: roomPush,
          guard: guard ?? FakeBeaconAccessGuard(),
          env: Env(environment: Environment.test),
          logger: Logger('BeaconRoomAdmissionMatrixTest'),
        );
      }

      void stubOpenActiveOffer({String authorId = _authorId}) {
        when(
          beaconRepo.getBeaconById(beaconId: _beaconId),
        ).thenAnswer((_) async => _beacon());
        when(
          helpOfferRepo.fetchByBeaconId(_beaconId),
        ).thenAnswer((_) async => [_activeOffer()]);
      }

      setUp(() {
        beaconRepo = MockBeaconRepositoryPort();
        helpOfferRepo = MockHelpOfferRepositoryPort();
        coordinationRepo = MockCoordinationRepositoryPort();
        roomRepo = MockBeaconRoomRepositoryPort();
        roomPush = MockBeaconRoomNotificationPort();
        buildSut();

        when(
          roomPush.notifyRoomAdmitted(
            receiverId: anyNamed('receiverId'),
            beaconId: anyNamed('beaconId'),
            actorUserId: anyNamed('actorUserId'),
          ),
        ).thenAnswer((_) async {});
        when(
          roomPush.notifyCommitmentDeclined(
            receiverId: anyNamed('receiverId'),
            beaconId: anyNamed('beaconId'),
            actorUserId: anyNamed('actorUserId'),
            reason: anyNamed('reason'),
          ),
        ).thenAnswer((_) async {});
        when(
          roomPush.notifyCommitmentRemoved(
            receiverId: anyNamed('receiverId'),
            beaconId: anyNamed('beaconId'),
            actorUserId: anyNamed('actorUserId'),
            reason: anyNamed('reason'),
          ),
        ).thenAnswer((_) async {});
      });

      test(
        'author accepts an active offer and notifies the committer',
        () async {
          stubOpenActiveOffer();
          when(
            coordinationRepo.acceptHelpOffer(
              beaconId: _beaconId,
              offerUserId: _helperId,
              actorUserId: _authorId,
            ),
          ).thenAnswer(
            (_) async =>
                (status: BeaconStatus.enoughHelp, statusChangedAt: _now),
          );

          final result = await sut.acceptHelpOffer(
            beaconId: _beaconId,
            offerUserId: _helperId,
            actorUserId: _authorId,
          );

          expect(result.status, BeaconStatus.enoughHelp.smallintValue);
          verify(
            coordinationRepo.acceptHelpOffer(
              beaconId: _beaconId,
              offerUserId: _helperId,
              actorUserId: _authorId,
            ),
          ).called(1);
          verify(
            roomPush.notifyRoomAdmitted(
              receiverId: _helperId,
              beaconId: _beaconId,
              actorUserId: _authorId,
            ),
          ).called(1);
        },
      );

      test('steward can decline with a trimmed mandatory reason', () async {
        stubOpenActiveOffer();
        when(
          roomRepo.isBeaconSteward(beaconId: _beaconId, userId: _stewardId),
        ).thenAnswer((_) async => true);
        when(
          roomRepo.findParticipant(beaconId: _beaconId, userId: _helperId),
        ).thenAnswer(
          (_) async => participant(roomAccess: RoomAccessBits.requested),
        );
        when(
          coordinationRepo.declineHelpOffer(
            beaconId: _beaconId,
            offerUserId: _helperId,
            actorUserId: _stewardId,
            reason: 'not a fit',
          ),
        ).thenAnswer(
          (_) async => (status: BeaconStatus.open, statusChangedAt: null),
        );

        await sut.declineHelpOffer(
          beaconId: _beaconId,
          offerUserId: _helperId,
          actorUserId: _stewardId,
          reason: '  not a fit  ',
        );

        verify(
          coordinationRepo.declineHelpOffer(
            beaconId: _beaconId,
            offerUserId: _helperId,
            actorUserId: _stewardId,
            reason: 'not a fit',
          ),
        ).called(1);
        verify(
          roomPush.notifyCommitmentDeclined(
            receiverId: _helperId,
            beaconId: _beaconId,
            actorUserId: _stewardId,
            reason: 'not a fit',
          ),
        ).called(1);
      });

      test('outsider cannot accept', () async {
        stubOpenActiveOffer();
        when(
          roomRepo.isBeaconSteward(beaconId: _beaconId, userId: _outsiderId),
        ).thenAnswer((_) async => false);

        await expectLater(
          sut.acceptHelpOffer(
            beaconId: _beaconId,
            offerUserId: _helperId,
            actorUserId: _outsiderId,
          ),
          throwsCoordinationCode(
            HelpOfferCoordinationExceptionCode.notBeaconAuthor,
          ),
        );
        verifyNever(
          coordinationRepo.acceptHelpOffer(
            beaconId: anyNamed('beaconId'),
            offerUserId: anyNamed('offerUserId'),
            actorUserId: anyNamed('actorUserId'),
          ),
        );
      });

      test('decline rejects empty and over-length reasons', () async {
        await expectLater(
          sut.declineHelpOffer(
            beaconId: _beaconId,
            offerUserId: _helperId,
            actorUserId: _authorId,
            reason: '  ',
          ),
          throwsCoordinationCode(
            HelpOfferCoordinationExceptionCode.reasonRequired,
          ),
        );

        await expectLater(
          sut.declineHelpOffer(
            beaconId: _beaconId,
            offerUserId: _helperId,
            actorUserId: _authorId,
            reason: 'x' * 501,
          ),
          throwsCoordinationCode(
            HelpOfferCoordinationExceptionCode.reasonTooLong,
          ),
        );
        verifyNever(
          coordinationRepo.declineHelpOffer(
            beaconId: anyNamed('beaconId'),
            offerUserId: anyNamed('offerUserId'),
            actorUserId: anyNamed('actorUserId'),
            reason: anyNamed('reason'),
          ),
        );
      });

      test('decline rejects already admitted committer', () async {
        stubOpenActiveOffer();
        when(
          roomRepo.findParticipant(beaconId: _beaconId, userId: _helperId),
        ).thenAnswer(
          (_) async => participant(roomAccess: RoomAccessBits.admitted),
        );

        await expectLater(
          sut.declineHelpOffer(
            beaconId: _beaconId,
            offerUserId: _helperId,
            actorUserId: _authorId,
            reason: 'not now',
          ),
          throwsCoordinationCode(
            HelpOfferCoordinationExceptionCode.alreadyAdmitted,
          ),
        );
      });

      test(
        'remove requires admitted committer and notifies with reason',
        () async {
          stubOpenActiveOffer();
          when(
            roomRepo.findParticipant(beaconId: _beaconId, userId: _helperId),
          ).thenAnswer(
            (_) async => participant(roomAccess: RoomAccessBits.admitted),
          );
          when(
            coordinationRepo.removeFromRoom(
              beaconId: _beaconId,
              offerUserId: _helperId,
              actorUserId: _authorId,
              reason: 'capacity changed',
            ),
          ).thenAnswer(
            (_) async => (status: BeaconStatus.open, statusChangedAt: null),
          );

          await sut.removeFromRoom(
            beaconId: _beaconId,
            offerUserId: _helperId,
            actorUserId: _authorId,
            reason: 'capacity changed',
          );

          verify(
            coordinationRepo.removeFromRoom(
              beaconId: _beaconId,
              offerUserId: _helperId,
              actorUserId: _authorId,
              reason: 'capacity changed',
            ),
          ).called(1);
          verify(
            roomPush.notifyCommitmentRemoved(
              receiverId: _helperId,
              beaconId: _beaconId,
              actorUserId: _authorId,
              reason: 'capacity changed',
            ),
          ).called(1);

          when(
            roomRepo.findParticipant(beaconId: _beaconId, userId: _helperId),
          ).thenAnswer(
            (_) async => participant(roomAccess: RoomAccessBits.requested),
          );
          await expectLater(
            sut.removeFromRoom(
              beaconId: _beaconId,
              offerUserId: _helperId,
              actorUserId: _authorId,
              reason: 'capacity changed',
            ),
            throwsCoordinationCode(
              HelpOfferCoordinationExceptionCode.notAdmitted,
            ),
          );
        },
      );

      test('help offer admission reasons are redacted per viewer', () async {
        const rowUser = UserPublicRecord(
          id: _helperId,
          displayName: 'helper',
          description: '',
        );
        final rows = [
          HelpOfferWithCoordinationRow(
            beaconId: _beaconId,
            userId: _helperId,
            message: '',
            status: 0,
            createdAt: _now,
            updatedAt: _now,
            user: rowUser,
            admissionAction: HelpOfferAdmissionAction.decline.smallintValue,
            lastDeclineReason: 'private reason',
          ),
        ];
        when(
          beaconRepo.getBeaconById(beaconId: _beaconId),
        ).thenAnswer((_) async => _beacon());
        when(
          coordinationRepo.helpOffersWithCoordination(
            _beaconId,
            viewerId: anyNamed('viewerId'),
          ),
        ).thenAnswer((_) async => rows);
        when(
          roomRepo.isBeaconSteward(
            beaconId: _beaconId,
            userId: anyNamed('userId'),
          ),
        ).thenAnswer((_) async => false);

        final authorRows = await sut.helpOffersWithCoordination(
          beaconId: _beaconId,
          viewerId: _authorId,
        );
        final helperRows = await sut.helpOffersWithCoordination(
          beaconId: _beaconId,
          viewerId: _helperId,
        );
        final outsiderRows = await sut.helpOffersWithCoordination(
          beaconId: _beaconId,
          viewerId: _outsiderId,
        );

        expect(authorRows.single.lastDeclineReason, 'private reason');
        expect(helperRows.single.lastDeclineReason, 'private reason');
        expect(outsiderRows.single.lastDeclineReason, isNull);

        buildSut(guard: FakeBeaconAccessGuard(contentAllowed: false));
        await expectLater(
          sut.helpOffersWithCoordination(
            beaconId: _beaconId,
            viewerId: _helperId,
          ),
          throwsA(isA<UnauthorizedException>()),
        );
      });
    });

    group('HelpOfferCase.offerHelp — auto-admit matrix', () {
      late MockBeaconRepositoryPort beaconRepo;
      late MockHelpOfferRepositoryPort helpOfferRepo;
      late MockCoordinationRepositoryPort coordinationRepo;
      late MockInboxRepositoryPort inboxRepo;
      late MockPersonCapabilityEventRepositoryPort capabilityRepo;
      late MockBeaconRoomRepositoryPort roomRepo;
      late MockForwardEdgeRepositoryPort forwardEdgeRepo;
      late MockHelpOfferAdmissionRepositoryPort admissionRepo;
      late MockBeaconRoomNotificationPort roomPush;
      late HelpOfferCase sut;

      BeaconParticipantRecord participant({required int roomAccess}) =>
          testBeaconParticipant(
            beaconId: _beaconId,
            userId: _helperId,
            roomAccess: roomAccess,
          );

      setUp(() {
        beaconRepo = MockBeaconRepositoryPort();
        helpOfferRepo = MockHelpOfferRepositoryPort();
        coordinationRepo = MockCoordinationRepositoryPort();
        inboxRepo = MockInboxRepositoryPort();
        capabilityRepo = MockPersonCapabilityEventRepositoryPort();
        roomRepo = MockBeaconRoomRepositoryPort();
        forwardEdgeRepo = MockForwardEdgeRepositoryPort();
        admissionRepo = MockHelpOfferAdmissionRepositoryPort();
        roomPush = MockBeaconRoomNotificationPort();
        final capabilityCase = CapabilityCase(
          capabilityRepo,
          env: Env(environment: Environment.test),
          logger: Logger('BeaconRoomAdmissionMatrixTest'),
        );
        sut = HelpOfferCase(
          helpOfferRepo,
          beaconRepo,
          coordinationRepo,
          inboxRepo,
          capabilityCase,
          roomRepo,
          forwardEdgeRepo,
          admissionRepo,
          roomPush,
          FakeBeaconAccessGuard(),
          env: Env(environment: Environment.test),
          logger: Logger('BeaconRoomAdmissionMatrixTest'),
        );

        when(
          beaconRepo.getBeaconById(beaconId: _beaconId),
        ).thenAnswer((_) async => _beacon());
        when(
          helpOfferRepo.hasActiveHelpOffer(
            beaconId: _beaconId,
            userId: _helperId,
          ),
        ).thenAnswer((_) async => false);
        when(
          helpOfferRepo.upsert(beaconId: _beaconId, userId: _helperId),
        ).thenAnswer((_) async {});
        when(
          roomPush.notifyHelpOfferToAuthor(
            beaconId: anyNamed('beaconId'),
            helpOffererId: anyNamed('helpOffererId'),
            authorId: anyNamed('authorId'),
          ),
        ).thenAnswer((_) async {});
        when(
          roomRepo.inviteOfferUserToBeaconRoom(
            beaconId: anyNamed('beaconId'),
            offerUserId: anyNamed('offerUserId'),
            authorUserId: anyNamed('authorUserId'),
          ),
        ).thenAnswer((_) async {});
        when(
          roomPush.notifyRoomAdmitted(
            receiverId: anyNamed('receiverId'),
            beaconId: anyNamed('beaconId'),
            actorUserId: anyNamed('actorUserId'),
          ),
        ).thenAnswer((_) async {});
        when(
          admissionRepo.record(
            beaconId: anyNamed('beaconId'),
            offerUserId: anyNamed('offerUserId'),
            actorUserId: anyNamed('actorUserId'),
            action: anyNamed('action'),
          ),
        ).thenAnswer((_) async {});
      });

      for (final row
          in <
            ({
              bool trusted,
              int? roomAccess,
              bool expectAdmit,
              String label,
            })
          >[
            (
              trusted: true,
              roomAccess: null,
              expectAdmit: true,
              label: 'trusted direct forward admits new helper',
            ),
            (
              trusted: true,
              roomAccess: RoomAccessBits.none,
              expectAdmit: false,
              label: 'author revoke (none) blocks auto-admit',
            ),
            (
              trusted: true,
              roomAccess: RoomAccessBits.requested,
              expectAdmit: true,
              label: 'trusted helper with requested access is re-admitted',
            ),
            (
              trusted: false,
              roomAccess: null,
              expectAdmit: false,
              label: 'non-trusted helper is not auto-admitted',
            ),
          ]) {
        test(row.label, () async {
          when(
            forwardEdgeRepo.isDirectAuthorForward(
              beaconId: _beaconId,
              authorId: _authorId,
              userId: _helperId,
            ),
          ).thenAnswer((_) async => row.trusted);

          if (row.roomAccess == null) {
            when(
              roomRepo.findParticipant(
                beaconId: _beaconId,
                userId: _helperId,
              ),
            ).thenAnswer((_) async => null);
          } else {
            when(
              roomRepo.findParticipant(
                beaconId: _beaconId,
                userId: _helperId,
              ),
            ).thenAnswer(
              (_) async => participant(roomAccess: row.roomAccess!),
            );
          }

          await sut.offerHelp(beaconId: _beaconId, userId: _helperId);

          if (row.expectAdmit) {
            verify(
              roomRepo.inviteOfferUserToBeaconRoom(
                beaconId: _beaconId,
                offerUserId: _helperId,
                authorUserId: _authorId,
              ),
            ).called(1);
            verify(
              roomPush.notifyRoomAdmitted(
                receiverId: _helperId,
                beaconId: _beaconId,
                actorUserId: _authorId,
              ),
            ).called(1);
            verify(
              admissionRepo.record(
                beaconId: _beaconId,
                offerUserId: _helperId,
                actorUserId: _authorId,
                action: HelpOfferAdmissionAction.autoAdmit,
              ),
            ).called(1);
          } else {
            verifyNever(
              roomRepo.inviteOfferUserToBeaconRoom(
                beaconId: anyNamed('beaconId'),
                offerUserId: anyNamed('offerUserId'),
                authorUserId: anyNamed('authorUserId'),
              ),
            );
            verifyNever(
              roomPush.notifyRoomAdmitted(
                receiverId: anyNamed('receiverId'),
                beaconId: anyNamed('beaconId'),
                actorUserId: anyNamed('actorUserId'),
              ),
            );
            verifyNever(
              admissionRepo.record(
                beaconId: anyNamed('beaconId'),
                offerUserId: anyNamed('offerUserId'),
                actorUserId: anyNamed('actorUserId'),
                action: anyNamed('action'),
              ),
            );
          }
        });
      }
    });
  });
}
