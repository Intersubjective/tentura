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
  int updateBeaconCalls = 0;
  int updateDraftBeaconCalls = 0;
  String? lastAddressLabel;

  @override
  Future<int> countRecentByAuthor({
    required String userId,
    required Duration window,
  }) async => recentCount;

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
    String? addressLabel,
    String? lineageParentBeaconId,
    String? lineageRootBeaconId,
  }) async {
    createBeaconCalls++;
    lastAddressLabel = addressLabel;
    return BeaconEntity(
      id: 'Bnew',
      title: title,
      author: UserEntity(id: authorId),
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      status: status ?? BeaconStatus.open,
      addressLabel: addressLabel,
    );
  }

  @override
  Future<BeaconEntity> updateBeacon({
    required String beaconId,
    required String userId,
    required String title,
    required String description,
    String? context,
    Set<String>? tags,
    Set<String>? needs,
    DateTime? startAt,
    DateTime? endAt,
    double? latitude,
    double? longitude,
    String? iconCode,
    int? iconBackground,
    String? addressLabel,
  }) async {
    updateBeaconCalls++;
    lastAddressLabel = addressLabel;
    return BeaconEntity(
      id: beaconId,
      title: title,
      author: UserEntity(id: userId),
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      addressLabel: addressLabel,
    );
  }

  @override
  Future<BeaconEntity> updateDraftBeacon({
    required String beaconId,
    required String userId,
    required String title,
    required String description,
    String? context,
    Set<String>? tags,
    Set<String>? needs,
    DateTime? startAt,
    DateTime? endAt,
    double? latitude,
    double? longitude,
    String? iconCode,
    int? iconBackground,
    String? addressLabel,
  }) async {
    updateDraftBeaconCalls++;
    lastAddressLabel = addressLabel;
    return BeaconEntity(
      id: beaconId,
      title: title,
      author: UserEntity(id: userId),
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      status: BeaconStatus.draft,
      addressLabel: addressLabel,
    );
  }
}

class _FakeImageRepo extends Fake implements ImageRepositoryPort {}

class _FakeTaskRepo extends Fake implements TaskRepositoryPort {}

class _FakeCoordinationRepo extends Fake
    implements CoordinationRepositoryPort {}

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
    );

    expect(beacon.id, 'Bnew');
    expect(beaconRepo.createBeaconCalls, 1);
  });

  test(
    'create passes the authoring-time address label to persistence',
    () async {
      final env = Env(
        environment: Environment.test,
        beaconCreateMaxPerUser: 3,
      );
      case_ = build(env);

      final beacon = await case_.create(
        userId: 'Uauth',
        title: 'Pickup request',
        description: 'A description that is long enough.',
        addressLabel: 'Museumplein 6, Amsterdam',
      );

      expect(beacon.addressLabel, 'Museumplein 6, Amsterdam');
      expect(beaconRepo.lastAddressLabel, 'Museumplein 6, Amsterdam');
    },
  );

  test('update passes the address label to persistence', () async {
    final env = Env(
      environment: Environment.test,
      beaconCreateMaxPerUser: 3,
    );
    case_ = build(env);

    final beacon = await case_.update(
      userId: 'Uauth',
      beaconId: 'B1',
      title: 'Pickup request',
      description: 'A description that is long enough.',
      addressLabel: '  Museumplein 6, Amsterdam  ',
    );

    expect(beacon.addressLabel, 'Museumplein 6, Amsterdam');
    expect(beaconRepo.lastAddressLabel, 'Museumplein 6, Amsterdam');
    expect(beaconRepo.updateBeaconCalls, 1);
  });

  test('updateDraft passes the address label to persistence', () async {
    final env = Env(
      environment: Environment.test,
      beaconCreateMaxPerUser: 3,
    );
    case_ = build(env);

    final beacon = await case_.updateDraft(
      userId: 'Uauth',
      beaconId: 'Bdraft',
      title: 'Draft pickup request',
      description: 'A description that is long enough.',
      addressLabel: '  Prinsengracht 263, Amsterdam  ',
    );

    expect(beacon.addressLabel, 'Prinsengracht 263, Amsterdam');
    expect(beaconRepo.lastAddressLabel, 'Prinsengracht 263, Amsterdam');
    expect(beaconRepo.updateDraftBeaconCalls, 1);
  });
}
