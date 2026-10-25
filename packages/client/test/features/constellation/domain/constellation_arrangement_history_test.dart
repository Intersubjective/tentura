import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/constellation/domain/port/constellation_anchor_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_arrangement_history.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

/// The screen-session undo / redo stack for Field arrangement: anchor batches,
/// local layout moves and server snapshot restores share one bounded stack.

ConstellationAnchorPosition _at(double x, double y) =>
    ConstellationAnchorPosition(
      xUnits: x,
      yUnits: y,
      coordinateSpaceVersion: 1,
    );

ConstellationAnchorTarget _person(int i) =>
    ConstellationAnchorTarget.person('U$i');

final class _Executor {
  final log = <String>[];
  final applied = <List<ConstellationAnchorApplyOp>>[];
  final restored = <String>[];
  final localLayouts = <Map<String, ConstellationAnchorPosition>>[];
  final savedReasons = <String>[];
  bool failApply = false;

  /// Zero-based index of the one apply call that fails; others succeed.
  int? failApplyCall;
  var _ids = 0;

  Future<bool> applyOps(List<ConstellationAnchorApplyOp> ops) async {
    log.add('apply');
    final call = applied.length;
    applied.add(ops);
    return !failApply && call != failApplyCall;
  }

  Future<String?> restoreSnapshot(String id) async {
    log.add('restore:$id');
    restored.add(id);
    return 'written-before-$id';
  }

  Future<void> applyLocalLayout(
    Map<String, ConstellationAnchorPosition> layout,
  ) async {
    log.add('local');
    localLayouts.add(layout);
  }

  Future<void> flushPlacementOutbox() async => log.add('flush');

  Future<String> saveSnapshot(String reason) async {
    log.add('save:$reason');
    savedReasons.add(reason);
    return 'S${savedReasons.length}';
  }

  String newOpId() => 'op${_ids++}';
}

ConstellationArrangementHistory _history(_Executor e) =>
    ConstellationArrangementHistory(
      applyOps: e.applyOps,
      restoreSnapshot: e.restoreSnapshot,
      applyLocalLayout: e.applyLocalLayout,
      flushPlacementOutbox: e.flushPlacementOutbox,
      saveSnapshot: e.saveSnapshot,
      newOpId: e.newOpId,
    );

AnchorBatchEntry _entry(int i) => AnchorBatchEntry.placement(
  changes: {_person(i): (before: _at(0, 0), after: _at(1, 1))},
  newOpId: () => 'e$i',
);

