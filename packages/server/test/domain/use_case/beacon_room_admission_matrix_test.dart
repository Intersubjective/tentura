import 'package:tentura_server/domain/use_case/beacon_fact_card_case.dart';
import 'package:tentura_server/domain/port/help_offer_repository_port.dart';
import 'package:tentura_server/domain/beacon_visibility.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../../support/fake_beacon_hierarchy_repository.dart';

import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/domain/commitment/commitment_event.dart';
import 'package:tentura_server/domain/commitment/commitment_event_kind.dart';
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
import 'package:tentura_server/domain/port/commitment_repository_port.dart';
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
import 'package:tentura_server/domain/use_case/commitment_query_case.dart';
import 'package:tentura_server/domain/use_case/help_offer_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/coordination_item_record_fixtures.dart';
import '../../support/fake_beacon_access_guard.dart';
import '../../support/recording_commitment_repository.dart';
import '../../support/test_attention_harness.dart';
import '../../support/fake_user_block_repository.dart';
import 'help_offer_case_mocks.mocks.dart';
import 'package:tentura_server/domain/policy/discussion_product_policy.dart';

const _beaconId = 'Bbbbbbbbbbbbb';
const _authorId = 'Uauthor000001';
const _stewardId = 'Usteward00001';
const _helperId = 'Uhelper000001';
const _outsiderId = 'Uoutsider0001';

final _now = DateTime.utc(2025);

