import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_cover_source.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/entity/image_picked.dart';
import 'package:tentura/domain/use_case/beacon_create_case.dart';

import 'fake_beacon_ports.dart';

ImageEntity _local(String key) => ImageEntity(
  localKey: key,
  fileName: '$key.jpg',
  imageBytes: Uint8List.fromList([1, 2, 3]),
);

const _server = ImageEntity(id: 'srv-1', authorId: 'author-1');

Beacon _fields({String id = ''}) => Beacon.empty.copyWith(
  id: id,
  title: 'Move a piano',
  needs: {'transport'},
  primaryNeedSlug: 'transport',
  coverSource: BeaconCoverSource.photo,
);

BeaconSaveCommand _command({
  String id = '',
  List<ImageEntity> images = const [],
  String? coverKey,
  bool draft = false,
}) => BeaconSaveCommand(
  fields: _fields(id: id),
  images: images,
  coverKey: coverKey,
  draft: draft,
);

void main() {
  group('field command selection', () {
    test('create only calls create and forwards the draft flag', () async {
      final write = FakeBeaconWritePort();
      final sut = BeaconCreateCase(write, FakeBeaconImagePort());

      await sut.create(_command(draft: true));

      expect(write.createdFields, hasLength(1));
      expect(write.updatedDraftFields, isEmpty);
      expect(write.updatedFields, isEmpty);
      expect(write.createdFields.single.primaryNeedSlug, 'transport');
    });

    test('saveDraft only calls updateDraft', () async {
      final write = FakeBeaconWritePort();
      final sut = BeaconCreateCase(write, FakeBeaconImagePort());

      await sut.saveDraft(_command(id: 'b-1'));

      expect(write.updatedDraftFields, hasLength(1));
      expect(write.createdFields, isEmpty);
      expect(write.updatedFields, isEmpty);
    });

    test('saveEdit only calls update', () async {
      final write = FakeBeaconWritePort();
      final sut = BeaconCreateCase(write, FakeBeaconImagePort());

      await sut.saveEdit(_command(id: 'b-1'));

      expect(write.updatedFields, hasLength(1));
      expect(write.createdFields, isEmpty);
      expect(write.updatedDraftFields, isEmpty);
    });
  });

  group('media reconciliation', () {
    test('every local image is staged; none rides along with create', () async {
      final write = FakeBeaconWritePort()..stageIds.addAll(['s1', 's2']);
      final sut = BeaconCreateCase(write, FakeBeaconImagePort());

      final result = await sut.create(
        _command(images: [_local('k1'), _local('k2')], coverKey: 'k1'),
      );

      expect(write.stagedKeys, ['k1', 'k2']);
      expect(result.images.map((e) => e.id), ['s1', 's2']);
    });

    test('reconciles exactly once and sends the staged ids in order', () async {
      final write = FakeBeaconWritePort()..stageIds.addAll(['s1', 's2']);
      final sut = BeaconCreateCase(write, FakeBeaconImagePort());

      await sut.create(
        _command(images: [_local('k1'), _local('k2')], coverKey: 'k2'),
      );

      expect(write.setMediaCalls, hasLength(1));
      final call = write.setMediaCalls.single;
      expect(call.imageIds, ['s1', 's2']);
      expect(call.coverImageId, 's2');
      expect(call.coverSource, BeaconCoverSource.photo);
    });

    test('an already staged image is not staged again', () async {
      final write = FakeBeaconWritePort()..stageIds.add('s2');
      final sut = BeaconCreateCase(write, FakeBeaconImagePort());

      await sut.saveEdit(
        _command(id: 'b-1', images: [_server, _local('k2')], coverKey: 'srv-1'),
      );

      expect(write.stagedKeys, ['k2']);
      expect(write.setMediaCalls.single.imageIds, ['srv-1', 's2']);
      expect(write.setMediaCalls.single.coverImageId, 'srv-1');
    });

    test('a stale cover selection falls back to the first image', () async {
      final write = FakeBeaconWritePort()..stageIds.add('s1');
      final sut = BeaconCreateCase(write, FakeBeaconImagePort());

      await sut.create(_command(images: [_local('k1')], coverKey: 'gone'));

      expect(write.setMediaCalls.single.coverImageId, 's1');
    });

    test('no images means no cover id and an empty list', () async {
      final write = FakeBeaconWritePort();
      final sut = BeaconCreateCase(write, FakeBeaconImagePort());

      await sut.create(_command());

      expect(write.setMediaCalls.single.imageIds, isEmpty);
      expect(write.setMediaCalls.single.coverImageId, isNull);
    });

    test('symbol preference still publishes the photo selection', () async {
      final write = FakeBeaconWritePort()..stageIds.add('s1');
      final sut = BeaconCreateCase(write, FakeBeaconImagePort());

      await sut.create(
        BeaconSaveCommand(
          fields: _fields().copyWith(coverSource: BeaconCoverSource.symbol),
          images: [_local('k1')],
          coverKey: 'k1',
        ),
      );

      expect(write.setMediaCalls.single.coverImageId, 's1');
      expect(write.setMediaCalls.single.coverSource, BeaconCoverSource.symbol);
    });
  });

  group('failure carries progress forward', () {
    test('a failed field command reports the fields phase', () async {
      final write = FakeBeaconWritePort()..createError = Exception('boom');
      final sut = BeaconCreateCase(write, FakeBeaconImagePort());

      await expectLater(
        sut.create(_command(images: [_local('k1')], coverKey: 'k1')),
        throwsA(
          isA<BeaconSaveFailure>()
              .having((e) => e.phase, 'phase', BeaconSavePhase.fields)
              .having((e) => e.beaconId, 'beaconId', isNull)
              .having((e) => e.coverKey, 'coverKey', 'k1'),
        ),
      );
      expect(write.setMediaCalls, isEmpty);
    });

    test('a partial stage keeps ids that already succeeded', () async {
      final write = FakeBeaconWritePort()
        ..stageIds.add('s1')
        ..failStageAtCall = 1;
      final sut = BeaconCreateCase(write, FakeBeaconImagePort());

      BeaconSaveFailure? failure;
      try {
        await sut.create(
          _command(images: [_local('k1'), _local('k2')], coverKey: 'k1'),
        );
      } on BeaconSaveFailure catch (e) {
        failure = e;
      }

      expect(failure, isNotNull);
      expect(failure!.phase, BeaconSavePhase.stage);
      expect(failure.beaconId, 'server-beacon');
      expect(failure.images.map((e) => e.id), ['s1', '']);
      expect(failure.coverKey, 's1');
      expect(write.setMediaCalls, isEmpty);
    });

    test('a retry re-uses staged ids and only stages what is left', () async {
      final write = FakeBeaconWritePort()
        ..stageIds.addAll(['s1', 's2'])
        ..failStageAtCall = 1;
      final sut = BeaconCreateCase(write, FakeBeaconImagePort());

      BeaconSaveFailure? failure;
      try {
        await sut.create(
          _command(images: [_local('k1'), _local('k2')], coverKey: 'k1'),
        );
      } on BeaconSaveFailure catch (e) {
        failure = e;
      }
      write
        ..failStageAtCall = null
        ..stagedKeys.clear();

      final result = await sut.saveDraft(
        _command(
          id: failure!.beaconId!,
          images: failure.images,
          coverKey: failure.coverKey,
        ),
      );

      expect(write.stagedKeys, ['k2']);
      expect(result.images.map((e) => e.id), ['s1', 's2']);
      expect(write.setMediaCalls.single.imageIds, ['s1', 's2']);
      expect(write.setMediaCalls.single.coverImageId, 's1');
    });

    test('a rejected reconciliation re-stages expired images once', () async {
      final write = FakeBeaconWritePort()
        ..stageIds.addAll(['s1', 's2', 's3', 's4'])
        ..failSetMediaAtCall = 0;
      final sut = BeaconCreateCase(write, FakeBeaconImagePort());

      final result = await sut.create(
        _command(images: [_local('k1'), _local('k2')], coverKey: 'k1'),
      );

      expect(write.stagedKeys, ['k1', 'k2', 'k1', 'k2']);
      expect(write.setMediaCalls, hasLength(2));
      expect(write.setMediaCalls.last.imageIds, ['s3', 's4']);
      expect(write.setMediaCalls.last.coverImageId, 's3');
      expect(result.images.map((e) => e.id), ['s3', 's4']);
    });

    test('recovery is not attempted without local bytes to re-send', () async {
      final write = FakeBeaconWritePort()..failSetMediaAtCall = 0;
      final sut = BeaconCreateCase(write, FakeBeaconImagePort());

      await expectLater(
        sut.saveEdit(
          _command(id: 'b-1', images: const [_server], coverKey: 'srv-1'),
        ),
        throwsA(
          isA<BeaconSaveFailure>()
              .having((e) => e.phase, 'phase', BeaconSavePhase.reconcile)
              .having((e) => e.beaconId, 'beaconId', 'b-1')
              .having((e) => e.coverKey, 'coverKey', 'srv-1'),
        ),
      );
      expect(write.setMediaCalls, hasLength(1));
    });
  });

  group('image acquisition', () {
    test('every picked image gets a distinct local key', () async {
      final images = FakeBeaconImagePort(
        picked: [
          _picked('a.jpg'),
          _picked('b.jpg'),
        ],
      );
      final sut = BeaconCreateCase(FakeBeaconWritePort(), images);

      final picked = await sut.pickImages();

      expect(picked, hasLength(2));
      expect(picked.first.localKey, isNotEmpty);
      expect(picked.first.key, isNot(picked.last.key));
      expect(picked.every((e) => e.id.isEmpty), isTrue);
    });

    test('cover crop uses held bytes and never fetches', () async {
      final images = FakeBeaconImagePort();
      final cropUi = FakeImageCropUi(result: _picked('cropped.jpg'));
      final sut = BeaconCreateCase(FakeBeaconWritePort(), images);

      final replacement = await sut.adjustCoverCrop(
        image: _local('k1'),
        imageUrl: 'https://example.test/k1.jpg',
        cropUi: cropUi,
      );

      expect(images.fetchedUrls, isEmpty);
      expect(replacement, isNotNull);
      expect(replacement!.id, isEmpty);
      expect(replacement.localKey, isNotEmpty);
    });

    test('cover crop fetches server bytes when none are held', () async {
      final images = FakeBeaconImagePort();
      final cropUi = FakeImageCropUi(result: _picked('cropped.jpg'));
      final sut = BeaconCreateCase(FakeBeaconWritePort(), images);

      await sut.adjustCoverCrop(
        image: _server,
        imageUrl: 'https://example.test/srv-1.jpg',
        cropUi: cropUi,
      );

      expect(images.fetchedUrls, ['https://example.test/srv-1.jpg']);
    });

    test('a cancelled crop returns null', () async {
      final sut = BeaconCreateCase(
        FakeBeaconWritePort(),
        FakeBeaconImagePort(),
      );

      final replacement = await sut.adjustCoverCrop(
        image: _local('k1'),
        imageUrl: 'https://example.test/k1.jpg',
        cropUi: FakeImageCropUi(),
      );

      expect(replacement, isNull);
    });

    test('a failed byte fetch propagates instead of cropping', () async {
      final images = FakeBeaconImagePort()..fetchError = Exception('offline');
      final cropUi = FakeImageCropUi(result: _picked('cropped.jpg'));
      final sut = BeaconCreateCase(FakeBeaconWritePort(), images);

      await expectLater(
        sut.adjustCoverCrop(
          image: _server,
          imageUrl: 'https://example.test/srv-1.jpg',
          cropUi: cropUi,
        ),
        throwsA(isA<Exception>()),
      );
      expect(cropUi.calls, 0);
    });
  });
}

ImagePicked _picked(String fileName) => ImagePicked(
  bytes: Uint8List.fromList([9, 9, 9]),
  fileName: fileName,
);
