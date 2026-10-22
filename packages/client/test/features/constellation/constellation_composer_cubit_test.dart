// The graph composer keeps one recipient selection (radius + manual
// overrides), creates the server draft lazily on the first content edit or
// recipient change, and mirrors the selection into the embedded
// `ForwardCubit` after every intent.

import 'dart:async';
import 'dart:ui' show Offset;

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/constellation/domain/radius_recipient_selection.dart';
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
  late FakeBeaconWritePort write;
  late FakeUiEffectPort effects;
  late ConstellationComposerCubit composer;
  late List<ForwardCubit> forwards;

  setUp(() {
    write = FakeBeaconWritePort();
    effects = FakeUiEffectPort();
    forwards = [];
    composer = ConstellationComposerCubit(
      positions: _positions,
      eligible: _positions.keys.toSet(),
      createCubitFactory: (kind) => BeaconCreateCubit(
        kind: kind,
        beaconCreateCase: fakeBeaconCreateCase(write: write),
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

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  /// First recipient/content edit: makes the server draft and the forward cubit.
  Future<ForwardCubit> touch() async {
    await composer.contentChanged();
    await settle();
    return composer.forwardCubit!;
  }

  group('ForwardCubit.setSelection', () {
    test('replaces the selected set and keeps notes of ids that stay', () {
      final forward = ForwardCubit(
        beaconId: 'b',
        embedded: true,
        effects: effects,
        debugSkipInitialLoad: true,
        debugInitialState: const ForwardState(
          beaconId: 'b',
          selectedIds: {'Ua', 'Ub'},
          perRecipientNotes: {'Ua': 'one', 'Ub': 'two'},
        ),
      );
      addTearDown(forward.close);

      forward.setSelection({'Ub', 'Uc'});

      expect(forward.state.selectedIds, {'Ub', 'Uc'});
      expect(forward.state.perRecipientNotes, {'Ub': 'two'});
    });
  });

  group('composer start', () {
    test(
      'sets the start radius, selects the three nearest and pushes them',
      () async {
        composer.start(BeaconKind.post, Offset.zero);
        final forward = await touch();

        expect(composer.selection.radius, closeTo(33, 1e-9));
        expect(composer.selection.selected, {'Ua', 'Ub', 'Uc'});
        expect(forward.state.selectedIds, {'Ua', 'Ub', 'Uc'});
      },
    );
  });

  group('people laid out only after the composer opened', () {
    // Forward candidates absent from the normal field get their first graph
    // positions only once the composing scene places them (tentura-rcp1).
    late ConstellationComposerCubit unplaced;

    setUp(() {
      unplaced = ConstellationComposerCubit(
        positions: const {},
        eligible: _positions.keys.toSet(),
        createCubitFactory: (kind) => BeaconCreateCubit(
          kind: kind,
          beaconCreateCase: fakeBeaconCreateCase(write: write),
          effects: effects,
        ),
        forwardCubitFactory: (beaconId) => ForwardCubit(
          beaconId: beaconId,
          embedded: true,
          effects: effects,
          debugSkipInitialLoad: true,
        ),
      );
    });

    tearDown(() => unplaced.close());

    test(
      'the first people the scene places size the circle to the three '
      'nearest; their seed positions before that do not',
      () {
        unplaced.start(BeaconKind.post, Offset.zero);
        expect(unplaced.selection.radius, kComposerMinRadius);
        expect(unplaced.selection.selected, isEmpty);

        // The graph reports the new people at a seed point first ...
        unplaced.updatePersonPositions({
          for (final id in _positions.keys) id: const Offset(5, 0),
        });
        expect(unplaced.selection.radius, kComposerMinRadius);

        // ... then the composing scene places them at their slots.
        unplaced.peoplePlaced({
          for (final e in _positions.entries) e.key: e.value * 10,
        });

        expect(unplaced.selection.radius, closeTo(330, 1e-9));
        expect(unplaced.selection.selected, {'Ua', 'Ub', 'Uc'});
      },
    );

    test('later placements and a set radius keep the circle', () {
      unplaced
        ..start(BeaconKind.post, Offset.zero)
        ..peoplePlaced({
          for (final e in _positions.entries) e.key: e.value * 10,
        })
        ..setRadius(150)
        ..updatePersonPositions({'Ub': const Offset(140, 0)})
        ..peoplePlaced({'Uc': const Offset(145, 0)});

      expect(unplaced.selection.radius, 150);
      expect(
        unplaced.selection.selected,
        {'Ua', 'Ub'},
        reason: 'once sized, a placement neither resizes nor moves anyone',
      );
    });

    test('a viewer radius set before anyone is placed is kept', () {
      final slots = {for (final e in _positions.entries) e.key: e.value * 10};
      unplaced
        ..start(BeaconKind.post, Offset.zero)
        ..setRadius(150)
        ..updatePersonPositions(slots)
        ..peoplePlaced(slots);

      expect(unplaced.selection.radius, 150);
      expect(unplaced.selection.selected, {'Ua'});
    });
  });

  group('composer start before any edit', () {
    test(
      'selects the three nearest at the start radius without a draft',
      () async {
        composer.start(BeaconKind.post, Offset.zero);
        await settle();

        expect(composer.selection.radius, closeTo(33, 1e-9));
        expect(composer.selection.selected, {'Ua', 'Ub', 'Uc'});
        expect(composer.forwardCubit, isNull);
        expect(write.createdFields, isEmpty);
      },
    );
  });

  group('composer intents', () {
    test(
      'toggling a selected person removes it in selection and forward',
      () async {
        composer.start(BeaconKind.post, Offset.zero);
        final forward = await touch();

        await composer.toggle('Ub');
        await settle();

        expect(composer.selection.selected, {'Ua', 'Uc'});
        expect(forward.state.selectedIds, {'Ua', 'Uc'});
      },
    );

    test(
      'growing the radius selects more but keeps the removed one removed',
      () async {
        composer.start(BeaconKind.post, Offset.zero);
        final forward = await touch();
        await composer.toggle('Ub');

        composer.setRadius(150);
        await settle();

        expect(composer.selection.selected, {'Ua', 'Uc', 'Ud'});
        expect(forward.state.selectedIds, {'Ua', 'Uc', 'Ud'});
      },
    );

    test('a list-picker toggle behaves like a graph toggle', () async {
      composer.start(BeaconKind.post, Offset.zero);
      final forward = await touch();

      await composer.toggle('Ue');
      await settle();
      expect(forward.state.selectedIds, {'Ua', 'Ub', 'Uc', 'Ue'});

      await composer.toggle('Ue');
      await composer.toggle('Ua');
      await settle();
      expect(forward.state.selectedIds, {'Ub', 'Uc'});
      expect(composer.selection.manualRemoved, {'Ua'});
    });

    test('moving the draft re-evaluates the radius membership', () async {
      composer.start(BeaconKind.post, Offset.zero);
      final forward = await touch();

      composer.moveDraft(const Offset(200, 0));
      await settle();

      expect(composer.selection.selected, {'Ue'});
      expect(forward.state.selectedIds, {'Ue'});
    });
  });

  group('composer draft lifecycle', () {
    test('cancelling an untouched composer makes no server call', () async {
      composer.start(BeaconKind.post, Offset.zero);

      await composer.cancel();
      await settle();

      expect(write.createdFields, isEmpty);
      expect(write.deletedIds, isEmpty);
    });

    test('the first content edit creates exactly one Post draft', () async {
      composer.start(BeaconKind.post, Offset.zero);

      await composer.contentChanged();
      await composer.contentChanged();

      expect(write.createdFields, hasLength(1));
      expect(write.createdFields.single.kind, BeaconKind.post);
      expect(composer.forwardCubit?.state.beaconId, 'server-beacon');
      expect(forwards, hasLength(1), reason: 'one forward cubit per draft');
      expect(identical(composer.forwardCubit, forwards.single), isTrue);
      expect(composer.forwardCubit!.state.selectedIds, {'Ua', 'Ub', 'Uc'});
      expect(composer.selection.selected, {'Ua', 'Ub', 'Uc'});
      expect(write.deletedIds, isEmpty);
    });

    test(
      'a recipient change alone creates no draft (hand-off carries selection)',
      () async {
        composer.start(BeaconKind.request, Offset.zero);
        await composer.toggle('Ub');
        await settle();
        await composer.toggle('Ud');
        await settle();

        expect(write.createdFields, isEmpty);
      },
    );

    test(
      'cancelling after only a recipient change deletes nothing',
      () async {
        composer.start(BeaconKind.request, Offset.zero);
        await composer.toggle('Ub');
        await settle();

        await composer.cancel();
        await settle();

        expect(write.createdFields, isEmpty);
        expect(write.deletedIds, isEmpty);
      },
    );

    test('cancelling a touched composer deletes the draft once', () async {
      composer.start(BeaconKind.post, Offset.zero);
      await touch();

      await composer.cancel();
      await settle();

      expect(write.deletedIds, ['server-beacon']);
    });

    test(
      'a draft created after cancel is deleted and changes no state',
      () async {
        final hold = write.createHold = Completer<void>();
        composer.start(BeaconKind.post, Offset.zero);
        final pending = composer.contentChanged();
        await settle();
        final stateBefore = composer.state;
        final selectedBefore = composer.selection.selected;
        final radiusBefore = composer.selection.radius;
        final emissions = <Object?>[];
        final sub = composer.stream.listen(emissions.add);
        addTearDown(sub.cancel);

        final cancelling = composer.cancel();
        hold.complete();
        await pending;
        await cancelling;
        await settle();

        expect(write.deletedIds, ['server-beacon']);
        expect(composer.forwardCubit, isNull);
        expect(emissions, isEmpty);
        expect(composer.state, stateBefore);
        expect(composer.selection.selected, selectedBefore);
        expect(composer.selection.radius, radiusBefore);
        expect(forwards, isEmpty);
      },
    );
  });
  group('People dropped on the circle', () {
    test('a dropped person inside the circle becomes a recipient', () {
      composer
        ..start(BeaconKind.post, Offset.zero)
        ..setRadius(25);
      expect(composer.selection.selected, contains('Ua'));
      unawaited(composer.toggle('Ua'));
      expect(composer.selection.selected, isNot(contains('Ua')));

      composer.personDropped('Ua');

      expect(composer.selection.selected, contains('Ua'));
    });

    test('a person dropped outside the circle is not added', () {
      composer
        ..start(BeaconKind.post, Offset.zero)
        ..setRadius(25)
        ..personDropped('Ue');

      expect(composer.selection.selected, isNot(contains('Ue')));
    });

    test('a sent session reports the recipients inside the circle', () async {
      composer
        ..start(BeaconKind.post, Offset.zero)
        ..setRadius(25)
        ..toggleManualSelection()
        ..toggleMapRecipient('Ue');
      expect(composer.selection.selected, containsAll(['Ua', 'Ub', 'Ue']));

      await composer.finish();

      expect(composer.sentInCircleIds, {'Ua', 'Ub'});
    });

    test('a cancelled session reports nobody', () async {
      composer
        ..start(BeaconKind.post, Offset.zero)
        ..setRadius(25);

      await composer.cancel();
      await composer.finish();

      expect(composer.sentInCircleIds, isEmpty);
    });
  });
}
