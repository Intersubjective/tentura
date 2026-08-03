import 'package:injectable/injectable.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/repository_event.dart';

import '../../data/repository/block_repository.dart';
import '../entity/user_block.dart';

@singleton
class BlockCase {
  BlockCase(this._repository);

  final BlockRepository _repository;

  Stream<RepositoryEvent<BlockIntent>> get changes => _repository.changes;

  Future<void> block({
    required String objectId,
    required int cascadeMode,
  }) =>
      _repository.block(objectId: objectId, cascadeMode: cascadeMode);

  Future<void> unblock({required String objectId}) =>
      _repository.unblock(objectId: objectId);

  Future<void> promote({required String objectId}) =>
      _repository.promote(objectId: objectId);

  Future<List<BlockIntent>> fetchMyBlocks() => _repository.fetchMyBlocks();

  Future<List<Profile>> fetchInherited({required String originId}) =>
      _repository.fetchInherited(originId: originId);

  Future<BlockPreview> preview({
    required String objectId,
    required int cascadeMode,
  }) =>
      _repository.preview(objectId: objectId, cascadeMode: cascadeMode);
}
