import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:rxdart/rxdart.dart';

import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/domain/use_case/use_case_base.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/auth/domain/use_case/auth_case.dart';

import '../../data/repository/notification_center_repository.dart';

/// Owns notification feed commands and routes convergence signals to projection
/// owners. Invalidation payloads are hints; consumers always refetch truth.
@singleton
final class NotificationCenterCase extends UseCaseBase {
  NotificationCenterCase(
    NotificationCenterRepository repository,
    RealtimeSyncCase realtime,
    AuthCase auth, {
    required Env env,
    required Logger logger,
  }) : this._(
         repository: repository,
         realtime: realtime,
         auth: auth,
         env: env,
         logger: logger,
       );

  @visibleForTesting
  NotificationCenterCase.forTesting({
    required NotificationCenterRepository repository,
    required Env env,
    required Logger logger,
    RealtimeSyncCase? realtime,
    AuthCase? auth,
  }) : this._(
         repository: repository,
         realtime: realtime,
         auth: auth,
         env: env,
         logger: logger,
       );

  NotificationCenterCase._({
    required this._repository,
    required this._realtime,
    required this._auth,
    required super.env,
    required super.logger,
  });

  final NotificationCenterRepository _repository;
  final RealtimeSyncCase? _realtime;
  final AuthCase? _auth;

  Stream<void> get changes => MergeStream<void>([
    _repository.changes,
    if (_realtime case final realtime?) ...[
      realtime.changesFor(const {RealtimeEntityKind.notification}).map((_) {}),
      realtime.catchUps.map((_) {}),
    ],
  ]);

  Stream<String> get accountChanges =>
      _auth?.currentAccountChanges() ?? const Stream.empty();

  Future<NotificationFeedPage> fetch({
    int limit = 50,
    DateTime? before,
  }) => _repository.fetch(limit: limit, before: before);

  Future<int> fetchUnreadCount() async =>
      (await _repository.fetch(limit: 1)).unreadCount;

  Future<int> markRead(List<String> ids) => _repository.markRead(ids);

  Future<int> markAllRead() => _repository.markAllRead();
}
