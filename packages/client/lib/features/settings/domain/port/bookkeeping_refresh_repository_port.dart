import 'package:tentura/features/settings/domain/entity/user_recalculate_bookkeeping_result.dart';

abstract class BookkeepingRefreshRepositoryPort {
  Future<UserRecalculateBookkeepingResult> recalculateBookkeeping();
}
