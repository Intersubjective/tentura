import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/domain/beacon_lineage_visibility.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/coordination_repository_port.dart';
import 'package:tentura_server/domain/port/help_offer_repository_port.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/use_case/beacon_case.dart';
import 'package:tentura_server/env.dart';

class _StubBeaconRepo extends Fake implements BeaconRepositoryPort {
  Future<BeaconEntity> Function()? onGetBeaconById;
  Future<BeaconEntity> Function()? onPublishDraft;
  int publishDraftCalls = 0;

  @override
  Future<BeaconEntity> getBeaconById({
    required String beaconId,
    String? filterByUserId,
  }) =>
      onGetBeaconById!();

  @override
  Future<BeaconEntity> publishDraft({
    required String id,
    required String actorId,
  }) {
    publishDraftCalls++;
    return onPublishDraft!();
  }
}

class _FakeImageRepo extends Fake implements ImageRepositoryPort {}

class _FakeTaskRepo extends Fake implements TaskRepositoryPort {}

class _FakeCoordinationRepo extends Fake implements CoordinationRepositoryPort {}

class _FakeHelpOfferRepo extends Fake implements HelpOfferRepositoryPort {}

void main() {
  late _StubBeaconRepo beaconRepo;
  late BeaconCase case_;
  final now = DateTime.utc(2026, 6, 18);

  BeaconEntity draftBeacon({
    String needSummary = 'Enough chars here!!',
  }) =>
      BeaconEntity(
        id: 'Bdraft',
        title: 'Draft title',
        author: UserEntity(id: 'Uauth'),
        createdAt: now,
        updatedAt: now,
        state: kBeaconStateDraft,
        needSummary: needSummary,
      );

  setUp(() {
    beaconRepo = _StubBeaconRepo();
    case_ = BeaconCase(
      beaconRepo,
      _FakeImageRepo(),
      _FakeTaskRepo(),
      _FakeCoordinationRepo(),
      _FakeHelpOfferRepo(),
      env: Env(environment: Environment.test),
      logger: Logger('BeaconCasePublishDraftTest'),
    );
  });

  test('publishDraft rejects draft with short need summary', () async {
    final beacon = draftBeacon(needSummary: 'too short');
    beaconRepo.onGetBeaconById = () async => beacon;

    await expectLater(
      case_.publishDraft(userId: 'Uauth', beaconId: beacon.id),
      throwsA(isA<BeaconNeedSummaryTooShortException>()),
    );
    expect(beaconRepo.publishDraftCalls, 0);
  });

  test('publishDraft delegates to repository for valid draft', () async {
    final beacon = draftBeacon();
    final published = beacon.copyWith(state: 0);
    beaconRepo.onGetBeaconById = () async => beacon;
    beaconRepo.onPublishDraft = () async => published;

    final result = await case_.publishDraft(
      userId: 'Uauth',
      beaconId: beacon.id,
    );

    expect(result.state, 0);
    expect(beaconRepo.publishDraftCalls, 1);
  });
}
