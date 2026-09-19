import 'dart:async';

import 'package:injectable/injectable.dart';

import 'package:tentura/data/service/bookkeeping_refresh_signal.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_clear.dart';
import 'package:tentura/domain/attention/entity/my_work_beacon_attention.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/domain/use_case/use_case_base.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_room_hints_repository.dart';
import 'package:tentura/features/beacon_threads/domain/entity/beacon_room_invalidation.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/help_offer_event.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_room_card_hints.dart';

import '../../data/repository/archive_repository.dart';
import '../../data/repository/my_work_repository.dart';
import 'package:tentura/features/beacon_view/data/repository/beacon_display_repository.dart';
import 'package:tentura/features/evaluation/data/repository/evaluation_repository.dart';
import 'package:tentura/features/evaluation/domain/entity/review_window_info.dart';
import 'package:tentura/domain/entity/beacon_display_status_dto.dart';
import '../derive_my_work_cards.dart';
import '../entity/my_work_card_view_model.dart';
import '../entity/my_work_desk_load_types.dart';
import '../entity/my_work_fetch_types.dart';
import '../port/my_work_desk_preferences_port.dart';

@singleton
final class MyWorkCase extends UseCaseBase {
  static const _maxAttentionIdsPerRequest = 500;

  MyWorkCase(
    this._repository,
    this._archiveRepository,
    this._forwardRepository,
    this._beaconRepository,
    this._beaconRoomCase,
    this._roomHints,
    this._deskPreferences,
    this._displayRepository,
    this._evaluationRepository,
    this._realtimeSyncCase,
    this._bookkeepingRefreshSignal,
    this._attentionCase, {
    required super.env,
    required super.logger,
  });

  final MyWorkRepository _repository;

  final ArchiveRepository _archiveRepository;

  final ForwardRepository _forwardRepository;

  final BeaconRepository _beaconRepository;

  final BeaconThreadsCase _beaconRoomCase;

  final BeaconRoomHintsRepository _roomHints;

  final MyWorkDeskPreferencesPort _deskPreferences;
  final BeaconDisplayRepository _displayRepository;
  final EvaluationRepository _evaluationRepository;
  final RealtimeSyncCase _realtimeSyncCase;

  final BookkeepingRefreshSignal _bookkeepingRefreshSignal;

  final AttentionCase _attentionCase;

  Stream<RepositoryEvent<Beacon>> get beaconChanges =>
      _beaconRepository.changes;

  Stream<HelpOfferEvent> get helpOfferChanges =>
      _forwardRepository.helpOfferChanges;

  Stream<void> get reviewPackageChanges =>
      _evaluationRepository.reviewPackageChanges;

  Stream<String> get forwardChanges => _forwardRepository.forwardChanges;

  Stream<String> get readWatermarkChanges =>
      _beaconRoomCase.readWatermarkChanges;

  Stream<String> get deskRelevantChanges => _beaconRoomCase.deskRelevantChanges;

  Stream<BeaconRoomInvalidation> get deskRelevantInvalidations =>
      _beaconRoomCase.deskRelevantInvalidations;

  Stream<void> get bookkeepingRefresh => _bookkeepingRefreshSignal.stream;

  Stream<void> get catchUps => _realtimeSyncCase.catchUps.map((_) {});

  Future<MyWorkInitResult> fetchInit({required String userId}) async {
    final obligationBeaconIds = await _attentionCase.liveObligationBeacons();
    return _repository.fetchInit(
      userId: userId,
      obligationBeaconIds: obligationBeaconIds.toList(),
    );
  }

  Future<MyWorkArchivedResult> fetchArchived({required String userId}) =>
      _repository.fetchArchived(userId: userId);

  Future<void> archiveBeacon({
    required String beaconId,
    required String userId,
  }) async {
    await _archiveRepository.archive(beaconId);
    // Notify mounted desk (e.g. under Home while request detail is on root stack).
    _bookkeepingRefreshSignal.notify();
  }

