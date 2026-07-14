import 'package:injectable/injectable.dart';

import 'package:tentura/data/repository/remote_repository.dart';

import 'package:tentura/features/settings/data/gql/_g/user_recalculate_bookkeeping.req.gql.dart';
import 'package:tentura/features/settings/domain/entity/user_recalculate_bookkeeping_result.dart';
import 'package:tentura/features/settings/domain/port/bookkeeping_refresh_repository_port.dart';

@Singleton(
  as: BookkeepingRefreshRepositoryPort,
  env: [Environment.dev, Environment.prod],
)
class BookkeepingRefreshRepository extends RemoteRepository
    implements BookkeepingRefreshRepositoryPort {
  BookkeepingRefreshRepository({
    required super.remoteApiService,
    required super.log,
  });

  @override
  Future<UserRecalculateBookkeepingResult> recalculateBookkeeping() async {
    final data = await requestDataOnlineOrThrow(
      GUserRecalculateBookkeepingReq(),
      label: _label,
    );
    final result = data.userRecalculateBookkeeping;
    return UserRecalculateBookkeepingResult(
      coordinationRepairedCount: result.coordinationRepairedCount,
      inboxRowsRepairedCount: result.inboxRowsRepairedCount,
      inboxRowsInsertedCount: result.inboxRowsInsertedCount,
      affectedBeaconIds: result.affectedBeaconIds.toList(growable: false),
    );
  }

  static const _label = 'UserRecalculateBookkeeping';
}
