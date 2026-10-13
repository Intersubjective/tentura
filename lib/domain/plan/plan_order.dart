/// Request plan («либретто», #220): canonical chronological step order.
///
/// Generic over the step type so the server snapshot and the client entity
/// share one algorithm.
library;

/// Puts [steps] in canonical order and returns a new list.
///
/// Untimed steps before the first timed step stay first. Every timed step
/// plus the untimed steps after it (up to the next timed step) form a block;
/// blocks are stable-sorted by anchor `startAt ?? endAt` (UTC instant). Idempotent.
List<T> orderPlanChronologically<T>(
  List<T> steps, {
  required DateTime? Function(T) startOf,
  required DateTime? Function(T) endOf,
}) {
  final leading = <T>[];
  final blocks = <({int anchor, List<T> steps})>[];
  for (final step in steps) {
    final anchor = (startOf(step) ?? endOf(step))?.millisecondsSinceEpoch;
    if (anchor != null) {
      blocks.add((anchor: anchor, steps: [step]));
    } else if (blocks.isEmpty) {
      leading.add(step);
    } else {
      blocks.last.steps.add(step);
    }
  }
  // List.sort is not stable; the index tie-break keeps input order.
  final indexed = [for (var i = 0; i < blocks.length; i++) (i, blocks[i])]
    ..sort((a, b) {
      final c = a.$2.anchor.compareTo(b.$2.anchor);
      return c != 0 ? c : a.$1.compareTo(b.$1);
    });
  return [
    ...leading,
    for (final (_, block) in indexed) ...block.steps,
  ];
}

/// Whether [steps] is already in the order [orderPlanChronologically] gives.
bool isPlanChronological<T>(
  List<T> steps, {
  required DateTime? Function(T) startOf,
  required DateTime? Function(T) endOf,
}) {
  final ordered = orderPlanChronologically<T>(
    steps,
    startOf: startOf,
    endOf: endOf,
  );
  for (var i = 0; i < steps.length; i++) {
    if (!identical(steps[i], ordered[i])) return false;
  }
  return true;
}
