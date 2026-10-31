import 'dart:async';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:injectable/injectable.dart';
import 'package:tentura_root/domain/entity/beacon_parent_reference.dart';

import 'package:tentura/domain/entity/beacon_activity_event.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_state.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_pending_upload.dart';
import 'package:tentura/domain/exception/generic_exception.dart';
import 'package:tentura/features/beacon_threads/domain/exception/beacon_fact_already_pinned_exception.dart';
import 'package:tentura/features/beacon_threads/domain/exception/beacon_fact_pin_after_message_exception.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/domain/use_case/use_case_base.dart';
import 'package:tentura/data/repository/presence_repository.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/beacon/domain/port/beacon_hierarchy_repository_port.dart';
import 'package:tentura/features/closure/data/repository/closure_repository.dart';
import 'package:tentura/features/closure/domain/entity/beacon_close_result.dart';
import 'package:tentura/features/closure/domain/entity/closure_state.dart';
import 'package:tentura/features/my_work/data/repository/archive_repository.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/help_offer_event.dart';
import 'package:tentura/features/forward/domain/entity/forward_edge.dart';
import 'package:tentura/features/inbox/data/repository/inbox_repository.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_provenance.dart';
import 'package:tentura/features/inbox/domain/enum.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_activity_event_repository.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/beacon_threads/domain/entity/beacon_room_invalidation.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';

import '../../data/repository/coordination_repository.dart';
import '../../data/repository/beacon_display_repository.dart';
import 'package:tentura/domain/entity/beacon_display_status_dto.dart';
import '../pinned_facts.dart';
import '../help_offer_row_record.dart';

@singleton
final class BeaconViewCase extends UseCaseBase {
  BeaconViewCase(
    this._beaconRepository,
    this._forwardRepository,
    this._closureRepository,
    this._archiveRepository,
    this._coordinationRepository,
    this._displayRepository,
    this._inboxRepository,
    this._factCards,
    this._beaconRoomCase,
    this._activityEvents,
    this._realtimeSyncCase, {
    required super.env,
    required super.logger,
    required PresenceRepository presenceRepository,
    BeaconHierarchyRepositoryPort? hierarchyRepository,
  }) : _presence = presenceRepository,
       _hierarchy = hierarchyRepository;

  final BeaconRepository _beaconRepository;

  final ForwardRepository _forwardRepository;

  final ClosureRepository _closureRepository;

  final ArchiveRepository _archiveRepository;

  final CoordinationRepository _coordinationRepository;

  final BeaconDisplayRepository _displayRepository;

  final InboxRepository _inboxRepository;

  final BeaconFactCardRepository _factCards;

  final BeaconThreadsCase _beaconRoomCase;

  final BeaconActivityEventRepository _activityEvents;

  final RealtimeSyncCase _realtimeSyncCase;

  final PresenceRepository _presence;

  final BeaconHierarchyRepositoryPort? _hierarchy;

  static final _epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  /// In-process seen cursors keyed by `userId\\tbeaconId`.
  final Map<String, DateTime> _pinnedFactsSeenAt = {};

  /// The Request's hierarchy (nesting) parent, for the access banner
  /// (#724); no parent when no hierarchy repository is wired.
  Future<BeaconParentReference> fetchParentReference(String beaconId) async =>
      await _hierarchy?.fetchParentReference(beaconId: beaconId) ??
      const BeaconParentReference(state: BeaconParentReferenceState.none);

  Stream<RepositoryEvent<Beacon>> get beaconChanges =>
      _beaconRepository.changes;

  Stream<void> get catchUps => _realtimeSyncCase.catchUps.map((_) {});

  /// A block or unblock either way (this or another session): the Request
  /// may now be unreadable, or its people and messages filtered (#638).
  Stream<void> get blockMarkers => _realtimeSyncCase.blockMarkers.map((_) {});

  Stream<RealtimeEntityChange> get peopleChanges =>
      _realtimeSyncCase.changesFor(
        const {RealtimeEntityKind.relationship, RealtimeEntityKind.profile},
      );

