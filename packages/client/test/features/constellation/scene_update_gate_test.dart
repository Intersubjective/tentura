import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/constellation/ui/scene/scene_update_gate.dart';

// The gate's contract, as pinned here (the architecture names the gate but not
// its signature):
//  * `SceneUpdateGate(onApply:)` hands every input that is allowed through to
//    `onApply(source, input)`. That callback is what changes the scene, so
//    "applied" below means "reached onApply".
//  * `submit(source, input)` applies at once while the gate is open and holds
//    the input while it is frozen.
//  * "Coalesced" is read as the architecture words it: while frozen, the
//    latest input of each source wins (a later one replaces an earlier one
//    from the same source).
//  * `release()` unfreezes and applies what was held, one input per source.
//  * Sources are the committed-scene inputs the architecture lists: the store,
//    the outbox and layout transitions.

typedef _Applied = ({SceneInputSource source, Object input});

void main() {
  late List<_Applied> applied;
  late SceneUpdateGate gate;

  setUp(() {
    applied = [];
    gate = SceneUpdateGate(
      onApply: (source, input) => applied.add((source: source, input: input)),
    );
  });

  group('SceneUpdateGate', () {
    test('lets inputs through at once while it is open', () {
      expect(gate.isFrozen, isFalse);

      gate
        ..submit(SceneInputSource.store, 'snapshot-1')
        ..submit(SceneInputSource.outbox, 'intent-1')
        ..submit(SceneInputSource.transition, 'frame-1');

      expect(applied, [
        (source: SceneInputSource.store, input: 'snapshot-1'),
        (source: SceneInputSource.outbox, input: 'intent-1'),
        (source: SceneInputSource.transition, input: 'frame-1'),
      ]);
    });

    test('applies nothing that arrives while frozen until it is released', () {
      gate.freeze();

      gate
        ..submit(SceneInputSource.store, 'snapshot-1')
        ..submit(SceneInputSource.outbox, 'intent-1')
        ..submit(SceneInputSource.transition, 'frame-1');

      expect(gate.isFrozen, isTrue);
      expect(applied, isEmpty);
    });

    test('applies what it held, once per source, on release', () {
      gate
        ..freeze()
        ..submit(SceneInputSource.store, 'snapshot-1')
        ..submit(SceneInputSource.outbox, 'intent-1')
        ..submit(SceneInputSource.transition, 'frame-1');

      gate.release();

      expect(gate.isFrozen, isFalse);
      expect(applied, hasLength(3));
      expect(
        applied,
        unorderedEquals([
          (source: SceneInputSource.store, input: 'snapshot-1'),
          (source: SceneInputSource.outbox, input: 'intent-1'),
          (source: SceneInputSource.transition, input: 'frame-1'),
        ]),
      );
    });

    test('coalesces inputs from one source down to the latest', () {
      gate
        ..freeze()
        ..submit(SceneInputSource.store, 'snapshot-1')
        ..submit(SceneInputSource.store, 'snapshot-2')
        ..submit(SceneInputSource.store, 'snapshot-3')
        ..submit(SceneInputSource.outbox, 'intent-1')
        ..submit(SceneInputSource.outbox, 'intent-2')
        ..submit(SceneInputSource.transition, 'frame-1')
        ..submit(SceneInputSource.transition, 'frame-2');
      expect(applied, isEmpty);

      gate.release();

      expect(
        applied,
        unorderedEquals([
          (source: SceneInputSource.store, input: 'snapshot-3'),
          (source: SceneInputSource.outbox, input: 'intent-2'),
          (source: SceneInputSource.transition, input: 'frame-2'),
        ]),
      );
    });

    test('a second release applies nothing more', () {
      gate
        ..freeze()
        ..submit(SceneInputSource.store, 'snapshot-1')
        ..release();
      expect(applied, hasLength(1));

      gate
        ..release()
        ..release();

      expect(applied, hasLength(1));
      expect(gate.isFrozen, isFalse);
    });

    test('freezing twice still needs just one release', () {
      gate
        ..freeze()
        ..freeze()
        ..submit(SceneInputSource.store, 'snapshot-1')
        ..release();

      expect(gate.isFrozen, isFalse);
      expect(applied, [
        (source: SceneInputSource.store, input: 'snapshot-1'),
      ]);
    });

    test('releasing an open gate applies nothing', () {
      gate.release();

      expect(applied, isEmpty);
      expect(gate.isFrozen, isFalse);
    });

    test('lets inputs through again once released', () {
      gate
        ..freeze()
        ..release()
        ..submit(SceneInputSource.outbox, 'intent-1');

      expect(applied, [
        (source: SceneInputSource.outbox, input: 'intent-1'),
      ]);
    });

    test('does not carry held inputs of one freeze into the next', () {
      gate
        ..freeze()
        ..submit(SceneInputSource.store, 'snapshot-1')
        ..release();
      applied.clear();

      gate
        ..freeze()
        ..submit(SceneInputSource.outbox, 'intent-1')
        ..release();

      expect(applied, [
        (source: SceneInputSource.outbox, input: 'intent-1'),
      ]);
    });
  });
}
