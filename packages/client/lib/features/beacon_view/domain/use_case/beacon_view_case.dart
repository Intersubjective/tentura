import 'dart:async';

import 'package:injectable/injectable.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/domain/entity/coordination_status.dart';
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

import '../../data/repository/beacon_author_update_repository.dart';
import '../../data/repository/beacon_view_repository.dart';
import '../../data/repository/coordination_repository.dart';
import '../../domain/typedef.dart';

@singleton
final class BeaconViewCase extends UseCaseBase {
  BeaconViewCase(
    this._beaconRepository,
    this._beaconViewRepository,
    this._forwardRepository,
    this._evaluationRepository,
    this._coordinationRepository,
    this._inboxRepository,
    this._beaconAuthorUpdateRepository, {
    required super.env,
    required super.logger,
  });

  final BeaconRepository _beaconRepository;

  final BeaconViewRepository _beaconViewRepository;

  final ForwardRepository _forwardRepository;

  final EvaluationRepository _evaluationRepository;

  final CoordinationRepository _coordinationRepository;

  final InboxRepository _inboxRepository;

  final BeaconAuthorUpdateRepository _beaconAuthorUpdateRepository;

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
    String? helpType,
    bool notifyCommitmentListeners = true,
  }) =>
      _forwardRepository.commit(
        beaconId: beaconId,
        message: message,
        helpType: helpType,
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
  }) =>
      _coordinationRepository.setCoordinationResponse(
        beaconId: beaconId,
        commitUserId: commitUserId,
        responseType: responseType,
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

  Future<BeaconInvolvementData> fetchBeaconInvolvement({
    required String beaconId,
  }) =>
      _forwardRepository.fetchBeaconInvolvement(beaconId: beaconId);

  Future<BeaconViewResult> fetchBeaconByCommentId(String commentId) =>
      _beaconViewRepository.fetchBeaconByCommentId(commentId);

  Future<bool> currentUserHasForwardedBeacon(String beaconId) =>
      _forwardRepository.currentUserHasForwardedBeacon(beaconId);
}
