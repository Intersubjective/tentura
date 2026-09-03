import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/ui/bloc/state_base.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'fake_beacon_ports.dart';

void main() {
  test('quiet autosave skips short titles and edit/live', () async {
    final write = FakeBeaconWritePort();
    final cubit = BeaconCreateCubit(
      beaconCreateCase: fakeBeaconCreateCase(write: write),
      effects: FakeUiEffectPort(),
    );
    addTearDown(cubit.close);
    cubit.setAutosaveContext('');

    cubit.setTitle('ab');
    await cubit.flushAutosave();
    expect(write.createdFields, isEmpty);
    expect(cubit.state.isAutosaving, isFalse);
    expect(cubit.state.status, isA<StateIsSuccess>());

    cubit.setTitle('Valid title');
    cubit.setDescription('A description that is required.');
    await cubit.flushAutosave();
    expect(write.createdFields, isNotEmpty);
    expect(cubit.state.isLoading, isFalse);
    expect(cubit.state.draftId, isNotNull);
    expect(cubit.state.lastAutosavedAt, isNotNull);
  });

  test(
    'title shorter than min length never persists Draft placeholder',
    () async {
      final write = FakeBeaconWritePort();
      final cubit = BeaconCreateCubit(
        beaconCreateCase: fakeBeaconCreateCase(write: write),
        effects: FakeUiEffectPort(),
      );
      addTearDown(cubit.close);
      cubit.setAutosaveContext('');

      cubit.setTitle('x' * (kTitleMinLength - 1));
      await cubit.flushAutosave();
      expect(write.createdFields, isEmpty);
    },
  );

  test('flushAutosave waits for an in-flight quiet persist', () async {
    final hold = Completer<void>();
    final write = FakeBeaconWritePort()..createHold = hold;
    final cubit = BeaconCreateCubit(
      beaconCreateCase: fakeBeaconCreateCase(write: write),
      effects: FakeUiEffectPort(),
    );
    addTearDown(cubit.close);
    cubit.setAutosaveContext('');
    cubit
      ..setTitle('Valid title')
      ..setDescription('A description that is required.');

    final first = cubit.flushAutosave();
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.isAutosaving, isTrue);

    final second = cubit.flushAutosave();
    hold.complete();
    await Future.wait([first, second]);
    expect(cubit.state.isAutosaving, isFalse);
    expect(write.createdFields, hasLength(1));
  });
}
