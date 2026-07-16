import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart';

import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/port/attention_dispatch_port.dart';
import 'package:tentura_server/domain/port/beacon_notification_port.dart';
import 'package:tentura_server/domain/port/mutating_unit_of_work_port.dart';

/// Runs one domain mutation and its receipt materialization atomically, then
/// hands channel work to the existing best-effort pipeline after commit.
@Singleton(order: 1)
class TransactionalAttentionCase {
  const TransactionalAttentionCase(
    this._unitOfWork,
    this._dispatch,
    this._channels,
    this._logger,
  );

  final MutatingUnitOfWorkPort _unitOfWork;
  final AttentionDispatchPort _dispatch;
  final BeaconNotificationPort _channels;
  final Logger _logger;

  Future<T> runAction<T>({
    required String? actorUserId,
    required Future<T> Function(AttentionTransaction transaction) action,
  }) async {
    final channelDecisions = <AttentionChannelDecision>[];
    final result = await _unitOfWork.run(
      actorUserId: actorUserId,
      action: () => action(
        AttentionTransaction._(_dispatch, channelDecisions),
      ),
    );

    try {
      await _channels.handOffChannels(channelDecisions);
    } on Object catch (error, stackTrace) {
      _logger.warning(
        '[Attention] post-commit channel hand-off failed',
        error,
        stackTrace,
      );
    }
    return result;
  }

  Future<T> run<T>({
    required String? actorUserId,
    required AttentionDispatchIntent intent,
    required Future<T> Function() mutation,
  }) async {
    return runAction(
      actorUserId: actorUserId,
      action: (transaction) async {
        final value = await mutation();
        await transaction.record(intent);
        return value;
      },
    );
  }
}

final class AttentionTransaction {
  AttentionTransaction._(this._dispatch, this._channelDecisions);

  final AttentionDispatchPort _dispatch;
  final List<AttentionChannelDecision> _channelDecisions;

  Future<void> record(AttentionDispatchIntent intent) async {
    _channelDecisions.addAll(await _dispatch.record(intent));
  }
}
