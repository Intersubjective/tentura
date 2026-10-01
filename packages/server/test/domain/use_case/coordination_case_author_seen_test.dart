import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/gql_public/help_offer_with_coordination_row.dart';
import 'package:tentura_server/domain/entity/gql_public/user_public_record.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/use_case/commitment_query_case.dart';
import 'package:tentura_server/domain/use_case/coordination_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/fake_beacon_access_guard.dart';
import '../../support/fake_beacon_hierarchy_repository.dart';
import '../../support/fake_user_block_repository.dart';
import '../../support/recording_commitment_repository.dart';
import '../../support/test_attention_harness.dart';
import 'help_offer_case_mocks.mocks.dart';


const _beaconId = 'Bbbbbbbbbbbbb';
const _authorId = 'Uauthor000001';
const _stewardId = 'Usteward00001';
const _offerAId = 'Uofferera0001';
const _offerBId = 'Uofferbb00001';

final _now = DateTime.utc(2026);
final _seenA = DateTime.utc(2026, 2, 3, 4, 5, 6);
final _seenB = DateTime.utc(2026, 3, 4, 5, 6, 7);

HelpOfferWithCoordinationRow _row(String userId, DateTime seenAt) =>
    HelpOfferWithCoordinationRow(
      beaconId: _beaconId,
      userId: userId,
      message: 'm',
      status: 0,
      createdAt: _now,
      updatedAt: _now,
      user: UserPublicRecord(
        id: userId,
        displayName: userId,
        description: '',
        userAvailability: null,
      ),
      authorSeenAt: seenAt,
    );

/// Issue #178 D6: `authorSeenAt` is visible only to the author, stewards and
/// the offer's owner.
void main() {
  late MockBeaconRepositoryPort beaconRepo;
  late MockHelpOfferRepositoryPort helpOfferRepo;
  late MockCoordinationRepositoryPort coordinationRepo;
  late MockBeaconRoomRepositoryPort roomRepo;
  late RecordingCommitmentRepository commitmentRepo;
  late CoordinationCase sut;

  setUp(() {
    beaconRepo = MockBeaconRepositoryPort();
    helpOfferRepo = MockHelpOfferRepositoryPort();
    coordinationRepo = MockCoordinationRepositoryPort();
    roomRepo = MockBeaconRoomRepositoryPort();
    commitmentRepo = RecordingCommitmentRepository();
    when(beaconRepo.getBeaconById(beaconId: _beaconId)).thenAnswer(
      (_) async => BeaconEntity(
        id: _beaconId,
        title: 't',
        author: UserEntity(id: _authorId),
        createdAt: _now,
        updatedAt: _now,
        status: BeaconStatus.open,
      ),
    );
    when(
      roomRepo.isBeaconSteward(
        beaconId: _beaconId,
        userId: anyNamed('userId'),
      ),
    ).thenAnswer((i) async => i.namedArguments[#userId] == _stewardId);
    when(
      coordinationRepo.helpOffersWithCoordination(
        _beaconId,
        viewerId: anyNamed('viewerId'),
      ),
    ).thenAnswer(
      (_) async => [_row(_offerAId, _seenA), _row(_offerBId, _seenB)],
    );
    final attention = TestAttentionHarness();
    sut = CoordinationCase(
      beaconRepo,
      helpOfferRepo,
      coordinationRepo,
      roomRepo,
      FakeUserBlockRepository(),
      commitmentRepo,
      CommitmentQueryCase(
        commitmentRepo,
        helpOfferRepo,
        env: Env(environment: Environment.test),
        logger: Logger('CoordinationCaseAuthorSeenTest'),
      ),
      FakeBeaconHierarchyRepository(),
      attentionIntents: attention.intents,
      attention: attention.transactional,
      guard: FakeBeaconAccessGuard(),
      env: Env(environment: Environment.test),
      logger: Logger('CoordinationCaseAuthorSeenTest'),
    );
  });

  Future<Map<String, DateTime?>> seenFor(String viewerId) async {
    final rows = await sut.helpOffersWithCoordination(
      beaconId: _beaconId,
      viewerId: viewerId,
    );
    return {for (final r in rows) r.userId: r.authorSeenAt};
  }

  test('offer owner sees authorSeenAt on own row, null on the other', () async {
    expect(await seenFor(_offerAId), {_offerAId: _seenA, _offerBId: isNull});
  });

  test('third-party active offerer sees null on both others rows', () async {
    expect(await seenFor('Uthirdparty01'), {
      _offerAId: isNull,
      _offerBId: isNull,
    });
  });

  test('author sees authorSeenAt on every row', () async {
    expect(await seenFor(_authorId), {_offerAId: _seenA, _offerBId: _seenB});
  });

  test('steward sees authorSeenAt on every row', () async {
    expect(await seenFor(_stewardId), {_offerAId: _seenA, _offerBId: _seenB});
  });
}
