// Tag picks in the graph composer: a tag adds its eligible people to the
// recipients, a second pick takes back only the people it added alone, and the
// embedded ForwardCubit mirrors the result. No tag data goes to the draft.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_composer_cubit.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import '../beacon_create/fake_beacon_ports.dart';

const _positions = <String, Offset>{
  'Ua': Offset(10, 0),
  'Ub': Offset(20, 0),
  'Uc': Offset(30, 0),
  'Ud': Offset(100, 0),
  'Ue': Offset(200, 0),
};

void main() {
  late FakeUiEffectPort effects;
  late ConstellationComposerCubit composer;
  late List<ForwardCubit> forwards;

  setUp(() {
    effects = FakeUiEffectPort();
    forwards = [];
    composer = ConstellationComposerCubit(
      positions: _positions,
      // 'Uz' is eligible but has no position yet.
      eligible: {..._positions.keys, 'Uz'},
      createCubitFactory: (kind) => BeaconCreateCubit(
        kind: kind,
        beaconCreateCase: fakeBeaconCreateCase(write: FakeBeaconWritePort()),
        effects: effects,
      ),
      forwardCubitFactory: (beaconId) {
        final cubit = ForwardCubit(
          beaconId: beaconId,
          embedded: true,
          effects: effects,
          debugSkipInitialLoad: true,
        );
        forwards.add(cubit);
        return cubit;
      },
    );
  });

  tearDown(() async {
    await composer.close();
    for (final f in forwards) {
      await f.close();
    }
  });

  // Start radius 33 selects Ua, Ub, Uc.
  void startPost() => composer.start(BeaconKind.post, Offset.zero);

  Future<ForwardCubit> touch() async {
    await composer.contentChanged();
    await Future<void>.delayed(Duration.zero);
    return composer.forwardCubit!;
  }

  test('picking a tag adds its people outside the circle', () {
    startPost();

    composer.toggleTag('t1', ['Ua', 'Ud', 'Uz']);

    expect(composer.selection.selected, {'Ua', 'Ub', 'Uc', 'Ud', 'Uz'});
  });

  test('picking the tag again keeps people inside the circle', () {
    startPost();

    composer
      ..toggleTag('t1', ['Ua', 'Ud'])
      ..toggleTag('t1', ['Ua', 'Ud']);

    expect(composer.selection.selected, {'Ua', 'Ub', 'Uc'});
  });

  test('picking the tag again keeps a person added individually', () {
    startPost();
    unawaited(composer.toggle('Ue'));

    composer
      ..toggleTag('t1', ['Ud', 'Ue'])
      ..toggleTag('t1', ['Ud', 'Ue']);

    expect(composer.selection.selected, {'Ua', 'Ub', 'Uc', 'Ue'});
  });

  test('tag people stay selected while the circle is resized', () {
    startPost();
    composer
      ..toggleTag('t1', ['Ud'])
      ..setRadius(5);

    expect(composer.selection.selected, {'Ud'});
  });

  test('the forward cubit mirrors the tag selection and its removal', () async {
    startPost();
    final forward = await touch();

    composer.toggleTag('t1', ['Ud', 'Ue']);
    expect(forward.state.selectedIds, {'Ua', 'Ub', 'Uc', 'Ud', 'Ue'});

    composer.toggleTag('t1', ['Ud', 'Ue']);
    expect(forward.state.selectedIds, {'Ua', 'Ub', 'Uc'});
  });

  test('the full-form hand-off carries the people a tag picked', () {
    startPost();
    composer.toggleTag('t1', ['Ud']);

    final handoff = composer.fullFormHandoff()!;

    expect(handoff.recipientIds, {'Ua', 'Ub', 'Uc', 'Ud'});
  });
}
