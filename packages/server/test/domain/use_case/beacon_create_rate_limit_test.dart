import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

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
import 'package:tentura_root/domain/entity/beacon_status.dart';

import '../../support/fake_beacon_access_guard.dart';

class _StubBeaconRepo extends Fake implements BeaconRepositoryPort {
  int recentCount = 0;
  int createBeaconCalls = 0;

  @override
  Future<int> countRecentByAuthor({
    required String userId,
    required Duration window,
  }) async =>
      recentCount;

  @override
  Future<BeaconEntity> createBeacon({
    required String authorId,
    required String title,
    String? description,
    String? context,
    List<String>? imageIds,
    double? latitude,
    double? longitude,
    DateTime? startAt,
    DateTime? endAt,
    Set<String>? tags,
    Set<String>? needs,
    int ticker = 0,
    String? iconCode,
    int? iconBackground,
    BeaconStatus? status,
    String? needSummary,
    String? successCriteria,
    String? lineageParentBeaconId,
    String? lineageRootBeaconId,
  }) async {
    createBeaconCalls++;
    return BeaconEntity(
      id: 'Bnew',
      title: title,
      author: UserEntity(id: authorId),
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      status: status ?? BeaconStatus.open,
      needSummary: needSummary,
    );
  }
}

class _FakeImageRepo extends Fake implements ImageRepositoryPort {}

class _FakeTaskRepo extends Fake implements TaskRepositoryPort {}

class _FakeCoordinationRepo extends Fake implements CoordinationRepositoryPort {}

class _FakeHelpOfferRepo extends Fake implements HelpOfferRepositoryPort {}

void main() {
  late _StubBeaconRepo beaconRepo;
  late BeaconCase case_;

  BeaconCase build(Env env) => BeaconCase(
        beaconRepo,
        _FakeImageRepo(),
        _FakeTaskRepo(),
        _FakeCoordinationRepo(),
        _FakeHelpOfferRepo(),
        FakeBeaconAccessGuard(),
        env: env,
        logger: Logger('BeaconCreateRateLimitTest'),
      );

  setUp(() {
    beaconRepo = _StubBeaconRepo();
  });

  test('create throws RateLimitedException at the per-user cap', () async {
    final env = Env(
      environment: Environment.test,
      beaconCreateMaxPerUser: 3,
    );
    case_ = build(env);
    beaconRepo.recentCount = 3;

    await expectLater(
      case_.create(
        userId: 'Uauth',
        title: 'Spam beacon',
        description: 'A description that is long enough.',
        needSummary: 'Enough chars here!!',
      ),
      throwsA(isA<RateLimitedException>()),
    );
    expect(beaconRepo.createBeaconCalls, 0);
  });

  test('create succeeds while under the per-user cap', () async {
    final env = Env(
      environment: Environment.test,
      beaconCreateMaxPerUser: 3,
    );
    case_ = build(env);
    beaconRepo.recentCount = 2;

    final beacon = await case_.create(
      userId: 'Uauth',
      title: 'Legit beacon',
      description: 'A description that is long enough.',
      needSummary: 'Enough chars here!!',
    );

    expect(beacon.id, 'Bnew');
    expect(beaconRepo.createBeaconCalls, 1);
  });
}