  Future<void> unarchiveBeacon({
    required String beaconId,
    required String userId,
  }) => _archiveRepository.unarchive(beaconId: beaconId, userId: userId);

  Future<MyWorkDeskInitLoad> loadDeskInit({required String userId}) async {
    final init = await fetchInit(userId: userId);
    final obligationBeacons = init.obligationBeacons;
    final nonArchived = buildNonArchivedViewModels(
      authoredNonArchived: init.authoredNonArchived,
      helpOfferedNonArchived: init.helpOfferedNonArchived,
      obligationBeacons: obligationBeacons,
    );
    final enriched = await _enrichDeskCards(nonArchived);
    return (
      nonArchivedCards: enriched,
      archivedCountHint: init.archivedCountHint,
    );
  }

  Future<List<MyWorkCardViewModel>> loadReviewWindows(
    List<MyWorkCardViewModel> cards, {
    required String userId,
  }) async {
    final reviewOpenIds = [
      for (final c in cards)
        if (c.beacon.status == BeaconStatus.reviewOpen) c.beaconId,
    ];
    if (reviewOpenIds.isEmpty) {
      return cards;
    }
    final windows = await _evaluationRepository.fetchReviewWindowStatuses(
      reviewOpenIds,
    );
    final windowByBeacon = {for (final w in windows) w.beaconId: w};
    return [
      for (final card in cards)
        if (card.beacon.status != BeaconStatus.reviewOpen)
          card
        else
          _withReviewWindow(card, windowByBeacon[card.beaconId]),
    ];
  }

  MyWorkCardViewModel _withReviewWindow(
    MyWorkCardViewModel card,
    ReviewWindowInfo? window,
  ) {
    final package = deriveMyWorkReviewPackageState(
      beaconStatus: card.beacon.status,
      review: window,
    );
    return card.copyWith(
      reviewPackageState: package,
      reviewAllRequiredSent: window?.allRequiredSent ?? false,
      showReviewCta: myWorkReviewPackageNeedsAction(package),
      showCloseNowCta:
          card.showCloseNowCta ||
          (card.role == MyWorkCardRole.authored &&
              window?.canCloseNow == true),
    );
  }

  Future<Map<String, MyWorkBeaconAttention>> loadMyWorkAttention(
    Set<String> beaconIds,
  ) async {
    if (beaconIds.isEmpty) {
      return const {};
    }
    final ids = beaconIds.toList(growable: false);
    final byBeacon = <String, MyWorkBeaconAttention>{};
    for (
      var offset = 0;
      offset < ids.length;
      offset += _maxAttentionIdsPerRequest
    ) {
      final nextOffset = offset + _maxAttentionIdsPerRequest;
      final end = nextOffset < ids.length ? nextOffset : ids.length;
      final rows = await _attentionCase.myWorkAttention(
        ids.sublist(offset, end).toSet(),
      );
      for (final row in rows) {
        byBeacon[row.beaconId] = row;
      }
    }
    return byBeacon;
  }

  Future<void> markSeenForBeacon(String beaconId) =>
      _attentionCase.markSeenForBeacon(beaconId);

  /// Clears one optional event — the clear axis (D02/U10b), not `markSeen`.
  ///
  /// There is no settlement counterpart: generic obligation settlement was
  /// removed in U07b and the server refuses it. Obligations end only through
  /// their source transitions (D04).
  ///
  /// R6 — the result is **returned**. Dropping it on the floor made a
  /// `skipped` and a `denied` answer look exactly like success, so a refusal
  /// left the row hidden and the card dark over live attention.
  Future<AttentionClearResult> clearReceipt(String receiptId) =>
      _attentionCase.clearReceipt(receiptId: receiptId);

  /// A Request whose surface or state changed and has to be re-read (U13c).
  Stream<String> get requestInvalidations => _attentionCase.requestInvalidations;

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
    final withHints = _applyRoomInboxSubtitles(withLastEvents, hints);
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
