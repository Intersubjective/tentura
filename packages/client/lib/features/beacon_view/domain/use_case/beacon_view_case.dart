import 'dart:async';

import 'package:injectable/injectable.dart';

import 'package:tentura/domain/entity/beacon_activity_event.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/domain/entity/coordination_status.dart';
import 'package:tentura/domain/entity/beacon_room_state.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/use_case/use_case_base.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/evaluation/data/repository/evaluation_repository.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/commitment_event.dart';
import 'package:tentura/features/forward/domain/entity/forward_edge.dart';
import 'package:tentura/features/inbox/data/repository/inbox_repository.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_provenance.dart';
import 'package:tentura/features/inbox/domain/enum.dart';
import 'package:tentura/features/beacon_room/data/repository/beacon_activity_event_repository.dart';
import 'package:tentura/features/beacon_room/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/beacon_room/domain/use_case/beacon_room_case.dart';

import '../../data/repository/beacon_author_update_repository.dart';
import '../../data/repository/coordination_repository.dart';

@singleton
final class BeaconViewCase extends UseCaseBase {
  BeaconViewCase(
    this._beaconRepository,
    this._forwardRepository,
    this._evaluationRepository,
    this._coordinationRepository,
    this._inboxRepository,
    this._beaconAuthorUpdateRepository,
    this._factCards,
    this._beaconRoomCase,
    this._activityEvents, {
    required super.env,
    required super.logger,
  });

  final BeaconRepository _beaconRepository;

  final ForwardRepository _forwardRepository;

  final EvaluationRepository _evaluationRepository;

  final CoordinationRepository _coordinationRepository;

  final InboxRepository _inboxRepository;

  final BeaconAuthorUpdateRepository _beaconAuthorUpdateRepository;

  final BeaconFactCardRepository _factCards;

  final BeaconRoomCase _beaconRoomCase;

  final BeaconActivityEventRepository _activityEvents;

  Stream<String> get forwardCompleted => _forwardRepository.forwardCompleted;

  Stream<CommitmentEvent> get commitmentChanges =>
      _forwardRepository.commitmentChanges;

  Future<void> setInboxStatus({
    required String beaconId,
    required InboxItemStatus status,
    String rejectionMessage = '',
  }) =>
      _inboxRepository.setStatus(
        beaconId: beaconId,
        status: status,
        rejectionMessage: rejectionMessage,
      );

  Future<void> deleteBeacon(String beaconId) =>
      _beaconRepository.delete(beaconId);

  Future<({String closesAt})> beaconCloseWithReview(String beaconId) =>
      _evaluationRepository.beaconCloseWithReview(beaconId);

  Future<void> setBeaconLifecycle(BeaconLifecycle next, {required String id}) =>
      _beaconRepository.setBeaconLifecycle(next, id: id);

  Future<bool> forwardCommit({
    required String beaconId,
    String? message,
    List<String>? helpTypes,
    bool notifyCommitmentListeners = true,
  }) =>
      _forwardRepository.commit(
        beaconId: beaconId,
        message: message,
        helpTypes: helpTypes,
        notifyCommitmentListeners: notifyCommitmentListeners,
      );

  Future<bool> forwardWithdraw({
    required String beaconId,
    required String uncommitReason,
    String? message,
  }) =>
      _forwardRepository.withdraw(
        beaconId: beaconId,
        message: message,
        uncommitReason: uncommitReason,
      );

  Future<({BeaconCoordinationStatus status, DateTime? updatedAt})>
      setCoordinationResponse({
    required String beaconId,
    required String commitUserId,
    required int responseType,
    required bool inviteToRoom,
    required bool removeFromRoom,
  }) =>
      _coordinationRepository.setCoordinationResponse(
        beaconId: beaconId,
        commitUserId: commitUserId,
        responseType: responseType,
        inviteToRoom: inviteToRoom,
        removeFromRoom: removeFromRoom,
      );

  Future<void> setBeaconCoordinationStatus({
    required String beaconId,
    required int coordinationStatus,
  }) =>
      _coordinationRepository.setBeaconCoordinationStatus(
        beaconId: beaconId,
        coordinationStatus: coordinationStatus,
      );