  static String _teamPresenceKey(String beaconId) => 'beacon:$beaconId:team';

  /// Online status for the request header's team face pile (U093): the
  /// presence service reports only peers someone asked for.
  void watchTeamPresence(String beaconId, Set<String> userIds) =>
      _presence.watch(_teamPresenceKey(beaconId), userIds);

  void unwatchTeamPresence(String beaconId) =>
      _presence.unwatch(_teamPresenceKey(beaconId));

  /// Author/steward People-tab watermarks (`people_seen` frames).
  Stream<RealtimeEntityChange> get peopleSeenChanges =>
      _realtimeSyncCase.changesFor(const {RealtimeEntityKind.peopleSeen});

  Stream<String> get forwardChanges => _forwardRepository.forwardChanges;

  Stream<HelpOfferEvent> get helpOfferChanges =>
      _forwardRepository.helpOfferChanges;

  Stream<BeaconRoomInvalidation> get beaconRoomInvalidations =>
      _beaconRoomCase.beaconRoomInvalidations;

  /// «Can't help» (#486): declines and tells the author, with [message].
  Future<bool> cantHelp({required String beaconId, String message = ''}) =>
      _inboxRepository.cantHelp(beaconId: beaconId, message: message);

  Future<void> setInboxStatus({
    required String beaconId,
    required InboxItemStatus status,
    String rejectionMessage = '',
  }) => _inboxRepository.setStatus(
    beaconId: beaconId,
    status: status,
    rejectionMessage: rejectionMessage,
  );

  Future<void> deleteBeacon(String beaconId) =>
      _beaconRepository.delete(beaconId);

  Future<BeaconCloseResult> beaconClose({
    required String beaconId,
    required bool expectedRequiresReviewWindow,
  }) async {
    final result = await _closureRepository.beaconClose(beaconId: beaconId);
    await _beaconRepository.refreshAndNotify(beaconId);
    return result;
  }

  /// Sends the cancel mutation only; throws when it fails. The screen
  /// applies the new status at once and does the single refresh read
  /// itself, so a failed read is not a failed cancel (#611).
  Future<void> beaconCancel(String beaconId) async {
    await _closureRepository.beaconCancel(beaconId);
  }

  Future<BeaconExtendReviewResult> beaconExtendReview(String beaconId) async {
    final result = await _closureRepository.beaconExtendReview(beaconId);
    await _beaconRepository.refreshAndNotify(beaconId);
    return result;
  }

  /// Sends the reopen mutation only; throws when it fails. The screen
  /// applies the new status at once and does the single refresh read
  /// itself (#366).
  Future<void> beaconReopen(String beaconId) =>
      _closureRepository.beaconReopen(beaconId);

  /// Sends the close-now mutation only; throws when it fails. Like
  /// [beaconCancel], the screen does the single refresh read (#611).
  Future<void> beaconCloseNow(String beaconId) async {
    await _closureRepository.beaconCloseNow(beaconId);
  }

  Future<void> archiveBeacon(String beaconId) =>
      _archiveRepository.archive(beaconId);

  Future<void> unarchiveBeacon({
    required String beaconId,
    required String userId,
  }) => _archiveRepository.unarchive(beaconId: beaconId, userId: userId);

  Future<bool> forwardOfferHelp({
    required String beaconId,
    String? message,
    List<String>? helpTypes,
    bool notifyHelpOfferListeners = true,
  }) => _forwardRepository.offerHelp(
    beaconId: beaconId,
    message: message,
    helpTypes: helpTypes,
    notifyHelpOfferListeners: notifyHelpOfferListeners,
  );

  Future<bool> forwardWithdraw({
    required String beaconId,
    required String withdrawReason,
    String? message,
  }) => _forwardRepository.withdraw(
    beaconId: beaconId,
    message: message,
    withdrawReason: withdrawReason,
  );

