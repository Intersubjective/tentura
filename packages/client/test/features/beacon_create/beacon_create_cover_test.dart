import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_cover_source.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_cover.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/entity/image_picked.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'fake_beacon_ports.dart';

ImagePicked _picked(String fileName) => ImagePicked(
  bytes: Uint8List.fromList([1, 2, 3]),
  fileName: fileName,
);

const _serverA = ImageEntity(id: 'srv-a', authorId: 'author-1');
const _serverB = ImageEntity(id: 'srv-b', authorId: 'author-1');

void main() {
  late FakeBeaconWritePort write;
  late FakeBeaconImagePort images;
  late FakeUiEffectPort effects;
  late BeaconCreateCubit cubit;

  BeaconCreateCubit build() {
    final created = BeaconCreateCubit(
      beaconCreateCase: fakeBeaconCreateCase(write: write, images: images),
      effects: effects,
    );
    addTearDown(created.close);
    return created;
  }

  /// Loads an open beacon so the cubit holds server-identified images, the way
  /// the edit flow does.
  Future<void> seedServerImages(
    List<ImageEntity> seeded, {
    required String coverKey,
    Set<String> needs = const {},
  }) async {
    write.beacon = Beacon.empty.copyWith(
      id: 'b-1',
      status: BeaconStatus.open,
      needs: needs,
      primaryNeedSlug: needs.isEmpty ? null : needs.first,
      images: seeded,
      coverImageId: coverKey,
    );
    await cubit.loadEdit('b-1');
  }

  setUp(() {
    write = FakeBeaconWritePort();
    images = FakeBeaconImagePort();
    effects = FakeUiEffectPort();
    cubit = build();
  });

  group('primary capability', () {
    test('needs promote the canonical-first slug as primary', () {
      cubit.setNeeds({'food', 'transport'});

      expect(cubit.state.primaryNeedSlug, 'transport');
      expect(cubit.state.canSelectSymbolSource, isTrue);
    });

    test('a still-valid primary survives a needs change', () {
      cubit
        ..setNeeds({'food', 'transport'})
        ..setPrimaryNeedSlug('food')
        ..setNeeds({'food', 'transport', 'tools'});

      expect(cubit.state.primaryNeedSlug, 'food');
    });

    test('removing the primary promotes the canonical-first remainder', () {
      cubit
        ..setNeeds({'food', 'transport'})
        ..setPrimaryNeedSlug('food')
        ..removeNeed('food');

      expect(cubit.state.primaryNeedSlug, 'transport');
    });

    test('removing the last capability clears the primary', () {
      cubit
        ..setNeeds({'transport'})
        ..removeNeed('transport');

      expect(cubit.state.primaryNeedSlug, isNull);
      expect(cubit.state.canSelectSymbolSource, isFalse);
    });

    test('a slug outside needs cannot become primary', () {
      cubit
        ..setNeeds({'transport'})
        ..setPrimaryNeedSlug('housing');

      expect(cubit.state.primaryNeedSlug, 'transport');
    });
  });

  group('cover source preference', () {
    test('symbol cannot be selected without a resolvable capability', () {
      cubit.selectSymbolCoverSource();

      expect(cubit.state.coverSource, BeaconCoverSource.photo);
    });

    test('choosing a primary switches the preference to symbol', () {
      cubit
        ..setNeeds({'food', 'transport'})
        ..setPrimaryNeedSlug('food');

      expect(cubit.state.coverSource, BeaconCoverSource.symbol);
      expect(cubit.state.primaryNeedSlug, 'food');
    });

    test('symbol preference keeps the stored photo selection', () async {
      images.picked = [_picked('a.jpg')];
      await cubit.pickImages();
      final coverKey = cubit.state.coverKey;
      cubit
        ..setNeeds({'transport'})
        ..selectSymbolCoverSource();

      expect(cubit.state.coverSource, BeaconCoverSource.symbol);
      expect(cubit.state.coverKey, coverKey);

      cubit.selectPhotoCoverSource();

      expect(cubit.state.coverSource, BeaconCoverSource.photo);
      expect(cubit.state.coverKey, coverKey);
    });

    test('the preview resolves through the shared identity resolver', () async {
      images.picked = [_picked('a.jpg')];
      await cubit.pickImages();

      expect(cubit.state.coverPreview.identity, isA<BeaconIdentityPhoto>());

      cubit
        ..setNeeds({'transport'})
        ..selectSymbolCoverSource();

      expect(cubit.state.coverPreview.identity, isA<BeaconIdentitySymbol>());

      cubit
        ..clearAllImages()
        ..selectPhotoCoverSource();

      // Photo preference with no photo shows the capability symbol.
      expect(cubit.state.coverPreview.identity, isA<BeaconIdentitySymbol>());

      cubit.removeNeed('transport');

      expect(cubit.state.coverPreview.identity, isA<BeaconIdentityNeutral>());
    });
  });

  group('cover selection among photos', () {
    test('the first picked image becomes the cover, later ones do not', () async {
      images.picked = [_picked('a.jpg')];
      await cubit.pickImages();
      final first = cubit.state.coverKey;

      images.picked = [_picked('b.jpg')];
      await cubit.pickImages();

      expect(cubit.state.coverKey, first);
      expect(cubit.state.images, hasLength(2));
    });

    test('picking from the cover block selects the new photo', () async {
      images.picked = [_picked('a.jpg')];
      await cubit.pickImages();
      cubit
        ..setNeeds({'transport'})
        ..selectSymbolCoverSource();

      images.picked = [_picked('b.jpg')];
      await cubit.pickCoverPhoto();

      expect(cubit.state.coverKey, cubit.state.images.last.key);
      expect(cubit.state.coverSource, BeaconCoverSource.photo);
    });

    test('an unknown key cannot be selected as cover', () async {
      images.picked = [_picked('a.jpg')];
      await cubit.pickImages();
      final selected = cubit.state.coverKey;

      cubit.setCoverImageKey('nope');

      expect(cubit.state.coverKey, selected);
    });

    test('deleting the cover selects the first remaining by list order', () async {
      await seedServerImages([_serverA, _serverB], coverKey: 'srv-b');

      cubit.removeImage(1);

      expect(cubit.state.coverKey, 'srv-a');
    });

    test('deleting the last image clears the key but keeps preference', () async {
      await seedServerImages([_serverA], coverKey: 'srv-a');

      cubit.removeImage(0);

      expect(cubit.state.coverKey, isNull);
      expect(cubit.state.coverSource, BeaconCoverSource.photo);
    });

    test('reordering changes order, not the cover identity', () async {
      await seedServerImages([_serverA, _serverB], coverKey: 'srv-b');

      cubit.reorderImages(1, 0);

      expect(cubit.state.images.map((e) => e.id), ['srv-b', 'srv-a']);
      expect(cubit.state.coverKey, 'srv-b');
    });
  });

  group('cover crop', () {
    test('a replacement keeps its position and the cover follows it', () async {
      images.bytes = Uint8List.fromList([4, 5, 6]);
      await seedServerImages([_serverA, _serverB], coverKey: 'srv-a');

      await cubit.adjustCoverCrop(FakeImageCropUi(result: _picked('crop.jpg')));

      final ids = cubit.state.images.map((e) => e.id).toList();
      expect(ids[1], 'srv-b');
      expect(ids.first, isEmpty);
      expect(cubit.state.coverKey, cubit.state.images.first.key);
      expect(images.fetchedUrls, hasLength(1));
    });

    test('cancelling preserves images, cover, and preference', () async {
      await seedServerImages([_serverA, _serverB], coverKey: 'srv-a');

      await cubit.adjustCoverCrop(FakeImageCropUi());

      expect(cubit.state.images.map((e) => e.id), ['srv-a', 'srv-b']);
      expect(cubit.state.coverKey, 'srv-a');
      expect(cubit.state.coverSource, BeaconCoverSource.photo);
    });

    test('a byte fetch failure surfaces an error and changes nothing', () async {
      images.fetchError = Exception('offline');
      await seedServerImages([_serverA], coverKey: 'srv-a');

      await cubit.adjustCoverCrop(FakeImageCropUi(result: _picked('c.jpg')));

      expect(effects.emitted.whereType<ShowError>(), hasLength(1));
      expect(cubit.state.images.map((e) => e.id), ['srv-a']);
      expect(cubit.state.coverKey, 'srv-a');
    });

    test('there is nothing to crop without a selected cover', () async {
      final cropUi = FakeImageCropUi(result: _picked('c.jpg'));

      await cubit.adjustCoverCrop(cropUi);

      expect(cropUi.calls, 0);
      expect(effects.emitted, isEmpty);
    });
  });

  group('server round trips', () {
    test('an edit load seeds primary, cover key, and preference', () async {
      write.beacon = Beacon.empty.copyWith(
        id: 'b-1',
        status: BeaconStatus.open,
        needs: {'transport'},
        primaryNeedSlug: 'transport',
        images: const [_serverA, _serverB],
        coverImageId: 'srv-b',
        coverSource: BeaconCoverSource.symbol,
      );

      await cubit.loadEdit('b-1');

      expect(cubit.state.primaryNeedSlug, 'transport');
      expect(cubit.state.coverKey, 'srv-b');
      expect(cubit.state.coverSource, BeaconCoverSource.symbol);
      expect(cubit.state.initialServerImageIds, {'srv-a', 'srv-b'});
    });

    test('a draft save replaces local keys with published ids', () async {
      write.stageIds.addAll(['srv-1', 'srv-2']);
      images.picked = [_picked('a.jpg'), _picked('b.jpg')];
      await cubit.pickImages();
      cubit.setTitle('Move a piano');

      await cubit.ensureDraft(context: '');

      expect(cubit.state.draftId, 'server-beacon');
      expect(cubit.state.images.map((e) => e.id), ['srv-1', 'srv-2']);
      expect(cubit.state.coverKey, 'srv-1');
      expect(write.setMediaCalls.single.coverImageId, 'srv-1');
    });

    test('a failed save keeps the beacon id and staged progress', () async {
      write
        ..stageIds.add('srv-1')
        ..failStageAtCall = 1;
      images.picked = [_picked('a.jpg'), _picked('b.jpg')];
      await cubit.pickImages();
      cubit.setTitle('Move a piano');

      await cubit.ensureDraft(context: '');

      expect(effects.emitted.whereType<ShowError>(), hasLength(1));
      expect(cubit.state.draftId, 'server-beacon');
      expect(cubit.state.images.map((e) => e.id), ['srv-1', '']);
      expect(cubit.state.coverKey, 'srv-1');
    });
  });
}
