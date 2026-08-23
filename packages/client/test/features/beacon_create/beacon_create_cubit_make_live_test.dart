import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/forward/domain/entity/forward_candidate.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/forward/ui/bloc/forward_state.dart';
import 'package:tentura/ui/effect/ui_effect.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'fake_beacon_ports.dart';

BeaconCreateCubit _cubit({
  required FakeBeaconWritePort write,
  FakeUiEffectPort? effects,
}) => BeaconCreateCubit(
  beaconCreateCase: fakeBeaconCreateCase(write: write),
  effects: effects ?? FakeUiEffectPort(),
);

void _fillRequired(BeaconCreateCubit cubit) {
  cubit
    ..setTitle('Need a piano moved')
    ..setDescription('Two flights of stairs, this weekend.');
}

void main() {
  test('makeLive publishes, sets isLive, and does not navigate back', () async {
    final write = FakeBeaconWritePort(
      beacon: Beacon.empty.copyWith(id: 'B1', status: BeaconStatus.draft),
    );
    final effects = FakeUiEffectPort();
    final cubit = _cubit(write: write, effects: effects);
    addTearDown(cubit.close);
    _fillRequired(cubit);

    await cubit.makeLive(context: 'c');

    expect(cubit.state.isLive, isTrue);
    expect(cubit.state.draftId, 'B1');
    expect(cubit.state.editId, isNull);
    expect(write.publishedIds, ['B1']);
    expect(effects.emitted.whereType<NavigateBack>(), isEmpty);
  });

  test(
    'makeLive on an already-open id sets isLive and does not throw',
    () async {
      final write = FakeBeaconWritePort(
        beacon: Beacon.empty.copyWith(id: 'B1', status: BeaconStatus.open),
      )..updateDraftError = Exception('Request is not an editable draft');
      final effects = FakeUiEffectPort();
      final cubit = _cubit(write: write, effects: effects);
      addTearDown(cubit.close);
      _fillRequired(cubit);
      await cubit.ensureDraft(context: 'c', showMessage: false);

      await cubit.makeLive(context: 'c');

      expect(cubit.state.isLive, isTrue);
      expect(cubit.state.editId, isNull);
      expect(write.publishedIds, isNotEmpty);
      expect(effects.emitted.whereType<NavigateBack>(), isEmpty);
      expect(effects.emitted.whereType<ShowError>(), isEmpty);
    },
  );

  test('saveEdit stay path does not navigate back', () async {
    final write = FakeBeaconWritePort(
      beacon: Beacon.empty.copyWith(id: 'B1', status: BeaconStatus.draft),
    );
    final effects = FakeUiEffectPort();
    final cubit = _cubit(write: write, effects: effects);
    addTearDown(cubit.close);
    _fillRequired(cubit);
    await cubit.makeLive(context: 'c');
    effects.clear();
    cubit.setTitle('Need a piano moved today');

    await cubit.saveEdit(context: 'c', navigateBack: false);

    expect(write.updatedFields, isNotEmpty);
    expect(effects.emitted.whereType<NavigateBack>(), isEmpty);
    expect(cubit.state.isLive, isTrue);
  });

  test(
    'sendRequest after isLive skips draft persist and does not pop first',
    () async {
      final write = FakeBeaconWritePort(
        beacon: Beacon.empty.copyWith(id: 'B1', status: BeaconStatus.draft),
      );
      final effects = FakeUiEffectPort();
      final cubit = _cubit(write: write, effects: effects);
      addTearDown(cubit.close);
      _fillRequired(cubit);
      await cubit.makeLive(context: 'c');
      write.updatedDraftFields.clear();
      write.publishedIds.clear();
      cubit.setTitle('Need a piano moved today');

      final forward = ForwardCubit(
        beaconId: 'B1',
        debugSkipInitialLoad: true,
        debugInitialState: const ForwardState(
          beaconId: 'B1',
          candidates: [
            ForwardCandidate(
              profile: Profile(
                id: 'U1',
                displayName: 'Recipient',
                myVote: 1,
                subjectExplicitlyTrustsViewer: true,
              ),
            ),
          ],
        ),
        effects: FakeUiEffectPort(),
      );
      addTearDown(forward.close);
      forward.toggleSelection('U1');

      await cubit.sendRequest(context: 'c', forwardCubit: forward);

      expect(write.updatedDraftFields, isEmpty);
      expect(write.publishedIds, isEmpty);
      expect(write.updatedFields, isNotEmpty);
      expect(effects.emitted.whereType<NavigateBack>(), isEmpty);
    },
  );

  test('overlapping ensureDraft and makeLive create at most one row', () async {
    final write = FakeBeaconWritePort(
      beacon: Beacon.empty.copyWith(id: 'B1', status: BeaconStatus.draft),
    )..createHold = Completer<void>();
    final cubit = _cubit(write: write);
    addTearDown(cubit.close);
    _fillRequired(cubit);

    final ensure = cubit.ensureDraft(context: 'c', showMessage: false);
    await Future<void>.delayed(Duration.zero);
    final live = cubit.makeLive(context: 'c');
    write.createHold!.complete();
    await Future.wait<void>([ensure, live]);

    expect(write.createdFields, hasLength(1));
    expect(cubit.state.draftId, 'B1');
    expect(cubit.state.isLive, isTrue);
  });
}
