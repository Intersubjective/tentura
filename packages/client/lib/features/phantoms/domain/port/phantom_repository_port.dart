import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

abstract interface class PhantomRepositoryPort {
  Future<String> create({
    required String name,
    String? emoji,
    ConstellationAnchorPosition? position,
  });

  Future<void> update({
    required String id,
    required String name,
    String? emoji,
  });

  Future<void> delete({required String id});
  Future<String> inviteEnsure({required String id});
  Future<String> inviteRotate({required String id});

  Future<void> link({required String phantomId, required String userId});
  Future<void> unmerge({required String phantomId});
  Future<void> hintDismiss({required String phantomId, required String userId});
}