  Future<({BeaconStatus status, DateTime? updatedAt})> setCoordinationResponse({
    required String beaconId,
    required String offerUserId,
    required int responseType,
    required bool inviteToRoom,
    required bool removeFromRoom,
  }) async {
    final result = await _coordinationRepository.setCoordinationResponse(
      beaconId: beaconId,
      offerUserId: offerUserId,
      responseType: responseType,
      inviteToRoom: inviteToRoom,
      removeFromRoom: removeFromRoom,
    );
    _forwardRepository.notifyHelpOfferChanged(HelpOfferInvalidated(beaconId));
    await _beaconRepository.refreshAndNotify(beaconId);
    return result;
  }

  Future<({BeaconStatus status, DateTime? updatedAt})> acceptHelpOffer({
    required String beaconId,
    required String offerUserId,
  }) async {
    final result = await _coordinationRepository.acceptHelpOffer(
      beaconId: beaconId,
      offerUserId: offerUserId,
    );
    _forwardRepository.notifyHelpOfferChanged(HelpOfferInvalidated(beaconId));
    await _beaconRepository.refreshAndNotify(beaconId);
    return result;
  }

  Future<void> setRoleLabel({
    required String beaconId,
    required String offerUserId,
    required String roleLabel,
  }) async {
    await _coordinationRepository.setRoleLabel(
      beaconId: beaconId,
      offerUserId: offerUserId,
      roleLabel: roleLabel,
    );
    _forwardRepository.notifyHelpOfferChanged(HelpOfferInvalidated(beaconId));
    _beaconRoomCase.notifyHelpOfferRoomInvalidation(beaconId);
  }

  Future<({BeaconStatus status, DateTime? updatedAt})> declineHelpOffer({
    required String beaconId,
    required String offerUserId,
    required String reason,
  }) async {
    final result = await _coordinationRepository.declineHelpOffer(
      beaconId: beaconId,
      offerUserId: offerUserId,
      reason: reason,
    );
    _forwardRepository.notifyHelpOfferChanged(HelpOfferInvalidated(beaconId));
    await _beaconRepository.refreshAndNotify(beaconId);
    return result;
  }

  /// «Keep as standby» (#596): the backup offer stays; the author's open
  /// question about it ends.
  Future<void> keepHelpOfferStandby({
    required String beaconId,
    required String offerUserId,
  }) async {
    await _coordinationRepository.keepHelpOfferStandby(
      beaconId: beaconId,
      offerUserId: offerUserId,
    );
    _forwardRepository.notifyHelpOfferChanged(HelpOfferInvalidated(beaconId));
    await _beaconRepository.refreshAndNotify(beaconId);
  }

  /// «Decline remaining offers» (#268): returns how many were declined.
  Future<int> declineRemainingHelpOffers({
    required String beaconId,
    required String reason,
  }) async {
    final declined = await _coordinationRepository.declineRemainingHelpOffers(
      beaconId: beaconId,
      reason: reason,
    );
    _forwardRepository.notifyHelpOfferChanged(HelpOfferInvalidated(beaconId));
    await _beaconRepository.refreshAndNotify(beaconId);
    return declined;
  }

  Future<({BeaconStatus status, DateTime? updatedAt})> removeFromRoom({
    required String beaconId,
    required String offerUserId,
    required String reason,
  }) async {
    final result = await _coordinationRepository.removeFromRoom(
      beaconId: beaconId,
      offerUserId: offerUserId,
      reason: reason,
    );
    _forwardRepository.notifyHelpOfferChanged(HelpOfferInvalidated(beaconId));
    await _beaconRepository.refreshAndNotify(beaconId);
    return result;
  }

  Future<({BeaconStatus status, DateTime? updatedAt})> releaseCommitment({
    required String beaconId,
    required String offerUserId,
    required String reason,
  }) async {
    final result = await _coordinationRepository.releaseCommitment(
      beaconId: beaconId,
      offerUserId: offerUserId,
      reason: reason,
    );
    _forwardRepository.notifyHelpOfferChanged(HelpOfferInvalidated(beaconId));
    await _beaconRepository.refreshAndNotify(beaconId);
    return result;
  }

