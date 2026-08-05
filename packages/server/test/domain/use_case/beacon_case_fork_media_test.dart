import 'dart:async';
import 'dart:typed_data';

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/entity/beacon_cover_source.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/image_entity.dart';
import 'package:tentura_server/domain/entity/task_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_access_guard.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/image_object_gc_port.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/use_case/beacon_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/noop_commitment_query_case.dart';

class _ForkBeaconRepo extends Fake implements BeaconRepositoryPort {
  _ForkBeaconRepo(this.source);

  BeaconEntity source;
  final createBeaconCalls =
      <
        ({
          List<String>? imageIds,
          String? coverImageId,
          BeaconCoverSource coverSource,
        })
      >[];
  Object? createFailure;

  @override
  Future<int> countRecentByAuthor({
    required String userId,
    required Duration window,
  }) async => 0;

  @override
  Future<BeaconEntity> getBeaconById({
    required String beaconId,
    String? filterByUserId,
  }) async => source;

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
    createBeaconCalls.add((
      imageIds: imageIds,
      coverImageId: coverImageId,
      coverSource: coverSource,
    ));
    if (createFailure != null) throw createFailure!;
    return BeaconEntity(
      id: 'Bfork',
      title: title,
      author: UserEntity(id: authorId),
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      status: status ?? BeaconStatus.draft,
      images: [
        for (final id in imageIds ?? const <String>[])
          ImageEntity(id: id, authorId: authorId, createdAt: DateTime.utc(2026)),
      ],
      coverImageId: coverImageId,
      coverSource: coverSource,
      lineageParentBeaconId: lineageParentBeaconId,
      lineageRootBeaconId: lineageRootBeaconId,
    );
  }
}

class _CopyingImageRepo extends Fake implements ImageRepositoryPort {
  int putCalls = 0;
  int failOnPutIndex = -1;
  final compensatedUploads = <({String authorId, String imageId})>[];

  @override
  Future<Uint8List> get({required String id}) async =>
      Uint8List.fromList(id.codeUnits);

  @override
  Future<String> put({
    required String authorId,
    required Stream<Uint8List> bytes,
  }) async {
    final index = putCalls;
    putCalls++;
    if (index == failOnPutIndex) {
      throw StateError('remote write failed for copy $index');
    }
    return 'Icopy$index';
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
  @override
  Future<String> schedule(TaskEntity task) async => 'T1';
}

class _AllowGuard implements BeaconAccessGuard {
  bool allowed = true;

  @override
  Future<bool> canReadContent({
    required String beaconId,
    required String viewerId,
  }) async => allowed;

  @override
  Future<bool> canReadInvolvement({
    required String beaconId,
    required String viewerId,
  }) async => allowed;

  @override
  Future<bool> canReadTombstone({
    required String beaconId,
    required String viewerId,
  }) async => allowed;
}

void main() {
  late _ForkBeaconRepo beaconRepo;
  late _CopyingImageRepo imageRepo;
  late _AllowGuard guard;
  late BeaconCase case_;
  final now = DateTime.utc(2026, 6, 25);

  BeaconEntity sourceBeacon({
    required String authorId,
    List<ImageEntity> images = const [],
    String? coverImageId,
  }) => BeaconEntity(
    id: 'Bsrc',
    title: 'Source title',
    author: UserEntity(id: authorId),
    createdAt: now,
    updatedAt: now,
    status: BeaconStatus.open,
    images: images,
    coverImageId: coverImageId,
    coverSource: BeaconCoverSource.photo,
  );

  setUp(() {
    guard = _AllowGuard();
    imageRepo = _CopyingImageRepo();
    beaconRepo = _ForkBeaconRepo(
      sourceBeacon(authorId: 'Uauth'),
    );
    case_ = BeaconCase(
      beaconRepo,
      imageRepo,
      _FakeImageObjectGc(),
      _FakeTaskRepo(),
      noopCommitmentQueryCase(),
      guard,
      env: Env(environment: Environment.test),
      logger: Logger('BeaconCaseForkMediaTest'),
    );
  });

  test(
    'copies images in order and maps the cover to the new copy',
    () async {
      final img1 = ImageEntity(id: 'Isrc1', authorId: 'Uauth', createdAt: now);
      final img2 = ImageEntity(id: 'Isrc2', authorId: 'Uauth', createdAt: now);
      beaconRepo.source = sourceBeacon(
        authorId: 'Uauth',
        images: [img1, img2],
        coverImageId: 'Isrc2',
      );

      final forked = await case_.fork(sourceId: 'Bsrc', userId: 'Uauth');

      expect(forked.id, 'Bfork');
      final call = beaconRepo.createBeaconCalls.single;
      expect(call.imageIds, ['Icopy0', 'Icopy1']);
      expect(call.coverImageId, 'Icopy1');
    },
  );

  test(
    'a viewer who is not the author never copies source images',
    () async {
      beaconRepo.source = sourceBeacon(
        authorId: 'Uauth',
        images: [ImageEntity(id: 'Isrc1', authorId: 'Uauth', createdAt: now)],
      );

      final forked = await case_.fork(sourceId: 'Bsrc', userId: 'Uviewer');

      expect(forked.id, 'Bfork');
      expect(imageRepo.putCalls, 0);
      final call = beaconRepo.createBeaconCalls.single;
      expect(call.imageIds, isNull);
    },
  );

  test(
    'a mid-copy remote failure compensates every already-copied image and rethrows',
    () async {
      beaconRepo.source = sourceBeacon(
        authorId: 'Uauth',
        images: [
          ImageEntity(id: 'Isrc1', authorId: 'Uauth', createdAt: now),
          ImageEntity(id: 'Isrc2', authorId: 'Uauth', createdAt: now),
          ImageEntity(id: 'Isrc3', authorId: 'Uauth', createdAt: now),
        ],
      );
      imageRepo.failOnPutIndex = 2;

      await expectLater(
        case_.fork(sourceId: 'Bsrc', userId: 'Uauth'),
        throwsA(isA<StateError>()),
      );

      expect(imageRepo.compensatedUploads, [
        (authorId: 'Uauth', imageId: 'Icopy0'),
        (authorId: 'Uauth', imageId: 'Icopy1'),
      ]);
      expect(beaconRepo.createBeaconCalls, isEmpty);
    },
  );

  test(
    'a final createBeacon failure after all copies compensates every copy',
    () async {
      beaconRepo.source = sourceBeacon(
        authorId: 'Uauth',
        images: [
          ImageEntity(id: 'Isrc1', authorId: 'Uauth', createdAt: now),
          ImageEntity(id: 'Isrc2', authorId: 'Uauth', createdAt: now),
        ],
      );
      beaconRepo.createFailure = StateError('database write failed');

      await expectLater(
        case_.fork(sourceId: 'Bsrc', userId: 'Uauth'),
        throwsA(isA<StateError>()),
      );

      expect(imageRepo.compensatedUploads, [
        (authorId: 'Uauth', imageId: 'Icopy0'),
        (authorId: 'Uauth', imageId: 'Icopy1'),
      ]);
    },
  );

  test('an unreadable source blocks the fork with no copies', () async {
    guard.allowed = false;
    beaconRepo.source = sourceBeacon(
      authorId: 'Uauth',
      images: [ImageEntity(id: 'Isrc1', authorId: 'Uauth', createdAt: now)],
    );

    await expectLater(
      case_.fork(sourceId: 'Bsrc', userId: 'Uviewer'),
      throwsA(isA<Object>()),
    );
    expect(imageRepo.putCalls, 0);
  });
}
