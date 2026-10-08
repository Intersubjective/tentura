import 'dart:convert';

import 'package:injectable/injectable.dart';

import 'package:tentura_server/consts.dart';
import 'package:tentura_server/domain/port/meritrank_status_port.dart';

import '_base_controller.dart';

/// The status read shares the worker's single DB connection; a busy or stalled
/// connection must not hold the liveness probe (compose timeout 3 s).
const kHealthStatusTimeout = Duration(seconds: 1);

@Injectable(order: 3)
final class HealthController extends BaseController {
  const HealthController(super.env, this._meritrankStatusPort);

  final MeritrankStatusPort _meritrankStatusPort;

  /// An unreachable or slow status read is reported, never turned into an
  /// error or a hang: the route stays a liveness probe.
  @override
  Future<Response> handler(Request request) async {
    Map<String, Object?> meritrank;
    try {
      final status = await _meritrankStatusPort.status().timeout(
        kHealthStatusTimeout,
      );
      meritrank = {
        'available': true,
        'walksCacheSize': status.walksCacheSize,
        'activeReaders': status.activeReaders,
        'walksCacheOverCapacity': status.walksCacheOverCapacity,
        'snapshotBytes': status.snapshotBytes,
        'snapshotBudgetBytes': status.snapshotBudgetBytes,
        'snapshotPressure': status.snapshotBytes == null
            ? null
            : status.snapshotPressure,
      };
    } catch (_) {
      meritrank = {'available': false};
    }
    return Response.ok(
      jsonEncode({'status': 'ok', 'meritrank': meritrank}),
      headers: {kHeaderContentType: kContentApplicationJson},
    );
  }
}
