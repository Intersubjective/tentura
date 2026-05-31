import 'package:tentura_server/domain/entity/help_offer_entity.dart';
import 'package:tentura_server/domain/entity/forward_edge_entity.dart';
import 'package:tentura_server/domain/port/help_offer_repository_port.dart';
import 'package:tentura_server/domain/port/forward_edge_repository_port.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/entity/account_credential_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';

/// Minimal fakes so `EvaluationParticipantGraphBuilder` returns an empty graph.
final class EmptyGraphHelpOfferRepository implements HelpOfferRepositoryPort {
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
    required String withdrawReason,
    String message = '',
  }) =>
      throw UnimplementedError();

  @override
  Future<List<HelpOfferEntity>> fetchByBeaconId(String beaconId) async => [];

  @override
  Future<List<HelpOfferEntity>> fetchAllByBeaconId(String beaconId) =>
      throw UnimplementedError();

  @override
  Future<List<HelpOfferEntity>> fetchByUserId(String userId) =>
      throw UnimplementedError();

  @override
  Future<bool> hasActiveHelpOffer({
    required String beaconId,
    required String userId,
  }) =>
      throw UnimplementedError();
}

final class EmptyGraphForwardEdgeRepository implements ForwardEdgeRepositoryPort {
  @override
  Future<ForwardEdgeEntity?> fetchById(String edgeId) => throw UnimplementedError();

  @override
  Future<bool> existsWithParent(String parentEdgeId) => throw UnimplementedError();

  @override
  Future<void> cancel(String edgeId, String senderId) => throw UnimplementedError();

  @override
  Future<void> updateNote(String edgeId, String senderId, String note) =>
      throw UnimplementedError();

  @override
  Future<void> markAsRead(String edgeId, String recipientId) =>
      throw UnimplementedError();

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
  Future<List<ForwardEdgeEntity>> fetchHelpOffererPathChain({
    required String beaconId,
    required String helpOffererId,
    required String viewerId,
  }) async =>
      [];

  @override
  Future<List<ForwardEdgeEntity>> fetchByRecipientId(
    String recipientId, {
    String? context,
  }) =>
      throw UnimplementedError();

  @override
  Future<List<String>> fetchDistinctSenderIdsByBeaconId(String beaconId) =>
      throw UnimplementedError();

  @override
  Future<bool> isDirectAuthorForward({
    required String beaconId,
    required String authorId,
    required String userId,
  }) async => false;
}

final class StubUserRepository implements UserRepositoryPort {
  StubUserRepository(this._displayName);

  final String _displayName;

  @override
  Future<UserEntity> getById(String id) async =>
      UserEntity(id: id, displayName: _displayName);

  @override
  Future<UserEntity> create({
    required String publicKey,
    required String displayName,
    String? handle,
  }) =>
      throw UnimplementedError();

  @override
  Future<UserEntity> createInvited({
    required String invitationId,
    required String publicKey,
    required String displayName,
    String? handle,
  }) =>
      throw UnimplementedError();

  @override
  Future<UserEntity> createWithCredential({
    required CredentialType type,
    required String identifier,
    required String displayName,
    String? handle,
    Map<String, Object?>? publicData,
  }) =>
      throw UnimplementedError();

  @override
  Future<UserEntity> createInvitedWithCredential({
    required String invitationId,
    required CredentialType type,
    required String identifier,
    required String displayName,
    String? handle,
    Map<String, Object?>? publicData,
  }) =>
      throw UnimplementedError();

  @override
  Future<UserEntity> getByPublicKey(String publicKey) =>
      throw UnimplementedError();

  @override
  Future<UserEntity> getByCredential({
    required String type,
    required String identifier,
  }) =>
      throw UnimplementedError();

  @override
  Future<List<AccountCredentialEntity>> listCredentials({
    required String accountId,
  }) =>
      throw UnimplementedError();

  @override
  Future<AccountCredentialEntity> addCredential({
    required String accountId,
    required CredentialType type,
    required String identifier,
    Map<String, Object?>? publicData,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> removeCredential({
    required String accountId,
    required String credentialId,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> update({
    required String id,
    String? displayName,
    String? description,
    String? imageId,
    bool dropImage = false,
    bool setHandle = false,
    String? handle,
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