  Future<void> setBeaconStatus({
    required String beaconId,
    required int status,
  }) async {
    await _coordinationRepository.setBeaconStatus(
      beaconId: beaconId,
      status: status,
    );
    await _beaconRepository.refreshAndNotify(beaconId);
  }

  Future<Beacon> fetchBeaconById(String beaconId) =>
      _beaconRepository.fetchBeaconById(beaconId);

  /// Complete admitted-helper roster (People tab); empty when unavailable.
  Future<List<Profile>> fetchAdmittedHelpers(String beaconId) async {
    try {
      return await _beaconRepository.fetchAdmittedHelpers(beaconId);
    } on Object catch (_) {
      return const [];
    }
  }

  /// Admitted helpers the viewer trusts or worked with before; empty when
  /// unavailable (the showcase strip then simply keeps roster order).
  Future<Set<String>> fetchTeamAcquaintanceIds(String beaconId) async {
    try {
      return await _beaconRepository.fetchTeamAcquaintanceIds(beaconId);
    } on Object catch (_) {
      return const {};
    }
  }

  Future<List<BeaconFactCard>> fetchFactCards(String beaconId) async {
    try {
      return await _factCards.list(beaconId: beaconId);
    } on Object catch (_) {
      return [];
    }
  }

  Future<void> correctFact({
    required String beaconId,
    required String factCardId,
    required String newText,
    required int baseRevisionSeq,
    String? attachmentsJson,
  }) => _factCards.correct(
    beaconId: beaconId,
    factCardId: factCardId,
    newText: newText,
    baseRevisionSeq: baseRevisionSeq,
    attachmentsJson: attachmentsJson,
  );

  Future<void> removeFact({
    required String beaconId,
    required String factCardId,
  }) => _factCards.remove(beaconId: beaconId, factCardId: factCardId);

  Future<void> setFactVisibility({
    required String beaconId,
    required String factCardId,
    required int visibility,
  }) => _factCards.setVisibility(
    beaconId: beaconId,
    factCardId: factCardId,
    visibility: visibility,
  );

  /// Posts to General (`threadItemId: null`) then pins. [messageBody] is the
  /// chat line; [factText] is the already-resolved fact card text.
  ///
  /// [postedMessageId] is a message this form already posted whose pin
  /// failed: it is pinned again instead of posting a second copy (#759).
  Future<void> pinFactFromComposer({
    required String beaconId,
    required String messageBody,
    required String factText,
    required int visibility,
    List<RoomPendingUpload> uploads = const [],
    String? postedMessageId,
  }) async {
    final messageId =
        postedMessageId ??
        await _beaconRoomCase.createMessage(
          beaconId: beaconId,
          body: messageBody,
          uploads: uploads,
        );
    if (messageId == null) {
      throw ArgumentError('messageBody');
    }
    try {
      await _pinComposerFact(
        beaconId: beaconId,
        factText: factText,
        visibility: visibility,
        sourceMessageId: messageId,
      );
    } on BeaconFactAlreadyPinnedException catch (e) {
      // The message was posted for this fact alone, so a fact already on it
      // with our text is this pin, saved on an earlier try whose answer was
      // lost (#759). A different fact (pinned by someone from the message
      // menu) is not ours: say so instead of dropping our text.
      if (await _isFactWithText(
        beaconId: beaconId,
        factCardId: e.factCardId,
        factText: factText,
      )) {
        return;
      }
      rethrow;
    } on Object catch (e, st) {
      _logPinFailure(
        error: e,
        stackTrace: st,
        beaconId: beaconId,
        messageId: messageId,
        visibility: visibility,
        retriedPost: postedMessageId != null,
      );
      throw BeaconFactPinAfterMessageException(
        messageId: messageId,
        cause: e,
      );
    }
  }

