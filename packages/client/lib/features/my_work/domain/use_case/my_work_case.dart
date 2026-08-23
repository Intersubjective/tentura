import 'dart:async';

import 'package:injectable/injectable.dart';

import 'package:tentura/data/service/bookkeeping_refresh_signal.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/domain/use_case/use_case_base.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_room_hints_repository.dart';
import 'package:tentura/features/beacon_threads/domain/entity/beacon_room_invalidation.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/features/coordination_item/domain/use_case/coordination_item_case.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/help_offer_event.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_room_card_hints.dart';

import '../../data/repository/archive_repository.dart';
import '../../data/repository/my_work_repository.dart';
import 'package:tentura/features/beacon_view/data/repository/beacon_display_repository.dart';
import 'package:tentura/features/evaluation/data/repository/evaluation_repository.dart';
import 'package:tentura/domain/entity/beacon_display_status_dto.dart';
import '../derive_my_work_cards.dart';
import '../entity/my_work_card_view_model.dart';
import '../entity/my_work_desk_load_types.dart';
import '../port/my_work_desk_preferences_port.dart';

@singleton
final class MyWorkCase extends UseCaseBase {
  MyWorkCase(
    this._repository,
    this._archiveRepository,
    this._forwardRepository,
    this._beaconRepository,
    this._coordinationItemCase,
    this._beaconRoomCase,
    this._roomHints,
    this._deskPreferences,
    this._displayRepository,
    this._evaluationRepository,
    this._realtimeSyncCase,
    this._bookkeepingRefreshSignal, {
    required super.env,
    required super.logger,
  });

  final MyWorkRepository _repository;

  final ArchiveRepository _archiveRepository;

  final ForwardRepository _forwardRepository;

  final BeaconRepository _beaconRepository;

  final CoordinationItemCase _coordinationItemCase;

  final BeaconThreadsCase _beaconRoomCase;

  final BeaconRoomHintsRepository _roomHints;

  final MyWorkDeskPreferencesPort _deskPreferences;
  final BeaconDisplayRepository _displayRepository;
  final EvaluationRepository _evaluationRepository;
  final RealtimeSyncCase _realtimeSyncCase;

  final BookkeepingRefreshSignal _bookkeepingRefreshSignal;

  Stream<RepositoryEvent<Beacon>> get beaconChanges =>
      _beaconRepository.changes;

  Stream<HelpOfferEvent> get helpOfferChanges =>
      _forwardRepository.helpOfferChanges;

  Stream<String> get forwardChanges => _forwardRepository.forwardChanges;

  Stream<String> get readWatermarkChanges =>
      _beaconRoomCase.readWatermarkChanges;

  Stream<String> get deskRelevantChanges => _beaconRoomCase.deskRelevantChanges;

  Stream<BeaconRoomInvalidation> get deskRelevantInvalidations =>
      _beaconRoomCase.deskRelevantInvalidations;

  Stream<void> get bookkeepingRefresh => _bookkeepingRefreshSignal.stream;

  Stream<void> get catchUps => _realtimeSyncCase.catchUps.map((_) {});

  Future<MyWorkInitResult> fetchInit({required String userId}) =>
      _repository.fetchInit(userId: userId);

  Future<MyWorkArchivedResult> fetchArchived({required String userId}) =>
      _repository.fetchArchived(userId: userId);

  Future<void> archiveBeacon({
    required String beaconId,
    required String userId,
  }) async {
    await _archiveRepository.archive(beaconId);
    await _deskPreferences.setFinishedArchiveHintDismissed(userId: userId);
  }

  Future<void> dismissFinishedArchiveHint({required String userId}) =>
      _deskPreferences.setFinishedArchiveHintDismissed(userId: userId);

  Future<void> unarchiveBeacon({
    required String beaconId,
    required String userId,
  }) => _archiveRepository.unarchive(beaconId: beaconId, userId: userId);

  Future<MyWorkDeskInitLoad> loadDeskInit({required String userId}) async {
    final init = await _repository.fetchInit(userId: userId);
    final nonArchived =
        buildNonArchivedViewModels(
          authoredNonArchived: init.authoredNonArchived,
          helpOfferedNonArchived: init.helpOfferedNonArchived,
        ).map((c) {
          final at = init.lastItemDiscussionMessageAtByBeaconId[c.beaconId];
          return at == null ? c : c.copyWith(lastCoordinationItemMessageAt: at);
        }).toList();
    final enriched = await _enrichDeskCards(nonArchived);
    final finishedArchiveHintDismissed = await _deskPreferences
        .isFinishedArchiveHintDismissed(userId: userId);
    return (
      nonArchivedCards: enriched,
      archivedCountHint: init.archivedCountHint,
      finishedArchiveHintDismissed: finishedArchiveHintDismissed,
    );
  }