  Future<Beacon> fetchBeaconById(String beaconId) =>
      _beaconRepository.fetchBeaconById(beaconId);

  Future<List<BeaconFactCard>> fetchFactCards(String beaconId) =>
      _factCards.list(beaconId: beaconId);

  /// Room API; returns empty when caller is not allowed (e.g. no room access).
  Future<List<BeaconParticipant>> fetchRoomParticipants(String beaconId) async {
    try {
      return await _beaconRoomCase.fetchParticipants(beaconId);
    } on Object catch (_) {
      return [];
    }
  }

  /// Latest private room state slice; `null` when the viewer cannot use the room API.
  Future<BeaconRoomState?> fetchRoomStateIfAllowed(String beaconId) async {
    try {
      return await _beaconRoomCase.fetchBeaconRoomState(beaconId);
    } on Object catch (_) {
      return null;
    }
  }

  /// Room coordination activity timeline (V2); empty when not a room member.
  Future<List<BeaconActivityEvent>> fetchRoomActivityEvents(
    String beaconId,
  ) async {
    try {
      return await _activityEvents.list(beaconId: beaconId);
    } on Object catch (_) {
      return [];
    }
  }

  Future<
      List<
          ({
            String beaconId,
            String userId,
            Profile user,
            String message,
            String? helpType,
            int status,
            String? uncommitReason,
            DateTime createdAt,
            DateTime updatedAt,
            int? responseType,
            DateTime? responseUpdatedAt,
            String? responseAuthorUserId,
          })>> fetchCommitmentsWithCoordination({
    required String beaconId,
  }) =>
      _coordinationRepository.fetchCommitmentsWithCoordination(
        beaconId: beaconId,
      );

  Future<
      List<
          ({
            String id,
            int number,
            Profile author,
            String content,
            DateTime createdAt,
          })>>
      fetchBeaconUpdates({
    required String beaconId,
  }) =>
      _forwardRepository.fetchUpdates(beaconId: beaconId);

  Future<void> postBeaconAuthorUpdate({
    required String beaconId,
    required String content,
  }) =>
      _beaconAuthorUpdateRepository.post(
        beaconId: beaconId,
        content: content,
      ).then((_) {});

  Future<void> editBeaconAuthorUpdate({
    required String id,
    required String content,
  }) =>
      _beaconAuthorUpdateRepository.edit(id: id, content: content).then((_) {});

  Future<({InboxItemStatus? status, InboxProvenance provenance, String latestNotePreview})>
      fetchInboxContextForBeacon(String beaconId) =>
          _inboxRepository.fetchInboxContextForBeacon(beaconId);

  Future<List<ForwardEdge>> fetchMyForwardEdges({
    required String beaconId,
    required String myUserId,
  }) =>
      _forwardRepository.fetchMyForwardEdges(
        beaconId: beaconId,
        myUserId: myUserId,
      );

  /// All forward edges on the beacon, newest first (`ForwardEdgesFetch`: `order_by: created_at desc`).
  Future<List<ForwardEdge>> fetchForwardEdgesForBeacon(String beaconId) =>
      _forwardRepository.fetchEdges(beaconId: beaconId);

  Future<BeaconInvolvementData> fetchBeaconInvolvement({
    required String beaconId,
  }) =>
      _forwardRepository.fetchBeaconInvolvement(beaconId: beaconId);

  Future<Map<String, List<String>>> fetchForwardReasonsByBeacon(
    String beaconId,
  ) => _forwardRepository.fetchReasonsByBeacon(beaconId: beaconId);

  Future<bool> currentUserHasForwardedBeacon(String beaconId) =>
      _forwardRepository.currentUserHasForwardedBeacon(beaconId);

  Future<Beacon> updatePublicStatus({
    required String beaconId,
    required int publicStatus,
    String? lastPublicMeaningfulChange,
  }) =>
      _beaconRepository.updatePublicStatus(
        id: beaconId,
        publicStatus: publicStatus,
        lastPublicMeaningfulChange: lastPublicMeaningfulChange,
      );
}