void main() {
  late _Executor exec;
  late ConstellationArrangementHistory history;

  setUp(() {
    exec = _Executor();
    history = _history(exec);
  });

  group('drag history', () {
    test(
      'undo writes the previous anchor back and redo re-applies the drag',
      () async {
        history.record(
          AnchorBatchEntry.placement(
            changes: {_person(1): (before: _at(1, 2), after: _at(5, 6))},
            newOpId: exec.newOpId,
          ),
        );

        expect(await history.undo(), isTrue);
        final undo = exec.applied.single.single;
        expect(undo.kind, ConstellationAnchorOpKind.upsert);
        expect(undo.target, _person(1));
        expect(undo.position, _at(1, 2));

        expect(await history.redo(), isTrue);
        final redo = exec.applied.last.single;
        expect(redo.kind, ConstellationAnchorOpKind.upsert);
        expect(redo.position, _at(5, 6));
      },
    );

    test('undoing the first placement of a person unpins them', () async {
      history.record(
        AnchorBatchEntry.placement(
          changes: {_person(2): (before: null, after: _at(5, 6))},
          newOpId: exec.newOpId,
        ),
      );

      await history.undo();

      final undo = exec.applied.single.single;
      expect(undo.kind, ConstellationAnchorOpKind.delete);
      expect(undo.target, _person(2));

      await history.redo();
      expect(exec.applied.last.single.kind, ConstellationAnchorOpKind.upsert);
      expect(exec.applied.last.single.position, _at(5, 6));
    });
  });

  group('bulk arrangement', () {
    test('a thirty-person sector arrangement is a single undo step', () async {
      history.record(
        AnchorBatchEntry.placement(
          changes: {
            for (var i = 0; i < 30; i++)
              _person(i): (before: _at(0, 0), after: _at(i + 1, 1)),
          },
          newOpId: exec.newOpId,
        ),
      );

      expect(history.length, 1);
      await history.undo();

      expect(exec.applied, hasLength(1));
      expect(exec.applied.single, hasLength(30));
      expect(history.canUndo, isFalse);
    });

    test(
      'an entry above the batch cap is still one step, sent in batches',
      () async {
        history.record(
          AnchorBatchEntry.placement(
            changes: {
              for (var i = 0; i < 450; i++)
                _person(i): (before: _at(0, 0), after: _at(1, 1)),
            },
            newOpId: exec.newOpId,
          ),
        );

        expect(history.length, 1);
        await history.undo();

        expect(exec.applied.map((b) => b.length), [400, 50]);
        expect(history.canUndo, isFalse);
      },
    );

    test(
      'a local layout entry undoes to its earlier hints and redoes',
      () async {
        history.record(
          LocalLayoutEntry(
            before: {'U1': _at(1, 1)},
            after: {'U1': _at(9, 9)},
          ),
        );

        await history.undo();
        expect(exec.localLayouts.single, {'U1': _at(1, 1)});
        expect(exec.applied, isEmpty);

        await history.redo();
        expect(exec.localLayouts.last, {'U1': _at(9, 9)});
      },
    );
  });

  group('snapshot restore entries', () {
    test('undoing a reset restores the snapshot written before it', () async {
      history.record(const SnapshotRestoreEntry(snapshotId: 'S-reset'));

      expect(await history.undo(), isTrue);
      expect(exec.restored, ['S-reset']);
      expect(exec.applied, isEmpty);
    });

    test(
      'redo restores the snapshot the undo wrote before restoring',
      () async {
        history.record(const SnapshotRestoreEntry(snapshotId: 'S-reset'));
        await history.undo();

        expect(await history.redo(), isTrue);
        expect(exec.restored, ['S-reset', 'written-before-S-reset']);
      },
    );
  });

  group('flushing before snapshots', () {
    test(
      'the placement outbox is flushed before a snapshot is saved',
      () async {
        final id = await history.saveSnapshotBeforeBulkAction('rearrange');

        expect(exec.log, ['flush', 'save:rearrange']);
        expect(id, 'S1');
      },
    );
  });

  group('stack limits', () {
    test('the 51st entry drops the oldest', () async {
      for (var i = 0; i < 51; i++) {
        history.record(_entry(i));
      }
      expect(history.length, 50);

      var undone = 0;
      while (await history.undo()) {
        undone++;
      }

      expect(undone, 50);
      // Entry 0 fell off the stack; entry 1 was the last one undone.
      expect(exec.applied.last.single.target, _person(1));
      expect(
        exec.applied.any((b) => b.single.target == _person(0)),
        isFalse,
      );
    });

    test('a new action clears the redo stack', () async {
      history
        ..record(_entry(1))
        ..record(_entry(2));
      await history.undo();
      expect(history.canRedo, isTrue);

      history.record(_entry(3));

      expect(history.canRedo, isFalse);
      expect(await history.redo(), isFalse);
    });
  });

  group('failed batches', () {
    test('an entry whose batch failed is not undoable', () async {
      final handle = history.record(_entry(1));

      history.markFailed(handle);

      expect(history.canUndo, isFalse);
      expect(await history.undo(), isFalse);
      expect(exec.applied, isEmpty);
    });

    test(
      'a failure of one entry leaves the earlier entries undoable',
      () async {
        history.record(_entry(1));
        final failed = history.record(_entry(2));
        history.markFailed(failed);

        expect(history.canUndo, isTrue);
        expect(await history.undo(), isTrue);
        expect(exec.applied.single.single.target, _person(1));
      },
    );

    test(
      'an undo whose batch is rejected fails and the entry is not retried',
      () async {
        history.record(_entry(1));
        history.record(_entry(2));
        exec.failApply = true;

        expect(await history.undo(), isFalse);
        expect(exec.applied, hasLength(1));
        exec.failApply = false;

        // The failed entry is skipped; the earlier one is still undoable.
        expect(history.canUndo, isTrue);
        expect(await history.undo(), isTrue);
        expect(exec.applied.last.single.target, _person(1));
        expect(history.canUndo, isFalse);
      },
    );

    test(
      'an entry whose only undo failed leaves nothing to undo or redo',
      () async {
        history.record(_entry(1));
        exec.failApply = true;
        await history.undo();
        exec.failApply = false;

        expect(history.canUndo, isFalse);
        expect(history.canRedo, isFalse);
        expect(await history.undo(), isFalse);
        expect(exec.applied, hasLength(1));
      },
    );

    test(
      'a redo whose batch is rejected marks the entry non-undoable',
      () async {
        history.record(_entry(1));
        await history.undo();
        exec.failApply = true;

        expect(await history.redo(), isFalse);
        exec.failApply = false;

        expect(history.canUndo, isFalse);
        expect(await history.undo(), isFalse);
        expect(exec.applied, hasLength(2));
      },
    );

    test('a later batch failing during a multi-batch undo makes the entry '
        'non-undoable', () async {
      history.record(_entry(0));
      history.record(
        AnchorBatchEntry.placement(
          changes: {
            for (var i = 100; i < 550; i++)
              _person(i): (before: _at(0, 0), after: _at(1, 1)),
          },
          newOpId: exec.newOpId,
        ),
      );
      exec.failApplyCall = 1; // the 50-op second batch

      expect(await history.undo(), isFalse);
      expect(exec.applied.map((b) => b.length), [400, 50]);

      // The half-undone entry is never retried; the earlier entry is next.
      expect(await history.undo(), isTrue);
      expect(exec.applied.last.single.target, _person(0));
      expect(exec.applied, hasLength(3));
    });
  });
}