  Future<List<MyWorkCardViewModel>> loadReviewWindows(
    List<MyWorkCardViewModel> cards, {
    required String userId,
  }) async {
    final reviewOpenAuthorIds = [
      for (final c in cards)
        if (c.role == MyWorkCardRole.authored &&
            c.beacon.status == BeaconStatus.reviewOpen)
          c.beaconId,
    ];
    if (reviewOpenAuthorIds.isEmpty) {
      return cards;
    }
    final windows = await _evaluationRepository.fetchReviewWindowStatuses(
      reviewOpenAuthorIds,
    );
    final canCloseByBeacon = {
      for (final w in windows)
        if (w.canCloseNow == true) w.beaconId: true,
    };
    return [
      for (final card in cards)
        canCloseByBeacon[card.beaconId] == true &&
                card.role == MyWorkCardRole.authored
            ? card.copyWith(showCloseNowCta: true)
            : card,
    ];
  }

  Future<MyWorkDeskArchivedLoad> loadDeskArchived({
    required String userId,
  }) async {
    final archivedResult = await _repository.fetchArchived(userId: userId);
    final archived = buildArchivedViewModels(
      authoredArchived: archivedResult.authoredArchived,
      helpOfferedArchived: archivedResult.helpOfferedArchived,
    );
    final enriched = await _enrichDeskCards(archived);
    return (archivedCards: enriched);
  }

  Future<List<MyWorkCardViewModel>> attachLastActivityEvents(
    List<MyWorkCardViewModel> cards,
  ) async {
    if (cards.isEmpty) {
      return cards;
    }
    final byBeacon = await _repository.fetchLastActivityEventsByBeaconId(
      cards.map((c) => c.beaconId).toList(),
    );
    return [
      for (final card in cards)
        () {
          final last = byBeacon[card.beaconId];
          return last == null ? card : card.copyWith(lastActivityEvent: last);
        }(),
    ];
  }

  Future<List<MyWorkCardViewModel>> attachResponsibilityCounts(
    List<MyWorkCardViewModel> cards, {
    Map<String, InboxRoomCardHints>? roomHints,
  }) async {
    if (cards.isEmpty) {
      return cards;
    }
    final ids = roomHints == null
        ? cards.map((c) => c.beaconId).toList()
        : [
            for (final c in cards)
              if (roomHints[c.beaconId]?.isRoomMember ?? false) c.beaconId,
          ];
    if (ids.isEmpty) {
      return cards;
    }
    final byBeacon = await _coordinationItemCase.fetchResponsibilityBatch(
      ids,
    );
    return [
      for (final card in cards)
        if (byBeacon.containsKey(card.beaconId))
          card.copyWith(youResponsibility: byBeacon[card.beaconId])
        else
          card,
    ];
  }

  Future<List<MyWorkCardViewModel>> _enrichDeskCards(
    List<MyWorkCardViewModel> cards,
  ) async {
    if (cards.isEmpty) {
      return cards;
    }
    final withLastEvents = await attachLastActivityEvents(cards);
    final hints = await _roomHints.fetchByBeaconIds(
      withLastEvents.map((c) => c.beaconId),
    );
    final withResponsibility = await attachResponsibilityCounts(
      withLastEvents,
      roomHints: hints,
    );
    final withHints = _applyRoomInboxSubtitles(withResponsibility, hints);
    return _attachDisplayStatuses(withHints);
  }

  Future<List<MyWorkCardViewModel>> _attachDisplayStatuses(
    List<MyWorkCardViewModel> cards,
  ) async {
    if (cards.isEmpty) return cards;
    final authoredIds = [
      for (final c in cards)
        if (c.role == MyWorkCardRole.authored) c.beaconId,
    ];
    if (authoredIds.isEmpty) return cards;
    final rows = await _displayRepository.fetchDisplayStatuses(authoredIds);
    final byBeacon = {for (final row in rows) row.beaconId: row};
    return [
      for (final card in cards)
        byBeacon.containsKey(card.beaconId)
            ? card.copyWith(displayStatus: byBeacon[card.beaconId])
            : card,
    ];
  }

  List<MyWorkCardViewModel> _applyRoomInboxSubtitles(
    List<MyWorkCardViewModel> cards,
    Map<String, InboxRoomCardHints> hints,
  ) {
    if (cards.isEmpty) {
      return cards;
    }
    return [
      for (final c in cards)
        () {
          final h = hints[c.beaconId];
          if (h == null || !h.isRoomMember) {
            return c;
          }
          final parts = <String>[];
          if (h.myNextMove.isNotEmpty) {
            parts.add(h.myNextMove);
          }
          if (h.roomUnreadCount > 0) {
            final unread = _beaconRoomCase.resolveUnread(
              beaconId: c.beaconId,
              serverCount: h.roomUnreadCount,
              serverSeenAt: h.lastSeenAt,
            );
            if (unread > 0) {
              parts.add('+$unread');
            }
          }
          return c.copyWith(
            roomCurrentLine: h.currentLineSnippet,
            roomOpenBlockerTitle: h.openBlockerTitle,
            roomOpenBlocker: h.openBlocker,
            roomInboxSubtitle: parts.join(' · '),
          );
        }(),
    ];
  }

}
