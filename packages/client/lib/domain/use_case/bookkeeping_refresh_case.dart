import 'package:injectable/injectable.dart';

import 'package:tentura/data/service/bookkeeping_refresh_signal.dart';
import 'package:tentura/domain/use_case/use_case_base.dart';
import 'package:tentura/features/auth/domain/use_case/auth_case.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/settings/domain/entity/user_recalculate_bookkeeping_result.dart';
import 'package:tentura/features/settings/domain/port/bookkeeping_refresh_repository_port.dart';

@singleton
final class BookkeepingRefreshCase extends UseCaseBase {
  BookkeepingRefreshCase(
    this._repository,
    this._authCase,
    this._beaconRepository,
    this._refreshSignal, {
    required super.env,
    required super.logger,
  });

  final BookkeepingRefreshRepositoryPort _repository;
  final AuthCase _authCase;
  final BeaconRepository _beaconRepository;
  final BookkeepingRefreshSignal _refreshSignal;

  Future<UserRecalculateBookkeepingResult> recalculateForCurrentUser() async {
    final accountId = await _authCase.getCurrentAccountId();
    if (accountId.isEmpty) {
      throw StateError('No active account');
    }

    final result = await _repository.recalculateBookkeeping();
    _refreshSignal.notify();

    for (final beaconId in result.affectedBeaconIds) {
      try {
        await _beaconRepository.refreshAndNotify(beaconId);
      } on Object catch (e, st) {
        logger.warning(
          'BookkeepingRefresh: beacon refresh failed for $beaconId',
          e,
          st,
        );
      }
    }

    return result;
  }
}
