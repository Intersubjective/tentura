import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/image_picked.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'fake_beacon_ports.dart';

ImagePicked _picked(String fileName) => ImagePicked(
  bytes: Uint8List.fromList([1, 2, 3]),
  fileName: fileName,
);

/// Issue #164 — deleted gallery images snap back after ~1s autosave.
void main() {
  test(
    'in-flight draft save must not restore an image removed while persisting',
    () async {
      final write = FakeBeaconWritePort()..stageIds.add('srv-1');
      final images = FakeBeaconImagePort(picked: [_picked('a.jpg')]);
      final cubit = BeaconCreateCubit(
        beaconCreateCase: fakeBeaconCreateCase(write: write, images: images),
        effects: FakeUiEffectPort(),
      );
      addTearDown(cubit.close);
      cubit.setAutosaveContext('');

      cubit
        ..setTitle('Valid title')
        ..setDescription('A description that is required.');
      await cubit.pickImages();
      await cubit.ensureDraft(context: '');
      expect(cubit.state.images, hasLength(1));
      expect(cubit.state.draftId, isNotNull);

      final hold = Completer<void>();
      write.setMediaHold = hold;

      cubit.setDescription('A description that is required. Tweaked.');
      final inFlight = cubit.flushAutosave();
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.isAutosaving, isTrue);

      cubit.removeImage(0);
      expect(cubit.state.images, isEmpty);

      hold.complete();
      await inFlight;
      expect(cubit.state.isAutosaving, isFalse);

      expect(
        cubit.state.images,
        isEmpty,
        reason:
            'Issue #164: stale saveDraft must not overwrite local removal via '
            '_applyServerMedia',
      );

      await Future<void>.delayed(const Duration(seconds: 2));
      expect(
        cubit.state.images,
        isEmpty,
        reason:
            'Issue #164: missed autosave while isAutosaving must not leave '
            'deleted images on screen',
      );
    },
  );
}
