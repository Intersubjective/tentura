import 'dart:async';
import 'dart:typed_data';

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/entity/beacon_cover_source.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/task_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/image_object_gc_port.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/use_case/beacon_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/fake_beacon_access_guard.dart';
import '../../support/noop_commitment_query_case.dart';

class _FailingCreateBeaconRepo extends Fake implements BeaconRepositoryPort {
  int recentCount = 0;
  Object failure = StateError('database write failed');

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
    String? primaryNeedSlug,
    String? coverImageId,
    BeaconCoverSource coverSource = BeaconCoverSource.photo,
    BeaconStatus? status,
    String? addressLabel,
    String? lineageParentBeaconId,
    String? lineageRootBeaconId,
  }) async {
    throw failure;
  }
}

class _TrackingImageRepo extends Fake implements ImageRepositoryPort {
  var nextPutIds = <String>['Inew'];
  var _putCalls = 0;
  final compensatedUploads = <({String authorId, String imageId})>[];

  @override
  Future<String> put({
    required String authorId,
    required Stream<Uint8List> bytes,
  }) async {
    final id = nextPutIds[_putCalls];
    _putCalls++;
    return id;
  }

  @override
  Future<void> compensateOrphanedUpload({
    required String imageId,
    required String authorId,
  }) async {
    compensatedUploads.add((authorId: authorId, imageId: imageId));
  }
}

class _FakeImageObjectGc extends Fake implements ImageObjectGcPort {}

class _FakeTaskRepo extends Fake implements TaskRepositoryPort {
  final scheduled = <String>[];

  @override
  Future<String> schedule(TaskEntity task) async {
    scheduled.add('T${scheduled.length + 1}');
    return scheduled.last;
  }
}

void main() {
  late _FailingCreateBeaconRepo beaconRepo;
  late _TrackingImageRepo imageRepo;
  late BeaconCase case_;

  setUp(() {
    beaconRepo = _FailingCreateBeaconRepo();
    imageRepo = _TrackingImageRepo();
    case_ = BeaconCase(
      beaconRepo,
      imageRepo,
      _FakeImageObjectGc(),
      _FakeTaskRepo(),
      noopCommitmentQueryCase(),
      FakeBeaconAccessGuard(),
      env: Env(environment: Environment.test),
      logger: Logger('BeaconCaseCreateMediaCleanupTest'),
    );
  });

  test(
    'a database failure after upload compensates the orphaned image in a new transaction',
    () async {
      await expectLater(
        case_.create(
          userId: 'Uauth',
          title: 'Pickup request',
          description: 'A description that is long enough.',
          imageBytes: const Stream.empty(),
        ),
        throwsA(isA<StateError>()),
      );

      expect(imageRepo.compensatedUploads, [
        (authorId: 'Uauth', imageId: 'Inew'),
      ]);
    },
  );

  test('rethrows the original database failure, not a compensation error',
      () async {
    beaconRepo.failure = ArgumentError('bad payload');

    await expectLater(
      case_.create(
        userId: 'Uauth',
        title: 'Pickup request',
        description: 'A description that is long enough.',
        imageBytes: const Stream.empty(),
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('a rate-limited create never uploads or compensates', () async {
    final env = Env(environment: Environment.test, beaconCreateMaxPerUser: 1);
    case_ = BeaconCase(
      beaconRepo,
      imageRepo,
      _FakeImageObjectGc(),
      _FakeTaskRepo(),
      noopCommitmentQueryCase(),
      FakeBeaconAccessGuard(),
      env: env,
      logger: Logger('BeaconCaseCreateMediaCleanupTest'),
    );
    beaconRepo.recentCount = 1;

    await expectLater(
      case_.create(
        userId: 'Uauth',
        title: 'Pickup request',
        description: 'A description that is long enough.',
        imageBytes: const Stream.empty(),
      ),
      throwsA(isA<RateLimitedException>()),
    );

    expect(imageRepo.compensatedUploads, isEmpty);
  });
}
