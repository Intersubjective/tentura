import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/bud_anchor_sweep_port.dart';
import 'package:tentura_server/domain/use_case/anchor_inherit_operation.dart';

import '_use_case_base.dart';

/// Anchor inheritance for budded Requests (Arch §8.1, plan C8). Runs from the
/// task worker every 10 s; [nudge] (after a bud commits) forces the next tick.
///
/// No long-lived row lock: the pending rows are read without a lock, each
/// viewer's anchor is applied in that viewer's own transaction, and a final
/// short transaction marks the row. Overlapping runs are safe because the
/// apply op log replays `bud:<child>:<viewer>` and the mark is
/// `WHERE anchor_inherited_at IS NULL`.
@Singleton(order: 1)
final class BudAnchorSweepCase extends UseCaseBase {
  BudAnchorSweepCase(
    this._port,
    this._inherit, {
    required super.env,
    required super.logger,
  });

  static const _batchSize = 50;

  final BudAnchorSweepPort _port;
  final AnchorInheritOperation _inherit;

  var _nudged = false;

  /// Asks the worker to run [run] on its next tick (bypassing the cadence
  /// gate); never runs the sweep itself.
  void nudge() => _nudged = true;

  /// True once per [nudge].
  bool consumeNudge() {
    final was = _nudged;
    _nudged = false;
    return was;
  }

  Future<void> run() async {
    final rows = await _port.pendingBuds(limit: _batchSize);
    for (final row in rows) {
      try {
        final child = row.childBeaconId;
        final post = row.postId;
        if (child != null && post != null) {
          final viewers = await _port.inheritingViewerIds(
            childBeaconId: child,
            postId: post,
          );
          for (final viewer in viewers) {
            await _inherit.inherit(
              childBeaconId: child,
              postId: post,
              viewerId: viewer,
            );
          }
        }
        await _port.markInherited(
          actorUserId: row.actorUserId,
          clientCommandId: row.clientCommandId,
        );
      } catch (e, s) {
        // The row stays unmarked; the next run retries it (replay-safe).
        logger.warning(
          'bud anchor inheritance failed for ${row.childBeaconId}',
          e,
          s,
        );
      }
    }
  }
}
