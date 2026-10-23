import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/constellation/domain/constellation_sector_arrangement.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_selection_cubit.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

// Field multi-selection (#642) and the sector being aimed (#644).

final _ann = ConstellationAnchorTarget.person('ann');
final _bob = ConstellationAnchorTarget.person('bob');
final _cat = ConstellationAnchorTarget.person('cat');
final _request = ConstellationAnchorTarget.beacon('request');

void main() {
  late ConstellationSelectionCubit cubit;

  setUp(() => cubit = ConstellationSelectionCubit());
  tearDown(() => cubit.close());

  test('starts empty, tool off, no bar', () {
    expect(cubit.state.isEmpty, isTrue);
    expect(cubit.state.selecting, isFalse);
    expect(cubit.state.isActive, isFalse);
  });

  test('a tap toggles a node in and out', () {
    cubit.toggle(_ann);
    expect(cubit.state.targets, {_ann});
    expect(cubit.state.isActive, isTrue);

    cubit.toggle(_ann);
    expect(cubit.state.isEmpty, isTrue);
  });

  test('people and Requests are both selectable; only people arrange', () {
    cubit
      ..toggle(_ann)
      ..toggle(_request);

    expect(cubit.state.count, 2);
    expect(cubit.state.personIds, ['ann']);
    expect(cubit.state.canArrange, isFalse);

    cubit.toggle(_bob);
    expect(cubit.state.canArrange, isTrue);
  });

  test('turning the tool on shows the bar even before anything is '
      'selected', () {
    cubit.setSelecting(true);
    expect(cubit.state.isActive, isTrue);
    expect(cubit.state.isEmpty, isTrue);
  });

  test('«Done» turns the tool off and keeps the selection', () {
    cubit
      ..setSelecting(true)
      ..toggle(_ann)
      ..setSelecting(false);

    expect(cubit.state.selecting, isFalse);
    expect(cubit.state.targets, {_ann});
  });

  test('«Clear selection» empties it and turns the tool off', () {
    cubit
      ..setSelecting(true)
      ..toggle(_ann)
      ..toggle(_bob)
      ..clear();

    expect(cubit.state, ConstellationMultiSelection.empty);
    expect(cubit.state.isActive, isFalse);
  });

  group('rubber-band box', () {
    setUp(() {
      cubit
        ..toggle(_ann)
        ..toggle(_bob);
    });

    test('a plain box replaces the selection', () {
      cubit.applyBox([_cat, _request], ConstellationBoxMerge.replace);
      expect(cubit.state.targets, {_cat, _request});
    });

    test('a Shift (or touch) box adds to it', () {
      cubit.applyBox([_bob, _cat], ConstellationBoxMerge.add);
      expect(cubit.state.targets, {_ann, _bob, _cat});
    });

    test('a Ctrl/Cmd box flips each node inside it', () {
      cubit.applyBox([_bob, _cat], ConstellationBoxMerge.toggle);
      expect(cubit.state.targets, {_ann, _cat});
    });

    test('a box keeps the tool as it was', () {
      cubit
        ..setSelecting(true)
        ..applyBox([_cat], ConstellationBoxMerge.replace);
      expect(cubit.state.selecting, isTrue);
    });
  });

  group('sector', () {
    setUp(() {
      cubit
        ..toggle(_ann)
        ..toggle(_bob);
    });

    test('starts at the given direction with the default width', () {
      cubit.beginSector(direction: 1);
      expect(cubit.state.sector!.direction, closeTo(1, 1e-12));
      expect(cubit.state.sector!.span, closeTo(math.pi / 2, 1e-12));
    });

    test('needs at least two people', () {
      cubit
        ..clear()
        ..toggle(_ann)
        ..toggle(_request)
        ..beginSector(direction: 0);
      expect(cubit.state.sector, isNull);
    });

    test('refuses more people than one batch can carry', () {
      cubit
        ..clear()
        ..addAll([
          for (var i = 0; i <= kConstellationSectorMaxPeople; i++)
            ConstellationAnchorTarget.person('p$i'),
        ])
        ..beginSector(direction: 0);
      expect(cubit.state.canArrange, isFalse);
      expect(cubit.state.sector, isNull);
    });

    test('aiming turns it and clamps its width', () {
      cubit
        ..beginSector(direction: 0)
        ..aimSector(direction: 3 * math.pi, span: 100);
      expect(cubit.state.sector!.direction.abs(), closeTo(math.pi, 1e-9));
      expect(cubit.state.sector!.span, kConstellationSectorMaxSpan);

      cubit.aimSector(span: 0);
      expect(cubit.state.sector!.span, kConstellationSectorMinSpan);
    });

    test('a changed selection drops the sector', () {
      cubit
        ..beginSector(direction: 0)
        ..toggle(_cat);
      expect(cubit.state.sector, isNull);
    });

    test('Escape backs out of the sector first, then the selection', () {
      cubit.beginSector(direction: 0);

      expect(cubit.escape(), isTrue);
      expect(cubit.state.sector, isNull);
      expect(cubit.state.count, 2);

      expect(cubit.escape(), isTrue);
      expect(cubit.state.isActive, isFalse);

      expect(cubit.escape(), isFalse);
    });
  });

  group('dragGroupFor (group drag)', () {
    test('a selected node takes the rest of the selection along', () {
      cubit
        ..toggle(_ann)
        ..toggle(_bob)
        ..toggle(_request);
      expect(cubit.state.dragGroupFor(_bob), {_ann, _request});
    });

    test('a node outside the selection moves alone', () {
      cubit
        ..toggle(_ann)
        ..toggle(_bob);
      expect(cubit.state.dragGroupFor(_cat), isEmpty);
    });

    test('a lone selected node and a sector being aimed take nothing', () {
      cubit.toggle(_ann);
      expect(cubit.state.dragGroupFor(_ann), isEmpty);
      cubit
        ..toggle(_bob)
        ..beginSector(direction: 0);
      expect(cubit.state.dragGroupFor(_ann), isEmpty);
    });
  });
}
