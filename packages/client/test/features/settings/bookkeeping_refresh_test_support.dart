import 'package:logging/logging.dart';

import 'package:tentura/data/service/bookkeeping_refresh_signal.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/domain/use_case/bookkeeping_refresh_case.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/auth/domain/use_case/auth_case.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/settings/domain/entity/user_recalculate_bookkeeping_result.dart';
import 'package:tentura/features/settings/domain/port/bookkeeping_refresh_repository_port.dart';

import '../auth/auth_test_helpers.dart';

class SignedInAuthLocal extends EmptyAuthLocal {
  static const accountId = 'Utest0000001';

  @override
  Stream<String> currentAccountChanges() => Stream.value(accountId);

  @override
  Future<String> getCurrentAccountId() async => accountId;
}

class FakeBookkeepingRefreshRepository
    implements BookkeepingRefreshRepositoryPort {
  UserRecalculateBookkeepingResult result = const UserRecalculateBookkeepingResult(
    coordinationRepairedCount: 1,
    inboxRowsRepairedCount: 2,
    inboxRowsInsertedCount: 1,
    affectedBeaconIds: ['B1', 'B2'],
  );

  int callCount = 0;

  @override
  Future<UserRecalculateBookkeepingResult> recalculateBookkeeping() async {
    callCount++;
    return result;
  }
}

class FakeBeaconRepositoryForBookkeeping implements BeaconRepository {
  final refreshedBeaconIds = <String>[];

  @override
  Future<void> refreshAndNotify(String id) async {
    refreshedBeaconIds.add(id);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

BookkeepingRefreshCase buildTestBookkeepingRefreshCase({
  BookkeepingRefreshRepositoryPort? repository,
  AuthCase? authCase,
  BeaconRepository? beaconRepository,
  BookkeepingRefreshSignal? refreshSignal,
}) =>
    BookkeepingRefreshCase(
      repository ?? FakeBookkeepingRefreshRepository(),
      authCase ?? buildTestAuthCase(SignedInAuthLocal(), EmptyAuthRemote()),
      beaconRepository ?? FakeBeaconRepositoryForBookkeeping(),
      refreshSignal ?? BookkeepingRefreshSignal(),
      env: const Env(),
      logger: Logger('test'),
    );
