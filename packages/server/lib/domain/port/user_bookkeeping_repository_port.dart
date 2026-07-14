import 'package:tentura_server/domain/entity/user_bookkeeping_result.dart';

abstract class UserBookkeepingRepositoryPort {
  Future<List<AdmittedOfferCoordinationGap>>
  listAdmittedOffersMissingCoordination(String authorUserId);

  Future<InboxReconcileResult> reconcileInboxForUser(String userId);
}
