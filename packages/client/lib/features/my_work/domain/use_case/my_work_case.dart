import 'dart:async';

import 'package:injectable/injectable.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/coordination_responsibility.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/domain/use_case/use_case_base.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/beacon_room/data/repository/beacon_room_hints_repository.dart';
import 'package:tentura/features/beacon_room/domain/use_case/beacon_room_case.dart';
import 'package:tentura/features/coordination_item/domain/use_case/coordination_item_case.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/help_offer_event.dart';

import '../../data/repository/my_work_repository.dart';
import '../derive_my_work_cards.dart';
import '../entity/my_work_card_view_model.dart';
import '../entity/my_work_desk_load_types.dart';

@singleton
final class MyWorkCase extends UseCaseBase {
  MyWorkCase(
    this._repository,
    this._forwardRepository,
    this._beaconRepository,
    this._coordinationItemCase,
    this._beaconRoomCase,
    this._roomHints, {
    required super.env,
    required super.logger,
  });

  final MyWorkRepository _repository;

  final ForwardRepository _forwardRepository;

  final BeaconRepository _beaconRepository;

  final CoordinationItemCase _coordinationItemCase;

  final BeaconRoomCase _beaconRoomCase;

  final BeaconRoomHintsRepository _roomHints;

  Stream<RepositoryEvent<Beacon>> get beaconChanges => _beaconRepository.changes;

  Stream<HelpOfferEvent> get helpOfferChanges => _forwardRepository.helpOfferChanges;

  Stream<String> get forwardCompleted => _forwardRepository.forwardCompleted;

  Stream<String> get readWatermarkChanges => _beaconRoomCase.readWatermarkChanges;

  Future<MyWorkInitResult> fetchInit({required String userId}) =>
      _repository.fetchInit(userId: userId);

  Future<MyWorkClosedResult> fetchClosed({required String userId}) =>
      _repository.fetchClosed(userId: userId);

  Future<MyWorkDeskInitLoad> loadDeskInit({required String userId}) async {
    final init = await _repository.fetchInit(userId: userId);
    final nonArchived = buildNonArchivedViewModels(
      authoredNonClosed: init.authoredNonClosed,
      helpOfferedNonClosed: init.helpOfferedNonClosed,
    ).map((c) {
      final at = init.lastItemDiscussionMessageAtByBeaconId[c.beaconId];
      return at == null
          ? c
          : c.copyWith(lastCoordinationItemMessageAt: at);
    }).toList();
    final enriched = await _enrichDeskCards(nonArchived);
    return (
      nonArchivedCards: enriched,
      authoredClosedIdHints: init.authoredClosedIds,
      helpOfferedClosedIdHints: init.helpOfferedClosedIds,
    );
  }

  Future<MyWorkDeskClosedLoad> loadDeskClosed({required String userId}) async {
    final closed = await _repository.fetchClosed(userId: userId);
    final archived = buildArchivedViewModels(
      authoredClosed: closed.authoredClosed,
      helpOfferedClosed: closed.helpOfferedClosed,
    );
    final enriched = await _enrichDeskCards(archived);
    return (archivedCards: enriched);
  }

  Future<bool> currentUserHasForwardedBeacon(String beaconId) =>
      _forwardRepository.currentUserHasForwardedBeacon(beaconId);

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
          return last == null
              ? card
              : card.copyWith(lastActivityEvent: last);
        }(),
    ];
  }

  Future<List<MyWorkCardViewModel>> attachResponsibilityCounts(
    List<MyWorkCardViewModel> cards,
  ) async {
    if (cards.isEmpty) {
      return cards;
    }
    final byBeacon = await _coordinationItemCase.fetchResponsibilityBatch(
      cards.map((c) => c.beaconId).toList(),
    );
    return [
      for (final card in cards)
        card.copyWith(
          youResponsibility: byBeacon[card.beaconId] ??
              CoordinationResponsibility(beaconId: card.beaconId),
        ),
    ];
  }

  Future<List<MyWorkCardViewModel>> _enrichDeskCards(
    List<MyWorkCardViewModel> cards,
  ) async {
    if (cards.isEmpty) {
      return cards;
    }
    final withLastEvents = await attachLastActivityEvents(cards);
    final withResponsibility =
        await attachResponsibilityCounts(withLastEvents);
    final withHints = await _applyRoomInboxSubtitles(withResponsibility);
    return _withAuthorForwardFlags(withHints);
  }

  Future<List<MyWorkCardViewModel>> _applyRoomInboxSubtitles(
    List<MyWorkCardViewModel> cards,
  ) async {
    if (cards.isEmpty) {
      return cards;
    }
    final hints = await _roomHints.fetchByBeaconIds(
      cards.map((c) => c.beaconId),
    );
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
          if (h.currentLineSnippet.isNotEmpty) {
            parts.add(h.currentLineSnippet);
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
          if (parts.isEmpty) return c;
          return c.copyWith(roomInboxSubtitle: parts.join(' · '));
        }(),
    ];
  }

  Future<List<MyWorkCardViewModel>> _withAuthorForwardFlags(
    List<MyWorkCardViewModel> cards,
  ) async {
    final needsFlag = cards
        .where((c) => c.kind != MyWorkCardKind.authoredDraft)
        .toList();
    if (needsFlag.isEmpty) {
      return cards;
    }
    final results = await Future.wait(
      needsFlag.map(
        (c) => currentUserHasForwardedBeacon(c.beaconId),
      ),
    );
    final map = <String, bool>{
      for (var i = 0; i < needsFlag.length; i++)
        needsFlag[i].beaconId: results[i],
    };
    return [
      for (final c in cards)
        c.kind == MyWorkCardKind.authoredDraft
            ? c
            : c.copyWith(authorHasForwardedOnce: map[c.beaconId] ?? false),
    ];
  }
}
