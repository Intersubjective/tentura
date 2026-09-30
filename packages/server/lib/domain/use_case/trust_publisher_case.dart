import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/trust_publish_port.dart';
import 'package:tentura_server/utils/id.dart';

import '_use_case_base.dart';

@Singleton(order: 3)
final class TrustPublisherCase extends UseCaseBase {
  TrustPublisherCase(
    this._port, {
    required super.env,
    required super.logger,
  });

  static const _batchSize = 200;

  final TrustPublishPort _port;

  /// Random per-process lease owner.
  final _instanceId = generateId('P');

  var _nudged = false;

  /// Asks the worker to run [run] on its next tick (bypassing the cadence
  /// gate); never runs a publisher itself.
  void nudge() => _nudged = true;

  /// True once per [nudge].
  bool consumeNudge() {
    final was = _nudged;
    _nudged = false;
    return was;
  }

  Future<void> run() async {
    if (await _port.cutoverPending()) return;
    final token = await _port.acquireLease(_instanceId);
    if (token == null) return;
    final rows = await _port.readBatch(_batchSize);
    if (rows.isEmpty) return;
    try {
      for (final row in rows) {
        if (!await _port.leaseValid(token)) return;
        await _port.publish(row);
      }
      await _port.sync();
    } catch (e) {
      await _port.fail(rows, e.toString());
      return;
    }
    await _port.ack(token, rows);
  }
}
