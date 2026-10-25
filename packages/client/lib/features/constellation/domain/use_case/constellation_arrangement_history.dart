import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../port/constellation_anchor_repository_port.dart';

/// Most entries the screen-session history keeps; the oldest falls off.
const int kConstellationArrangementHistoryLimit = 50;

/// One undoable arrangement action.
sealed class ArrangementEntry {
  const ArrangementEntry();
}

/// Anchor placements / unpins sent as one logical step (possibly several
/// server batches).
final class AnchorBatchEntry extends ArrangementEntry {
  /// [changes] maps each target to its anchor before and after the action;
  /// `null` means unpinned.
  AnchorBatchEntry.placement({
    required this.changes,
    required String Function() newOpId,
  }) : _newOpId = newOpId;

  final Map<
    ConstellationAnchorTarget,
    ({
      ConstellationAnchorPosition? before,
      ConstellationAnchorPosition? after,
    })
  >
  changes;
  final String Function() _newOpId;

  List<ConstellationAnchorApplyOp> _ops({required bool undo}) => [
    for (final entry in changes.entries)
      switch (undo ? entry.value.before : entry.value.after) {
        final ConstellationAnchorPosition position =>
          ConstellationAnchorApplyOp(
            clientOpId: _newOpId(),
            kind: ConstellationAnchorOpKind.upsert,
            target: entry.key,
            position: position,
          ),
        null => ConstellationAnchorApplyOp(
          clientOpId: _newOpId(),
          kind: ConstellationAnchorOpKind.delete,
          target: entry.key,
        ),
      },
  ];
}

/// A local-only layout move.
final class LocalLayoutEntry extends ArrangementEntry {
  LocalLayoutEntry({required this.before, required this.after});

  final Map<String, ConstellationAnchorPosition> before;
  final Map<String, ConstellationAnchorPosition> after;
}

/// A server snapshot restore; [snapshotId] is the snapshot that undoes it.
final class SnapshotRestoreEntry extends ArrangementEntry {
  const SnapshotRestoreEntry({required this.snapshotId});

  final String snapshotId;
}

/// Bounded undo / redo stack of Field arrangement for one screen session.
final class ConstellationArrangementHistory {
  ConstellationArrangementHistory({
    required this.applyOps,
    required this.restoreSnapshot,
    required this.applyLocalLayout,
    required this.flushPlacementOutbox,
    required this.saveSnapshot,
    required this.newOpId,
  });

  /// Sends one batch; false when the server rejected it.
  final Future<bool> Function(List<ConstellationAnchorApplyOp> ops) applyOps;

  /// Restores a snapshot; returns the id of the snapshot written before it.
  final Future<String?> Function(String snapshotId) restoreSnapshot;
  final Future<void> Function(Map<String, ConstellationAnchorPosition> layout)
  applyLocalLayout;
  final Future<void> Function() flushPlacementOutbox;
  final Future<String> Function(String reason) saveSnapshot;
  final String Function() newOpId;

  static const _batchCap = 400;

  final _undo = <ArrangementEntry>[];
  final _redo = <ArrangementEntry>[];

  int get length => _undo.length;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  /// Pushes [entry] and clears redo; the result is the handle for [markFailed].
  ArrangementEntry record(ArrangementEntry entry) {
    _redo.clear();
    _undo.add(entry);
    if (_undo.length > kConstellationArrangementHistoryLimit) {
      _undo.removeAt(0);
    }
    return entry;
  }

  /// The entry's write failed: it can be neither undone nor redone.
  void markFailed(ArrangementEntry handle) {
    _undo.remove(handle);
    _redo.remove(handle);
  }

  /// Flushes the placement outbox so the snapshot sees every pending write.
  Future<String> saveSnapshotBeforeBulkAction(String reason) async {
    await flushPlacementOutbox();
    return saveSnapshot(reason);
  }

  Future<bool> undo() async {
    if (_undo.isEmpty) return false;
    final entry = _undo.removeLast();
    final inverse = await _run(entry, undo: true);
    if (inverse == null) return false;
    _redo.add(inverse);
    return true;
  }

  Future<bool> redo() async {
    if (_redo.isEmpty) return false;
    final entry = _redo.removeLast();
    final inverse = await _run(entry, undo: false);
    if (inverse == null) return false;
    _undo.add(inverse);
    return true;
  }

  /// The entry to keep for the opposite direction, or null on failure.
  Future<ArrangementEntry?> _run(
    ArrangementEntry entry, {
    required bool undo,
  }) async {
    switch (entry) {
      case final AnchorBatchEntry e:
        final ops = e._ops(undo: undo);
        for (var i = 0; i < ops.length; i += _batchCap) {
          final end = i + _batchCap < ops.length ? i + _batchCap : ops.length;
          if (!await applyOps(ops.sublist(i, end))) return null;
        }
        return e;
      case final LocalLayoutEntry e:
        await applyLocalLayout(undo ? e.before : e.after);
        return e;
      case final SnapshotRestoreEntry e:
        final written = await restoreSnapshot(e.snapshotId);
        return written == null
            ? null
            : SnapshotRestoreEntry(snapshotId: written);
    }
  }
}
