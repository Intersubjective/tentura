import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/mutating_unit_of_work_port.dart';
import 'package:tentura_server/domain/port/trust_cutover_port.dart';
import 'package:tentura_server/utils/id.dart';

import '_use_case_base.dart';

@Singleton(order: 3)
final class TrustCutoverCase extends UseCaseBase {
  TrustCutoverCase(
    this._port,
    this._uow, {
    required super.env,
    required super.logger,
    @ignoreParam this.retryDelay = const Duration(seconds: 5),
  });

  static const _batchSize = 500;
  static const _leaseLength = Duration(minutes: 10);

  final TrustCutoverPort _port;
  final MutatingUnitOfWorkPort _uow;
  final Duration retryDelay;

  /// Random per-process lease owner.
  final _instanceId = generateId('C');

  /// Loads the vote graph into MeritRank once; restartable.
  Future<void> runIfPending() async {
    final deadline = DateTime.timestamp().add(_leaseLength);
    while (true) {
      if (await _port.isDone()) {
        await _banWalls();
        return;
      }
      final token = await _port.acquire(_instanceId);
      if (token != null) {
        await _cutover(token);
        await _banWalls();
        return;
      }
      // Another instance is cutting over.
      if (DateTime.timestamp().isAfter(deadline)) {
        throw StateError('Trust cutover is held by another instance');
      }
      await Future<void>.delayed(retryDelay);
    }
  }

  Future<void> _cutover(int token) async {
    final pairs = await _port.votePairs();
    for (var i = 0; i < pairs.length; i += _batchSize) {
      final batch = pairs.sublist(
        i,
        i + _batchSize > pairs.length ? pairs.length : i + _batchSize,
      );
      await _uow.run(action: () => _port.projectPairs(token, batch));
      await _renew(token);
    }
    await _port.reset(token);
    await _port.init(token);
    await _port.sync(token);
    await _port.finish(token);
  }

  /// B1: projects every existing block as a wall, once. Idempotent, so a
  /// concurrent run is harmless; publication goes through the queue.
  Future<void> _banWalls() async {
    if (await _port.banWallsDone()) return;
    final pairs = await _port.banPairs();
    for (var i = 0; i < pairs.length; i += _batchSize) {
      final batch = pairs.sublist(
        i,
        i + _batchSize > pairs.length ? pairs.length : i + _batchSize,
      );
      await _uow.run(action: () => _port.projectBanPairs(batch));
    }
    await _port.markBanWallsDone();
  }

  Future<void> _renew(int token) async {
    if (!await _port.renew(token)) {
      throw StateError('Trust cutover lease lost');
    }
  }
}
