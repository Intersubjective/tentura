import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/capability/capability_evidence_models.dart';
import 'package:tentura_server/domain/port/capability_cell_port.dart';
import 'package:tentura_server/domain/use_case/_use_case_base.dart';
import 'package:tentura_server/utils/id.dart';

@Singleton(order: 3)
final class CapabilityCellExpirySweepCase extends UseCaseBase {
  CapabilityCellExpirySweepCase(
    this._cellPort, {
    required super.env,
    required super.logger,
  });

  final CapabilityCellPort _cellPort;

  /// Per-process lease owner for concurrent sweep workers.
  final _leaseOwner = generateId('CS');

  static const _batchSize = 64;

  Future<int> runDue({DateTime? now}) async {
    final clock = now ?? DateTime.timestamp();
    final claimed = await _cellPort.claimExpiredCells(
      limit: _batchSize,
      leaseOwner: _leaseOwner,
    );
    if (claimed.isEmpty) {
      return 0;
    }

    final latenessByRef = await _loadLateness(claimed, clock);
    var processed = 0;
    Duration? maxLateness;

    for (final ref in claimed) {
      try {
        await _cellPort.rebuildCell(ref);
        await _cellPort.releaseSweepLease(ref: ref, leaseOwner: _leaseOwner);
        processed++;

        final lateness = latenessByRef[ref];
        if (lateness != null &&
            (maxLateness == null || lateness > maxLateness)) {
          maxLateness = lateness;
        }
      } catch (e, st) {
        logger.warning(
          'CapabilityCellExpirySweepCase: failed '
          '${ref.observerUserId}/${ref.subjectUserId}/${ref.tagSlug}: $e\n$st',
        );
      }
    }

    if (maxLateness != null) {
      logger.info(
        'CapabilityCellExpirySweepCase: processed $processed cells; '
        'max lateness ${maxLateness.inSeconds}s',
      );
    } else if (processed > 0) {
      logger.info(
        'CapabilityCellExpirySweepCase: processed $processed cells',
      );
    }

    return processed;
  }

  Future<Map<CellRef, Duration>> _loadLateness(
    List<CellRef> claimed,
    DateTime now,
  ) async {
    final result = <CellRef, Duration>{};
    for (final ref in claimed) {
      final expiry = await _cellPort.nextExpiryAt(ref);
      if (expiry != null && !expiry.isAfter(now)) {
        result[ref] = now.difference(expiry);
      }
    }
    return result;
  }
}
