import 'package:injectable/injectable.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/port/attention_dispatch_port.dart';
import 'package:tentura_server/domain/port/mutating_unit_of_work_port.dart';

/// Runs one domain mutation and its occurrence/receipt/job materialization atomically.
@Singleton(order: 1)
class TransactionalAttentionCase {
  const TransactionalAttentionCase(this._unitOfWork, this._dispatch);

  final MutatingUnitOfWorkPort _unitOfWork;
  final AttentionDispatchPort _dispatch;

  Future<T> runAction<T>({
    required String? actorUserId,
    required Future<T> Function(AttentionTransaction transaction) action,
  }) async {
    return _unitOfWork.run(
      actorUserId: actorUserId,
      action: () => action(AttentionTransaction._(_dispatch)),
    );
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
  AttentionTransaction._(this._dispatch);

  final AttentionDispatchPort _dispatch;

  Future<void> record(AttentionDispatchIntent intent) =>
      _dispatch.record(intent);
}
