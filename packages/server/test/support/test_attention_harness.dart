import 'package:mockito/mockito.dart';

import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/entity/beacon_notification_context.dart';
import 'package:tentura_server/domain/entity/beacon_notification_intent.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/port/attention_dispatch_port.dart';
import 'package:tentura_server/domain/port/beacon_access_guard.dart';
import 'package:tentura_server/domain/port/beacon_room_notification_context_port.dart';
import 'package:tentura_server/domain/port/mutating_unit_of_work_port.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';

final class TestAttentionHarness {
  TestAttentionHarness({
    BeaconNotificationContext context = const BeaconNotificationContext(),
    bool canReadBeaconContent = true,
    void Function()? onContextLoaded,
  }) : _dispatch = _RecordingDispatch(),
       intents = AttentionIntentCase(
         _Context(context, onContextLoaded),
         _Users(),
         _Access(allowed: canReadBeaconContent),
       ) {
    transactional = TransactionalAttentionCase(
      _UnitOfWork(),
      _dispatch,
    );
  }

  final _RecordingDispatch _dispatch;
  final AttentionIntentCase intents;
  late final TransactionalAttentionCase transactional;

  List<AttentionDispatchIntent> get recorded => _dispatch.recorded;
}

final class _UnitOfWork extends Fake implements MutatingUnitOfWorkPort {
  @override
  Future<T> run<T>({
    required Future<T> Function() action,
    String? actorUserId,
  }) => action();
}

final class _RecordingDispatch extends Fake implements AttentionDispatchPort {
  final List<AttentionDispatchIntent> recorded = [];

  @override
  Future<void> record(AttentionDispatchIntent intent) async {
    recorded.add(intent);
  }
}

final class _Context extends Fake implements BeaconRoomNotificationContextPort {
  _Context(this.context, this.onLoaded);

  final BeaconNotificationContext context;
  final void Function()? onLoaded;

  @override
  Future<BeaconNotificationContext> loadContextForBeacon(
    String beaconId,
  ) async {
    onLoaded?.call();
    return context;
  }
}

final class _Users extends Fake implements UserRepositoryPort {
  @override
  Future<UserEntity> getById(String id) async =>
      UserEntity(id: id, displayName: 'Actor');
}

final class _Access extends Fake implements BeaconAccessGuard {
  _Access({required this.allowed});

  final bool allowed;

  @override
  Future<bool> canReadContent({
    required String beaconId,
    required String viewerId,
  }) async => allowed;
}
