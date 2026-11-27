import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../entity/phantom_import.dart';

abstract interface class PhantomRepositoryPort {
  Future<String> create({
    required String name,
    String? emoji,
    ConstellationAnchorPosition? position,
  });

  Future<List<PhantomImportOutcome>> createBatch({
    required List<PhantomImportContact> rows,
    required bool keepContacts,
    required String clientOpId,
  });

  Future<void> update({
    required String id,
    required String name,
    String? emoji,
  });

  Future<Uri> forwardRequest({
    required String phantomId,
    required String beaconId,
    String? note,
  });

  Future<void> delete({required String id});
  Future<String> inviteEnsure({required String id});
  Future<String> inviteRotate({required String id});

  Future<void> link({required String phantomId, required String userId});
  Future<void> unmerge({required String phantomId, String? mergeId});
  Future<void> hintDismiss({required String phantomId, required String userId});
}
