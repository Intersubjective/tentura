import 'package:tentura_server/domain/entity/commitment_entity.dart';
import 'package:tentura_server/domain/entity/forward_edge_entity.dart';
import 'package:tentura_server/domain/port/commitment_repository_port.dart';
import 'package:tentura_server/domain/port/forward_edge_repository_port.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';

/// Minimal fakes so `EvaluationParticipantGraphBuilder` returns an empty graph.
final class EmptyGraphCommitmentRepository implements CommitmentRepositoryPort {
  @override
  Future<void> upsert({
    required String beaconId,
    required String userId,
    String message = '',
    List<String>? helpTypes,
    int status = 0,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> withdraw({
    required String beaconId,
    required String userId,
    required String uncommitReason,
    String message = '',
  }) =>
      throw UnimplementedError();

  @override
  Future<List<CommitmentEntity>> fetchByBeaconId(String beaconId) async => [];

  @override
  Future<List<CommitmentEntity>> fetchAllByBeaconId(String beaconId) =>
      throw UnimplementedError();

  @override
  Future<List<CommitmentEntity>> fetchByUserId(String userId) =>
      throw UnimplementedError();

  @override
  Future<bool> hasActiveCommitment({
    required String beaconId,
    required String userId,
  }) =>
      throw UnimplementedError();
}

final class EmptyGraphForwardEdgeRepository implements ForwardEdgeRepositoryPort {
  @override
  Future<void> create({
    required String beaconId,
    required String senderId,
    required String recipientId,
    required String note,
    String? context,
    String? parentEdgeId,
    String? batchId,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> createBatch({
    required String beaconId,
    required String senderId,
    required List<String> recipientIds,
    required String batchId,
    required String Function(String recipientId) noteForRecipient,
    String? context,
    String? parentEdgeId,
    Future<void> Function()? onAfterEdgesInserted,
  }) =>
      throw UnimplementedError();

  @override
  Future<List<ForwardEdgeEntity>> fetchByBeaconId(String beaconId) async => [];

  @override
  Future<List<ForwardEdgeEntity>> fetchByRecipientId(
    String recipientId, {
    String? context,
  }) =>
      throw UnimplementedError();

  @override
  Future<List<String>> fetchDistinctSenderIdsByBeaconId(String beaconId) =>
      throw UnimplementedError();
}

final class StubUserRepository implements UserRepositoryPort {
  StubUserRepository(this._title);

  final String _title;

  @override
  Future<UserEntity> getById(String id) async => UserEntity(id: id, title: _title);

  @override
  Future<UserEntity> create({
    required String publicKey,
    required String title,
  }) =>
      throw UnimplementedError();

  @override
  Future<UserEntity> createInvited({
    required String invitationId,
    required String publicKey,
    required String title,
  }) =>
      throw UnimplementedError();

  @override
  Future<UserEntity> getByPublicKey(String publicKey) =>
      throw UnimplementedError();

  @override
  Future<void> update({
    required String id,
    String? title,
    String? description,
    String? imageId,
    bool dropImage = false,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> deleteById({required String id}) => throw UnimplementedError();

  @override
  Future<bool> bindMutual({
    required String invitationId,
    required String userId,
  }) =>
      throw UnimplementedError();
}