CommitmentQueryCase _commitmentQueryCase(
  CommitmentRepositoryPort commitmentRepo,
  HelpOfferRepositoryPort helpOfferRepo,
) =>
    CommitmentQueryCase(
      commitmentRepo,
      helpOfferRepo,
      env: Env(environment: Environment.test),
      logger: Logger('BeaconRoomAdmissionMatrixTest'),
    );

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
    String admissionReason = 'admit',
  }) async {
    admittedParticipantId = participantUserId;
    admitActorId = actorUserId;
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

// Stateful offer storage: declining must deactivate the content/involvement grant.
class _ExitOffers extends Fake implements HelpOfferRepositoryPort {
  bool active = true;

  @override
  Future<List<HelpOfferEntity>> fetchByBeaconId(String beaconId) async =>
      active ? [_activeOffer()] : [];

  @override
  Future<void> withdraw({
    required String beaconId,
    required String userId,
    required String withdrawReason,
    String message = '',
  }) async {
    active = false;
  }

  @override
  Future<void> deactivate({
    required String beaconId,
    required String userId,
  }) async {
    active = false;
  }
}

void main() {
  group('exited helpers have external-viewer access (#144)', () {
    for (final withdraw in [true, false]) {
      test(
        withdraw ? 'accept and admit then leave' : 'author declines offer',
        () async {
          final beaconRepo = MockBeaconRepositoryPort();
          final offers = _ExitOffers();
          final coordinationRepo = MockCoordinationRepositoryPort();
          final room = MockBeaconRoomRepositoryPort();
          final inbox = MockInboxRepositoryPort();
          final commitments = RecordingCommitmentRepository();
          final attention = TestAttentionHarness();
          var admission = RoomAccessBits.requested;
          var watching = true;
          when(
            beaconRepo.getBeaconById(beaconId: _beaconId),
          ).thenAnswer((_) async => _beacon());
          when(
            room.isBeaconAuthor(beaconId: _beaconId, userId: _helperId),
          ).thenAnswer((_) async => false);
          when(
            room.isBeaconAuthor(beaconId: _beaconId, userId: _authorId),
          ).thenAnswer((_) async => true);
          when(
            room.isBeaconSteward(beaconId: _beaconId, userId: _authorId),
          ).thenAnswer((_) async => false);
          when(
            room.isBeaconSteward(beaconId: _beaconId, userId: _helperId),
          ).thenAnswer((_) async => false);
          when(
            room.findParticipant(beaconId: _beaconId, userId: _helperId),
          ).thenAnswer(
            (_) async => testBeaconParticipant(
              beaconId: _beaconId,
              userId: _helperId,
              roomAccess: admission,
            ),
          );
          when(
            room.revokeOfferUserBeaconRoomAccess(
              beaconId: _beaconId,
              offerUserId: _helperId,
              authorUserId: anyNamed('authorUserId'),
            ),
          ).thenAnswer((_) async {
            admission = RoomAccessBits.none;
          });
          when(
            room.admitParticipant(
              beaconId: _beaconId,
              participantUserId: _helperId,
              actorUserId: _authorId,
            ),
          ).thenAnswer((_) async {
            admission = RoomAccessBits.admitted;
          });
          when(
            inbox.upsertWatchingForSender(
              senderId: _helperId,
              beaconId: _beaconId,
              touchForwardOrdering: false,
            ),
          ).thenAnswer((_) async {
            watching = true;
          });
          when(
            coordinationRepo.acceptHelpOffer(
              beaconId: _beaconId,
              offerUserId: _helperId,
              actorUserId: _authorId,
            ),
          ).thenAnswer(
            (_) async => (status: BeaconStatus.open, statusChangedAt: null),
          );
          when(
            coordinationRepo.declineHelpOffer(
              beaconId: _beaconId,
              offerUserId: _helperId,
              actorUserId: _authorId,
              reason: 'capacity',
            ),
          ).thenAnswer(
            (_) async => (status: BeaconStatus.open, statusChangedAt: null),
          );
          final coordination = CoordinationCase(
            beaconRepo,
            offers,
            coordinationRepo,
            room,
            _MinimalEvaluationRepo(),
            FakeUserBlockRepository(),
            commitments,
            _commitmentQueryCase(commitments, offers),
            FakeBeaconHierarchyRepository(),
            attentionIntents: attention.intents,
            attention: attention.transactional,
            guard: FakeBeaconAccessGuard(),
            env: Env(environment: Environment.test),
            logger: Logger('ExitAccessTest'),
          );
          final discussion = BeaconRoomCase(
            room,
            _MinimalCoordinationItems(),
            _MinimalFactCards(),
            _MinimalImages(),
            _MinimalTasks(),
            _MinimalRemoteStorage(),
            _MinimalPolling(),
            _MinimalUploadQuota(),
            FakeUserBlockRepository(),
            PassThroughMutatingUnitOfWork(),
            FakeBeaconHierarchyRepository(),
            const ProductionDiscussionProductPolicy(),
            attentionIntents: attention.intents,
            attention: attention.transactional,
            env: Env(environment: Environment.test),
            logger: Logger('ExitAccessTest'),
          );
          if (withdraw) {
            await coordination.acceptHelpOffer(
              beaconId: _beaconId,
              offerUserId: _helperId,
              actorUserId: _authorId,
            );
            await discussion.admit(
              beaconId: _beaconId,
              participantUserId: _helperId,
              actorUserId: _authorId,
            );
            expect(admission, RoomAccessBits.admitted);
            watching = false;
            final helper = HelpOfferCase(
              offers,
              beaconRepo,
              commitments,
              inbox,
              CapabilityCase(
                MockPersonCapabilityEventRepositoryPort(),
                env: Env(environment: Environment.test),
                logger: Logger('ExitAccessTest'),
              ),
              FakeBeaconAccessGuard(),
              roomRepository: room,
              attentionIntents: attention.intents,
              attention: attention.transactional,
              env: Env(environment: Environment.test),
              logger: Logger('ExitAccessTest'),
            );
            await helper.withdraw(
              beaconId: _beaconId,
              userId: _helperId,
              withdrawReason: 'other',
            );
          } else {
            await coordination.declineHelpOffer(
              beaconId: _beaconId,
              offerUserId: _helperId,
              actorUserId: _authorId,
              reason: 'capacity',
            );
          }
          expect(
            offers.active,
            isFalse,
            reason: 'An exited offer grants no helper privileges',
          );
          expect(admission, RoomAccessBits.none);
          expect(watching, isTrue);
          for (final forwarded in [false, true]) {
            BeaconContentVisibilityFacts facts({required bool exited}) =>
                BeaconContentVisibilityFacts(
                  status: BeaconStatus.open,
                  isAuthor: false,
                  hasActiveForwardEdgeAsRecipient: forwarded,
                  isRoomAdmittedOrSteward:
                      exited && admission == RoomAccessBits.admitted,
                  isActiveHelpOfferer: exited && offers.active,
                  isDiscoverable: false,
                  isPublished: true,
                  isMutuallyVisibleWithAuthor: false,
                );
            expect(
              BeaconVisibility.canReadContent(facts(exited: true)),
              BeaconVisibility.canReadContent(facts(exited: false)),
            );
            bool involvement({required bool exited}) =>
                BeaconVisibility.canReadInvolvement(
                  BeaconInvolvementVisibilityFacts(
                    contentFacts: facts(exited: exited),
                    isOnActiveForwardEdge: forwarded,
                    isActiveHelpOfferer: exited && offers.active,
                    isRoomAdmittedOrSteward:
                        exited && admission == RoomAccessBits.admitted,
                  ),
                );
            expect(involvement(exited: true), involvement(exited: false));
          }
          await expectLater(
            discussion.createMessage(
              beaconId: _beaconId,
              userId: _helperId,
              body: 'stale client',
            ),
            throwsA(isA<UnauthorizedException>()),
          );
          final facts = BeaconFactCardCase(
            _MinimalFactCards(), room, FakeBeaconHierarchyRepository(),
            FakeBeaconAccessGuard(),
            env: Env(environment: Environment.test), logger: Logger('ExitAccessTest'),
          );
          await expectLater(facts.pin(
            beaconId: _beaconId, userId: _helperId,
            factText: 'stale client', visibility: 0,
          ), throwsA(isA<UnauthorizedException>()));
          if (withdraw) {
            verify(
              inbox.upsertWatchingForSender(
                senderId: _helperId,
                beaconId: _beaconId,
                touchForwardOrdering: false,
              ),
            ).called(1);
            expect(
              commitments.recordCalls.last.kind,
              CommitmentEventKind.withdrawnByHelper,
            );
          }
        },
      );
    }
  });


  group('room admission matrix (COV-051)', () {
    group('BeaconRoomCase.admit — actor matrix', () {
      late _AdmitStubRoom room;
      late TestAttentionHarness attention;
      late BeaconRoomCase sut;

      setUp(() {
        room = _AdmitStubRoom(authorIds: {_authorId});
        attention = TestAttentionHarness();
        sut = BeaconRoomCase(
          room,
          _MinimalCoordinationItems(),
          _MinimalFactCards(),
          _MinimalImages(),
          _MinimalTasks(),
          _MinimalRemoteStorage(),
          _MinimalPolling(),
          _MinimalUploadQuota(),
          FakeUserBlockRepository(),
      PassThroughMutatingUnitOfWork(),
      FakeBeaconHierarchyRepository(),
      const ProductionDiscussionProductPolicy(),
          attentionIntents: attention.intents,
          attention: attention.transactional,
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
                attention = TestAttentionHarness();
            sut = BeaconRoomCase(
              room,
              _MinimalCoordinationItems(),
              _MinimalFactCards(),
                  _MinimalImages(),
              _MinimalTasks(),
              _MinimalRemoteStorage(),
              _MinimalPolling(),
              _MinimalUploadQuota(),
              FakeUserBlockRepository(),
      PassThroughMutatingUnitOfWork(),
      FakeBeaconHierarchyRepository(),
      const ProductionDiscussionProductPolicy(),
              attentionIntents: attention.intents,
              attention: attention.transactional,
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
          expect(
            attention.recorded.single.recipients.single.recipientId,
            _helperId,
          );
          expect(attention.recorded.single.actorUserId, row.actorId);
        });
      }

      test('outsider is rejected', () async {
        room = _AdmitStubRoom();
        sut = BeaconRoomCase(
          room,
          _MinimalCoordinationItems(),
          _MinimalFactCards(),
          _MinimalImages(),
          _MinimalTasks(),
          _MinimalRemoteStorage(),
          _MinimalPolling(),
          _MinimalUploadQuota(),
          FakeUserBlockRepository(),
      PassThroughMutatingUnitOfWork(),
      FakeBeaconHierarchyRepository(),
      const ProductionDiscussionProductPolicy(),
          attentionIntents: attention.intents,
          attention: attention.transactional,
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
      });
    });

    group('CoordinationCase.setCoordinationResponse — room access matrix', () {
      late MockBeaconRepositoryPort beaconRepo;
      late MockHelpOfferRepositoryPort helpOfferRepo;
      late MockCoordinationRepositoryPort coordinationRepo;
      late MockBeaconRoomRepositoryPort roomRepo;
      late CoordinationCase sut;

      setUp(() {
        beaconRepo = MockBeaconRepositoryPort();
        helpOfferRepo = MockHelpOfferRepositoryPort();
        coordinationRepo = MockCoordinationRepositoryPort();
        roomRepo = MockBeaconRoomRepositoryPort();
        final commitmentRepo = NoOpCommitmentRepository();
        sut = CoordinationCase(
          beaconRepo,
          helpOfferRepo,
          coordinationRepo,
          roomRepo,
          _MinimalEvaluationRepo(),
          FakeUserBlockRepository(),
          commitmentRepo,
          _commitmentQueryCase(commitmentRepo, helpOfferRepo),
          FakeBeaconHierarchyRepository(),
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
      late TestAttentionHarness attention;
      late CoordinationCase sut;
      late FakeUserBlockRepository userBlocks;

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

      void buildSut({
        FakeBeaconAccessGuard? guard,
        void Function()? onAttentionContextLoaded,
      }) {
        attention = TestAttentionHarness(
          onContextLoaded: onAttentionContextLoaded,
        );
        userBlocks = FakeUserBlockRepository();
        final commitmentRepo = NoOpCommitmentRepository();
        sut = CoordinationCase(
          beaconRepo,
          helpOfferRepo,
          coordinationRepo,
          roomRepo,
          _MinimalEvaluationRepo(),
          userBlocks,
          commitmentRepo,
          _commitmentQueryCase(commitmentRepo, helpOfferRepo),
          FakeBeaconHierarchyRepository(),
          attentionIntents: attention.intents,
          attention: attention.transactional,
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
        buildSut();

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
          expect(attention.recorded.single.eventType.name, 'offerAccepted');
        },
      );

      test('steward can decline with a trimmed mandatory reason', () async {
        final ordering = <String>[];
        buildSut(
          onAttentionContextLoaded: () => ordering.add('audience_resolved'),
        );
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
        ).thenAnswer((_) async {
          ordering.add('destructive_mutation');
          return (status: BeaconStatus.open, statusChangedAt: null);
        });

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
        expect(attention.recorded.single.eventType.name, 'offerDeclined');
        expect(ordering, ['audience_resolved', 'destructive_mutation']);
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

      test('rejects admission when author blocked helper', () async {
        stubOpenActiveOffer();
        userBlocks.blockPair(_authorId, _helperId);

        await expectLater(
          sut.acceptHelpOffer(
            beaconId: _beaconId,
            offerUserId: _helperId,
            actorUserId: _authorId,
          ),
          throwsA(isA<UnauthorizedException>()),
        );
        verifyNever(
          coordinationRepo.acceptHelpOffer(
            beaconId: anyNamed('beaconId'),
            offerUserId: anyNamed('offerUserId'),
            actorUserId: anyNamed('actorUserId'),
          ),
        );
      });

      test('rejects admission when helper blocked author', () async {
        stubOpenActiveOffer();
        userBlocks.blockPair(_helperId, _authorId);

        await expectLater(
          sut.acceptHelpOffer(
            beaconId: _beaconId,
            offerUserId: _helperId,
            actorUserId: _authorId,
          ),
          throwsA(isA<UnauthorizedException>()),
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

      test('decline rejects previously acknowledged committer', () async {
        final commitmentRepo = RecordingCommitmentRepository(
          eventsByPair: {
            commitmentPairKey(_beaconId, _helperId): [
              CommitmentEvent(
                id: 'CE-1',
                seq: 1,
                beaconId: _beaconId,
                userId: _helperId,
                actorUserId: _authorId,
                kind: CommitmentEventKind.offered,
                createdAt: _now,
              ),
              CommitmentEvent(
                id: 'CE-2',
                seq: 2,
                beaconId: _beaconId,
                userId: _helperId,
                actorUserId: _authorId,
                kind: CommitmentEventKind.acknowledged,
                createdAt: _now.add(const Duration(minutes: 1)),
              ),
            ],
          },
        );
        attention = TestAttentionHarness();
        sut = CoordinationCase(
          beaconRepo,
          helpOfferRepo,
          coordinationRepo,
          roomRepo,
          _MinimalEvaluationRepo(),
          userBlocks,
          commitmentRepo,
          _commitmentQueryCase(commitmentRepo, helpOfferRepo),
          FakeBeaconHierarchyRepository(),
          attentionIntents: attention.intents,
          attention: attention.transactional,
          guard: FakeBeaconAccessGuard(),
          env: Env(environment: Environment.test),
          logger: Logger('BeaconRoomAdmissionMatrixTest'),
        );
        stubOpenActiveOffer();

        await expectLater(
          sut.declineHelpOffer(
            beaconId: _beaconId,
            offerUserId: _helperId,
            actorUserId: _authorId,
            reason: 'not now',
          ),
          throwsCoordinationCode(
            HelpOfferCoordinationExceptionCode.commitmentAlreadyAcknowledged,
          ),
        );
      });

      test(
        'remove requires admitted committer and notifies with reason',
        () async {
          final ordering = <String>[];
          buildSut(
            onAttentionContextLoaded: () => ordering.add('audience_resolved'),
          );
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
          ).thenAnswer((_) async {
            ordering.add('destructive_mutation');
            return (status: BeaconStatus.open, statusChangedAt: null);
          });

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
          expect(attention.recorded.single.eventType.name, 'offerRemoved');
          expect(ordering, ['audience_resolved', 'destructive_mutation']);

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
          userAvailability: null,
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

        // Content-readable but not involved: the gate must check involvement.
        buildSut(guard: FakeBeaconAccessGuard(involvementAllowed: false));
        await expectLater(
          sut.helpOffersWithCoordination(
            beaconId: _beaconId,
            viewerId: _outsiderId,
          ),
          throwsA(
            isA<UnauthorizedException>().having(
              (e) => e.description,
              'description',
              'Viewer cannot read request involvement',
            ),
          ),
        );

        // Stranger: neither content nor involvement.
        buildSut(
          guard: FakeBeaconAccessGuard(
            contentAllowed: false,
            involvementAllowed: false,
          ),
        );
        await expectLater(
          sut.helpOffersWithCoordination(
            beaconId: _beaconId,
            viewerId: _outsiderId,
          ),
          throwsA(isA<UnauthorizedException>()),
        );
      });
    });

    group('HelpOfferCase.offerHelp — direct forward does not auto-admit (P5)', () {
      late MockBeaconRepositoryPort beaconRepo;
      late MockHelpOfferRepositoryPort helpOfferRepo;
      late MockCoordinationRepositoryPort coordinationRepo;
      late MockInboxRepositoryPort inboxRepo;
      late MockPersonCapabilityEventRepositoryPort capabilityRepo;
      late MockBeaconRoomRepositoryPort roomRepo;
      late RecordingCommitmentRepository commitmentRepo;
      late TestAttentionHarness attention;
      late HelpOfferCase sut;

      setUp(() {
        beaconRepo = MockBeaconRepositoryPort();
        helpOfferRepo = MockHelpOfferRepositoryPort();
        coordinationRepo = MockCoordinationRepositoryPort();
        inboxRepo = MockInboxRepositoryPort();
        capabilityRepo = MockPersonCapabilityEventRepositoryPort();
        roomRepo = MockBeaconRoomRepositoryPort();
        commitmentRepo = RecordingCommitmentRepository();
        attention = TestAttentionHarness();
        final capabilityCase = CapabilityCase(
          capabilityRepo,
          env: Env(environment: Environment.test),
          logger: Logger('BeaconRoomAdmissionMatrixTest'),
        );
        sut = HelpOfferCase(
          helpOfferRepo,
          beaconRepo,
          commitmentRepo,
          inboxRepo,
          capabilityCase,
          FakeBeaconAccessGuard(),
        roomRepository: roomRepo,
          attentionIntents: attention.intents,
          attention: attention.transactional,
          env: Env(environment: Environment.test),
          logger: Logger('BeaconRoomAdmissionMatrixTest'),
        );

        when(
          beaconRepo.getBeaconById(beaconId: _beaconId),
        ).thenAnswer((_) async => _beacon());
        when(
          beaconRepo.runInBeaconStateTransaction<void>(
            beaconId: anyNamed('beaconId'),
            userId: anyNamed('userId'),
            fn: anyNamed('fn'),
          ),
        ).thenAnswer((invocation) {
          final fn =
              invocation.namedArguments[#fn]
                  as Future<void> Function(BeaconEntity);
          return fn(_beacon());
        });
        when(
          helpOfferRepo.hasActiveHelpOffer(
            beaconId: _beaconId,
            userId: _helperId,
          ),
        ).thenAnswer((_) async => false);
        when(
          helpOfferRepo.upsert(beaconId: _beaconId, userId: _helperId),
        ).thenAnswer((_) async {});
      });

      test(
        'direct author forward recipient is not admitted until explicit accept',
        () async {
          await sut.offerHelp(beaconId: _beaconId, userId: _helperId);

          verifyNever(
            roomRepo.inviteOfferUserToBeaconRoom(
              beaconId: anyNamed('beaconId'),
              offerUserId: anyNamed('offerUserId'),
              authorUserId: anyNamed('authorUserId'),
              admissionReason: anyNamed('admissionReason'),
            ),
          );
          verifyNever(
            coordinationRepo.upsertResponse(
              beaconId: anyNamed('beaconId'),
              offerUserId: anyNamed('offerUserId'),
              authorUserId: anyNamed('authorUserId'),
              responseType: anyNamed('responseType'),
            ),
          );
          expect(
            commitmentRepo.recordCalls.map((c) => c.kind),
            [CommitmentEventKind.offered],
          );
          expect(
            attention.recorded.map((intent) => intent.eventType.name),
            ['helpOfferSubmitted'],
          );
        },
      );
    });
  });
}
