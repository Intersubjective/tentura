import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/domain/entity/gql_public/help_offer_with_coordination_row.dart';
import 'package:tentura_server/domain/entity/gql_public/user_public_record.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/use_case/commitment_query_case.dart';
import 'package:tentura_server/domain/use_case/coordination_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/fake_beacon_access_guard.dart';
import '../../support/fake_beacon_hierarchy_repository.dart';
import '../../support/fake_user_block_repository.dart';
import '../../support/recording_commitment_repository.dart';
import '../../support/test_attention_harness.dart';
import 'help_offer_case_mocks.mocks.dart';

class _NoBeaconRepo extends Fake implements BeaconRepositoryPort {}

const _beaconId = 'Bmine0000001';
const _viewer = 'Uviewer00001';
const _other = 'Uother000001';

HelpOfferWithCoordinationRow _row(
  String userId, {
  int status = 0,
  int? admissionAction,
  String? lastDeclineReason,
}) => HelpOfferWithCoordinationRow(
  beaconId: _beaconId,
  userId: userId,
  message: 'm',
  status: status,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  user: UserPublicRecord(
    id: userId,
    displayName: userId,
    description: '',
    userAvailability: null,
  ),
  admissionAction: admissionAction,
  lastDeclineReason: lastDeclineReason,
);

/// `myHelpOffer` lets an offerer see their own (e.g. declined) offer after
/// the decline has taken away their involvement access (UI review #216).
void main() {
  late MockCoordinationRepositoryPort coordinationRepo;
  late FakeBeaconAccessGuard guard;
  late CoordinationCase sut;

  setUp(() {
    coordinationRepo = MockCoordinationRepositoryPort();
    guard = FakeBeaconAccessGuard(involvementAllowed: false);
    final helpOfferRepo = MockHelpOfferRepositoryPort();
    final commitmentRepo = NoOpCommitmentRepository();
    final env = Env(environment: Environment.test);
    final logger = Logger('CoordinationCaseMyHelpOfferTest');
    final attention = TestAttentionHarness();
    sut = CoordinationCase(
      _NoBeaconRepo(),
      helpOfferRepo,
      coordinationRepo,
      MockBeaconRoomRepositoryPort(),
      FakeUserBlockRepository(),
      commitmentRepo,
      CommitmentQueryCase(
        commitmentRepo,
        helpOfferRepo,
        env: env,
        logger: logger,
      ),
      FakeBeaconHierarchyRepository(),
      attentionIntents: attention.intents,
      attention: attention.transactional,
      guard: guard,
      env: env,
      logger: logger,
    );
  });

  void stubRows(List<HelpOfferWithCoordinationRow> rows) => when(
    coordinationRepo.helpOffersWithCoordination(
      _beaconId,
      viewerId: _viewer,
    ),
  ).thenAnswer((_) async => rows);

  test('returns only the viewer row, with its decline reason', () async {
    stubRows([
      _row(_other),
      _row(
        _viewer,
        status: 1,
        admissionAction: 2,
        lastDeclineReason: 'We have enough hands',
      ),
    ]);

    final row = await sut.myHelpOffer(beaconId: _beaconId, viewerId: _viewer);

    expect(row?.userId, _viewer);
    expect(row?.lastDeclineReason, 'We have enough hands');
  });

  test('returns null when the viewer never offered', () async {
    stubRows([_row(_other)]);

    expect(
      await sut.myHelpOffer(beaconId: _beaconId, viewerId: _viewer),
      isNull,
    );
  });

  test('refuses viewers who cannot read the request', () async {
    guard.contentAllowed = false;

    await expectLater(
      sut.myHelpOffer(beaconId: _beaconId, viewerId: _viewer),
      throwsA(isA<UnauthorizedException>()),
    );
    verifyNever(
      coordinationRepo.helpOffersWithCoordination(
        any,
        viewerId: anyNamed('viewerId'),
      ),
    );
  });
}