  /// [factCardId] is a fact on [beaconId] whose text is [factText]; false
  /// when it cannot be read.
  Future<bool> _isFactWithText({
    required String beaconId,
    required String factCardId,
    required String factText,
  }) async {
    try {
      final cards = await _factCards.list(beaconId: beaconId);
      return cards.any(
        (c) => c.id == factCardId && c.factText.trim() == factText.trim(),
      );
    } on Object {
      return false;
    }
  }

  /// One structured line per failed composer pin (#759): the error, the
  /// request and the posted message, never the fact text or who pinned it.
  void _logPinFailure({
    required Object error,
    required StackTrace stackTrace,
    required String beaconId,
    required String messageId,
    required int visibility,
    required bool retriedPost,
  }) {
    final message = '$error'.replaceAll(RegExp(r'\s+'), ' ').trim();
    logger.warning(
      'fact_pin_failed error_type=${error.runtimeType} '
      'beacon_id=$beaconId '
      'source_message_id=$messageId '
      'visibility=$visibility '
      'retried_post=$retriedPost '
      'message=${message.length <= 300 ? message : '${message.substring(0, 300)}…'}',
      error,
      stackTrace,
    );
  }

  /// Extra tries of the pin when the server turns it away as busy (#759). A
  /// repeat can never pin twice: the server keeps one fact per message, and
  /// a fact already on it counts as pinned above.
  static const _pinBusyRetries = 2;

  Future<void> _pinComposerFact({
    required String beaconId,
    required String factText,
    required int visibility,
    required String sourceMessageId,
  }) async {
    for (var attempt = 0; ; attempt++) {
      try {
        await _factCards.pin(
          beaconId: beaconId,
          factText: factText,
          visibility: visibility,
          sourceMessageId: sourceMessageId,
        );
        return;
      } on RemoteApiRetryLaterException catch (e) {
        if (attempt >= _pinBusyRetries) rethrow;
        await Future<void>.delayed(e.retryAfter);
      }
    }
  }

  DateTime? pinnedFactsSeenAt(String beaconId, String userId) =>
      _pinnedFactsSeenAt[_pinnedFactsSeenKey(userId, beaconId)];

  /// First observation this process: freeze the current max fact timestamp.
  void baselinePinnedFactsIfNeeded({
    required String beaconId,
    required String userId,
    required List<BeaconFactCard> facts,
  }) {
    final key = _pinnedFactsSeenKey(userId, beaconId);
    if (_pinnedFactsSeenAt.containsKey(key)) return;
    _pinnedFactsSeenAt[key] = activePinnedFactsMaxTimestamp(facts) ?? _epoch;
  }

  void markPinnedFactsSeen({
    required String beaconId,
    required String userId,
    required List<BeaconFactCard> facts,
  }) {
    _pinnedFactsSeenAt[_pinnedFactsSeenKey(userId, beaconId)] =
        activePinnedFactsMaxTimestamp(facts) ?? _epoch;
  }

  String _pinnedFactsSeenKey(String userId, String beaconId) =>
      '$userId\t$beaconId';

  /// Room API; returns empty when caller is not allowed (e.g. no room access).
  Future<List<BeaconParticipant>> fetchRoomParticipants(String beaconId) async {
    try {
      return await _beaconRoomCase.fetchParticipants(beaconId);
    } on Object catch (_) {
      return [];
    }
  }

  /// Latest private room state slice; `null` when the viewer cannot use the room API.
  Future<CoordinationItem?> fetchOpenCoordinationBlocker(
    String beaconId,
  ) async {
    try {
      return await _beaconRoomCase.fetchOpenCoordinationBlocker(beaconId);
    } on Object catch (_) {
      return null;
    }
  }

  /// The room state for a background refresh of a loaded request. Unlike
  /// [fetchRoomStateIfAllowed], a failure (e.g. 1704 "database busy") is
  /// rethrown, so the caller can keep the room state it already shows instead
  /// of blanking the next step (B079, review of #514).
  Future<BeaconRoomState?> fetchRoomStateOrThrow(String beaconId) =>
      _beaconRoomCase.fetchBeaconRoomState(beaconId);

