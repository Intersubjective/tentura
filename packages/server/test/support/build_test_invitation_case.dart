import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';

import 'package:tentura_server/domain/entity/forward_edge_entity.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/forward_edge_repository_port.dart';
import 'package:tentura_server/domain/port/invitation_repository_port.dart';
import 'package:tentura_server/domain/port/user_contact_repository_port.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/port/vote_user_friendship_lookup_port.dart';
import 'package:tentura_server/domain/use_case/invitation_case.dart';
import 'package:tentura_server/env.dart';

import 'fake_beacon_access_guard.dart';

InvitationCase buildTestInvitationCase({
  required InvitationRepositoryPort invitationRepo,
  required UserRepositoryPort userRepo,
  required BeaconRepositoryPort beaconRepo,
  required VoteUserFriendshipLookupPort friendshipLookup,
  required UserContactRepositoryPort contactRepo,
  ForwardEdgeRepositoryPort? forwardEdgeRepo,
  FakeBeaconAccessGuard? guard,
  Env? env,
  Logger? logger,
}) =>
    InvitationCase(
      invitationRepo,
      userRepo,
      beaconRepo,
      friendshipLookup,
      contactRepo,
      guard ?? FakeBeaconAccessGuard(),
      _NoopForwardEdgeRepositoryPort(forwardEdgeRepo),
      env: env ?? Env(environment: Environment.test),
      logger: logger ?? Logger('InvitationCaseTest'),
    );

class _NoopForwardEdgeRepositoryPort implements ForwardEdgeRepositoryPort {
  _NoopForwardEdgeRepositoryPort(this._delegate);

  final ForwardEdgeRepositoryPort? _delegate;

  ForwardEdgeRepositoryPort get _d =>
      _delegate ?? _UnimplementedForwardEdgeRepositoryPort();

  @override
  Future<void> cancel(String edgeId, String senderId) => _d.cancel(edgeId, senderId);

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
      _d.create(
        beaconId: beaconId,
        senderId: senderId,
        recipientId: recipientId,
        note: note,
        context: context,
        parentEdgeId: parentEdgeId,
        batchId: batchId,
      );

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
      _d.createBatch(
        beaconId: beaconId,
        senderId: senderId,
        recipientIds: recipientIds,
        batchId: batchId,
        noteForRecipient: noteForRecipient,
        context: context,
        parentEdgeId: parentEdgeId,
        onAfterEdgesInserted: onAfterEdgesInserted,
      );

  @override
  Future<void> createForInviteAccept({
    required String beaconId,
    required String senderId,
    required String recipientId,
    String? parentEdgeId,
  }) =>
      _d.createForInviteAccept(
        beaconId: beaconId,
        senderId: senderId,
        recipientId: recipientId,
        parentEdgeId: parentEdgeId,
      );

  @override
  Future<bool> existsWithParent(String parentEdgeId) =>
      _d.existsWithParent(parentEdgeId);

  @override
  Future<ForwardEdgeEntity?> fetchById(String edgeId) => _d.fetchById(edgeId);

  @override
  Future<List<ForwardEdgeEntity>> fetchActiveInboundEdges({
    required String beaconId,
    required String recipientId,
  }) async =>
      const [];

  @override
  Future<List<ForwardEdgeEntity>> fetchByBeaconId(String beaconId) =>
      _d.fetchByBeaconId(beaconId);

  @override
  Future<List<ForwardEdgeEntity>> fetchByRecipientId(
    String recipientId, {
    String? context,
  }) =>
      _d.fetchByRecipientId(recipientId, context: context);

  @override
  Future<List<ForwardEdgeEntity>> fetchHelpOffererPathChain({
    required String beaconId,
    required String helpOffererId,
    required String viewerId,
  }) =>
      _d.fetchHelpOffererPathChain(
        beaconId: beaconId,
        helpOffererId: helpOffererId,
        viewerId: viewerId,
      );

  @override
  Future<List<String>> fetchDistinctSenderIdsByBeaconId(String beaconId) =>
      _d.fetchDistinctSenderIdsByBeaconId(beaconId);

  @override
  Future<ForwardEdgeEntity?> findActiveEdge({
    required String beaconId,
    required String senderId,
    required String recipientId,
  }) =>
      _d.findActiveEdge(
        beaconId: beaconId,
        senderId: senderId,
        recipientId: recipientId,
      );

  @override
  Future<bool> isDirectAuthorForward({
    required String beaconId,
    required String authorId,
    required String userId,
  }) =>
      _d.isDirectAuthorForward(
        beaconId: beaconId,
        authorId: authorId,
        userId: userId,
      );

  @override
  Future<void> markAsRead(String edgeId, String recipientId) =>
      _d.markAsRead(edgeId, recipientId);

  @override
  Future<void> updateNote(String edgeId, String senderId, String note) =>
      _d.updateNote(edgeId, senderId, note);
}

class _UnimplementedForwardEdgeRepositoryPort
    implements ForwardEdgeRepositoryPort {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
