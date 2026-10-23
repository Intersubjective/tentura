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

  test('people and Requests are both selectable and both arrange', () {
    cubit.toggle(_request);
    expect(cubit.state.canArrange, isFalse, reason: 'one is not enough');

    cubit.toggle(_ann);
    expect(cubit.state.count, 2);
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
    const draft = ConstellationSectorDraft(
      centre: (x: 100, y: 200),
      radius: 300,
      direction: 1,
    );

    setUp(() {
      cubit
        ..toggle(_ann)
        ..toggle(_bob);
    });

    test('starts at the given draft with the default width', () {
      cubit.beginSector(draft);
      final sector = cubit.state.sector!;
      expect(sector.centre, (x: 100.0, y: 200.0));
      expect(sector.radius, 300);
      expect(sector.direction, closeTo(1, 1e-12));
      expect(sector.span, closeTo(math.pi / 2, 1e-12));
    });

    test('Requests and Posts arrange alone too', () {
      cubit
        ..clear()
        ..toggle(_request)
        ..toggle(ConstellationAnchorTarget.beacon('post'))
        ..beginSector(draft);
      expect(cubit.state.sector, isNotNull);
    });

    test('needs at least two nodes', () {
      cubit
        ..clear()
        ..toggle(_request)
        ..beginSector(draft);
      expect(cubit.state.sector, isNull);
    });

    test('refuses more nodes than one arrangement can carry', () {
      cubit
        ..clear()
        ..addAll([
          for (var i = 0; i <= kConstellationSectorMaxItems; i++)
            ConstellationAnchorTarget.person('p$i'),
        ])
        ..beginSector(draft);
      expect(cubit.state.canArrange, isFalse);
      expect(cubit.state.sector, isNull);
    });

    test('aiming turns it and clamps its width', () {
      cubit
        ..beginSector(draft)
        ..aimSector(direction: 3 * math.pi, span: 100);
      expect(cubit.state.sector!.direction.abs(), closeTo(math.pi, 1e-9));
      expect(cubit.state.sector!.span, kConstellationSectorMaxSpan);
      expect(cubit.state.sector!.isFullCircle, isTrue);

      cubit.aimSector(span: 0);
      expect(cubit.state.sector!.span, kConstellationSectorMinSpan);
    });

    test('editing replaces the draft, and does nothing without one', () {
      cubit.editSector(draft);
      expect(cubit.state.sector, isNull);

      cubit
        ..beginSector(draft)
        ..editSector(draft.copyWith(centre: (x: 5, y: 6), radius: -4));
      expect(cubit.state.sector!.centre, (x: 5.0, y: 6.0));
      expect(cubit.state.sector!.radius, 0, reason: 'never negative');
    });

    test('a changed selection drops the sector', () {
      cubit
        ..beginSector(draft)
        ..toggle(_cat);
      expect(cubit.state.sector, isNull);
    });

    test('Escape backs out of the sector first, then the selection', () {
      cubit.beginSector(draft);

      expect(cubit.escape(), isTrue);
      expect(cubit.state.sector, isNull);
      expect(cubit.state.count, 2);

      expect(cubit.escape(), isTrue);
      expect(cubit.state.isActive, isFalse);

      expect(cubit.escape(), isFalse);
    });
  });

  group('ConstellationSectorDraft.withEdgeMoved', () {
    const draft = ConstellationSectorDraft(
      centre: (x: 0, y: 0),
      radius: 100,
      direction: 0,
    );

    test('the end edge widens the sector, the start edge stays put', () {
      final moved = draft.withEdgeMoved(ConstellationSectorEdge.end, 0.5);
      expect(moved.start, closeTo(draft.start, 1e-12));
      expect(moved.end, closeTo(draft.end + 0.5, 1e-12));
      expect(moved.span, closeTo(draft.span + 0.5, 1e-12));
    });

    test('the start edge narrows it, the end edge stays put', () {
      final moved = draft.withEdgeMoved(ConstellationSectorEdge.start, 0.5);
      expect(moved.end, closeTo(draft.end, 1e-12));
      expect(moved.start, closeTo(draft.start + 0.5, 1e-12));
      expect(moved.span, closeTo(draft.span - 0.5, 1e-12));
    });

    test('the width stops at the whole circle and at the narrowest, with '
        'the other edge still in place', () {
      final full = draft.withEdgeMoved(ConstellationSectorEdge.end, 100);
      expect(full.span, kConstellationSectorMaxSpan);
      expect(full.start, closeTo(draft.start, 1e-9));
      final narrow = draft.withEdgeMoved(ConstellationSectorEdge.start, 100);
      expect(narrow.span, kConstellationSectorMinSpan);
      expect(narrow.end, closeTo(draft.end, 1e-9));
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
        ..beginSector(
          const ConstellationSectorDraft(
            centre: (x: 0, y: 0),
            radius: 100,
            direction: 0,
          ),
        );
      expect(cubit.state.dragGroupFor(_ann), isEmpty);
    });
  });
}