  Future<BeaconRoomState?> fetchRoomStateIfAllowed(String beaconId) async {
    try {
      return await _beaconRoomCase.fetchBeaconRoomState(beaconId);
    } on Object catch (_) {
      return null;
    }
  }

  /// Room coordination activity timeline; empty when caller cannot use room APIs.
  Future<List<BeaconActivityEvent>> fetchRoomActivityEvents(
    String beaconId,
  ) async {
    try {
      return await _activityEvents.list(beaconId: beaconId);
    } on Object catch (_) {
      return [];
    }
  }

  Future<List<HelpOfferRowRecord>> fetchHelpOffersWithCoordination({
    required String beaconId,
  }) => _coordinationRepository.fetchHelpOffersWithCoordination(
    beaconId: beaconId,
  );

  /// The viewer's own offer (any status) — see
  /// [CoordinationRepository.fetchMyHelpOffer].
  Future<HelpOfferRowRecord?> fetchMyHelpOffer(String beaconId) =>
      _coordinationRepository.fetchMyHelpOffer(beaconId: beaconId);

  Future<DateTime> markPeopleSeen(String beaconId) =>
      _coordinationRepository.markBeaconPeopleSeen(beaconId);

  Future<BeaconDisplayStatusDto?> fetchDisplayStatus(String beaconId) async {
    final rows = await _displayRepository.fetchDisplayStatuses([beaconId]);
    if (rows.isEmpty) return null;
    return rows.first;
  }

  Future<
    ({
      InboxItemStatus? status,
      InboxProvenance provenance,
      String latestNotePreview,
    })
  >
  fetchInboxContextForBeacon(String beaconId) =>
      _inboxRepository.fetchInboxContextForBeacon(beaconId);

  Future<List<ForwardEdge>> fetchMyForwardEdges({
    required String beaconId,
    required String myUserId,
  }) => _forwardRepository.fetchMyForwardEdges(
    beaconId: beaconId,
    myUserId: myUserId,
  );

  /// All forward edges on the beacon, newest first (`ForwardEdgesFetch`: `order_by: created_at desc`).
  Future<List<ForwardEdge>> fetchForwardEdgesForBeacon(String beaconId) =>
      _forwardRepository.fetchEdges(beaconId: beaconId);

  Future<BeaconInvolvementData> fetchBeaconInvolvement({
    required String beaconId,
  }) => _forwardRepository.fetchBeaconInvolvement(beaconId: beaconId);

  /// Involvement for a Request already loaded. Skips the beacon re-read
  /// [fetchBeaconInvolvement] does for callers that don't have one.
  Future<BeaconInvolvementData> fetchInvolvementForBeacon(Beacon beacon) =>
      _forwardRepository.fetchInvolvementForBeacon(beacon);

  Future<Map<String, List<String>>> fetchForwardReasonsByBeacon(
    String beaconId,
  ) => _forwardRepository.fetchReasonsByBeacon(beaconId: beaconId);

  Future<bool> currentUserHasForwardedBeacon(String beaconId) =>
      _forwardRepository.currentUserHasForwardedBeacon(beaconId);

  Future<void> publishBeacon(String beaconId) async {
    await _beaconRepository.publishDraft(beaconId);
    await _beaconRepository.refreshAndNotify(beaconId);
  }

  void notifyBeaconUpdated(Beacon beacon) =>
      _beaconRepository.notifyUpdated(beacon);

  /// Final-check snapshot when the Request is wrapping up.
  ///
  /// [status] is the status of a Request just read. Passing it skips another
  /// beacon fetch; without it the status is read first.
  Future<ClosureState?> fetchClosureStateIfReviewOpen(
    String beaconId, {
    BeaconStatus? status,
  }) async {
    final resolved = status ?? (await fetchBeaconById(beaconId)).status;
    if (resolved != BeaconStatus.reviewOpen) return null;
    return _closureRepository.fetchState(beaconId);
  }
}
