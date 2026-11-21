import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/entity/image_picked.dart';
import 'package:tentura/domain/port/beacon_image_port.dart';
import 'package:tentura/domain/port/beacon_write_port.dart';
import 'package:tentura/domain/use_case/beacon_create_case.dart';

import '../features/beacon_create/fake_beacon_ports.dart';

typedef BeaconCreateCaseFactory =
    BeaconCreateCase Function({
      BeaconWritePort? beacons,
      BeaconImagePort? images,
    });

void registerBeaconCreateCaseFactoryTests(BeaconCreateCaseFactory buildCase) {
  test('default cases keep draft writes isolated', () async {
    final first = buildCase();
    final second = buildCase();
    const draftId = 'draft-1';
    const title = 'Move a piano';
    final saved = await first.saveDraft(
      BeaconSaveCommand(
        fields: Beacon.empty.copyWith(id: draftId, title: title),
        images: const [],
        coverKey: null,
      ),
    );

    expect(saved.beacon.title, title);
    expect((await first.fetchById(draftId)).title, title);
    expect(await second.fetchById(draftId), Beacon.empty);
  });

  test('default cases deliver independent crop buffers', () async {
    final first = buildCase();
    final second = buildCase();
    const image = ImageEntity(id: 'cover', authorId: 'author');
    const url = 'https://example.test/cover.png';

    final edited = await first.adjustCoverCrop(
      image: image,
      imageUrl: url,
      cropUi: _DefaultCoverCrop()..replaceFirstByte = 0,
    );
    final untouched = await second.adjustCoverCrop(
      image: image,
      imageUrl: url,
      cropUi: _DefaultCoverCrop(),
    );

    expect(edited?.imageBytes?.first, 0);
    expect(untouched?.imageBytes, orderedEquals(kTinyPng));
    expect(await first.pickImages(), isEmpty);
    expect(await second.pickImages(), isEmpty);
  });

  test(
    'publishing and deleting record IDs on the supplied write port',
    () async {
      final write = FakeBeaconWritePort();
      final createCase = buildCase(beacons: write);

      await createCase.publishDraft('b1');
      await createCase.delete('b2');

      expect(write.publishedIds, ['b1']);
      expect(write.deletedIds, ['b2']);
    },
  );

  test(
    'the supplied image picker yields images with distinct local keys',
    () async {
      final picked = [
        ImagePicked(bytes: Uint8List.fromList(kTinyPng), fileName: 'first.png'),
        ImagePicked(
          bytes: Uint8List.fromList(kTinyPng),
          fileName: 'second.png',
        ),
      ];
      final images = FakeBeaconImagePort(picked: picked);
      final createCase = buildCase(images: images);

      final results = await createCase.pickImages();

      expect(results.map((image) => image.fileName), [
        'first.png',
        'second.png',
      ]);
      final keys = results.map((image) => image.localKey);
      expect(keys, everyElement(isNotEmpty));
      expect(keys.toSet(), hasLength(2));
    },
  );
}

class _DefaultCoverCrop implements ImageCropUiPort {
  int? replaceFirstByte;

  @override
  Future<ImagePicked> cropSquare(Uint8List bytes) async {
    final replacement = replaceFirstByte;
    if (replacement != null) bytes[0] = replacement;
    return ImagePicked(bytes: bytes, fileName: 'cover.png');
  }
}
