import 'package:test/test.dart';

import 'package:tentura_root/domain/entity/beacon_cover_source.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/data/repository/mock/beacon_repository_mock.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/image_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';

/// B006 — `replaceMedia` contract: a staged image that becomes the cover
/// thumbnail is promoted, so it is not among the ids reported as discarded
/// (the caller garbage-collects those). The Postgres repository follows the
/// same rule; this pins it on the in-memory double the use-case tests use.
void main() {
  const beaconId = 'B-thumb-contract';
  const repo = BeaconRepositoryMock();
  final now = DateTime.utc(2026, 10, 14);

  setUp(() {
    BeaconRepositoryMock.storageById[beaconId] = BeaconEntity(
      id: beaconId,
      title: 'Title',
      author: const UserEntity(id: 'Uauth'),
      createdAt: now,
      updatedAt: now,
      status: BeaconStatus.draft,
      images: [ImageEntity(id: 'I1', authorId: 'Uauth', createdAt: now)],
      coverImageId: 'I1',
    );
    BeaconRepositoryMock.stagesByBeaconId[beaconId] = {
      'Ithumb': now,
      'Istale': now,
    };
  });

  tearDown(() {
    BeaconRepositoryMock.storageById.remove(beaconId);
    BeaconRepositoryMock.stagesByBeaconId.remove(beaconId);
  });

  test('the staged cover thumbnail is not reported as discarded', () async {
    final removed = await repo.replaceMedia(
      beaconId: beaconId,
      imageIds: const ['I1'],
      coverImageId: 'I1',
      coverSource: BeaconCoverSource.photo,
      coverThumbImageId: 'Ithumb',
    );

    expect(removed, ['Istale']);
    expect(
      BeaconRepositoryMock.storageById[beaconId]!.coverThumbImageId,
      'Ithumb',
    );
    expect(BeaconRepositoryMock.stagesByBeaconId[beaconId], isEmpty);
  });

  test('a later save with the same thumbnail removes nothing', () async {
    await repo.replaceMedia(
      beaconId: beaconId,
      imageIds: const ['I1'],
      coverImageId: 'I1',
      coverSource: BeaconCoverSource.photo,
      coverThumbImageId: 'Ithumb',
    );
    final removed = await repo.replaceMedia(
      beaconId: beaconId,
      imageIds: const ['I1'],
      coverImageId: 'I1',
      coverSource: BeaconCoverSource.photo,
      coverThumbImageId: 'Ithumb',
    );

    expect(removed, isEmpty);
  });
}
