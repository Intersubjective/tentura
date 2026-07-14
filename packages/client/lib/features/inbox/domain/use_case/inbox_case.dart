import 'dart:async';

import 'package:injectable/injectable.dart';
import 'package:rxdart/rxdart.dart';

import 'package:tentura/data/service/bookkeeping_refresh_signal.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/domain/use_case/use_case_base.dart';
import 'package:tentura/features/beacon_room/domain/use_case/beacon_room_case.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/help_offer_event.dart';

import '../../data/repository/inbox_repository.dart';
import '../entity/inbox_item.dart';
import '../enum.dart';

@singleton
final class InboxCase extends UseCaseBase {
  InboxCase(
    this._repository,
    this._beaconRoomCase,
    this._forwardRepository,
    this._realtimeSyncCase,
    this._bookkeepingRefreshSignal, {
    required super.env,
    required super.logger,
  });

  final InboxRepository _repository;

  final BeaconRoomCase _beaconRoomCase;
  final ForwardRepository _forwardRepository;
  final RealtimeSyncCase _realtimeSyncCase;

  final BookkeepingRefreshSignal _bookkeepingRefreshSignal;

  /// Inbox list refresh after local writes or session read-watermark changes.
  Stream<void> get localMutations => MergeStream<void>([
    _repository.localMutations,
    _beaconRoomCase.readWatermarkChanges.map((_) {}),
    _bookkeepingRefreshSignal.stream,
  ]);

  Stream<HelpOfferEvent> get helpOfferChanges =>
      _forwardRepository.helpOfferChanges;

  Stream<String> get forwardCommandCompleted =>
      _forwardRepository.forwardCommandCompleted;

  Stream<String> get deskRelevantChanges => MergeStream<String>([
    _beaconRoomCase.deskRelevantChanges,
    _forwardRepository.forwardChanges,
    _forwardRepository.helpOfferChanges.map((event) => event.beaconId),
    _realtimeSyncCase
        .changesFor(const {
          RealtimeEntityKind.inboxItem,
          RealtimeEntityKind.beacon,
          RealtimeEntityKind.roomMessage,
          RealtimeEntityKind.roomReaction,
          RealtimeEntityKind.roomPoll,
          RealtimeEntityKind.participant,
          RealtimeEntityKind.factCard,
          RealtimeEntityKind.activityEvent,
          RealtimeEntityKind.coordinationItem,
          RealtimeEntityKind.roomSeen,
        })
        .map((change) => change.aggregateId),
  ]);

  Stream<void> get catchUps => _realtimeSyncCase.catchUps.map((_) {});

  Future<List<InboxItem>> fetch({required String userId}) =>
      _repository.fetch(userId: userId);

  Future<void> setStatus({
    required String beaconId,
    required InboxItemStatus status,
    String rejectionMessage = '',
  }) => _repository.setStatus(
    beaconId: beaconId,
    status: status,
    rejectionMessage: rejectionMessage,
  );

  Future<void> dismissTombstone({
    required String beaconId,
    DateTime? dismissedAt,
  }) => _repository.dismissTombstone(
    beaconId: beaconId,
    dismissedAt: dismissedAt,
  );

  int resolveRoomUnread({
    required String beaconId,
    required int serverCount,
    required DateTime? serverSeenAt,
  }) => _beaconRoomCase.resolveUnread(
    beaconId: beaconId,
    serverCount: serverCount,
    serverSeenAt: serverSeenAt,
  );
}
