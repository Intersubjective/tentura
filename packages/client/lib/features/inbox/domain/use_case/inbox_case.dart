import 'dart:async';

import 'package:injectable/injectable.dart';
import 'package:rxdart/rxdart.dart';

import 'package:tentura/data/service/bookkeeping_refresh_signal.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/domain/use_case/use_case_base.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/features/block/domain/use_case/block_case.dart';
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
    this._bookkeepingRefreshSignal,
    this._blockCase, {
    required super.env,
    required super.logger,
  });

  final InboxRepository _repository;

  final BeaconThreadsCase _beaconRoomCase;
  final ForwardRepository _forwardRepository;
  final RealtimeSyncCase _realtimeSyncCase;

  final BookkeepingRefreshSignal _bookkeepingRefreshSignal;
  final BlockCase _blockCase;

  /// Inbox list refresh after local writes or session read-watermark changes.
  Stream<void> get localMutations => MergeStream<void>([
    _repository.localMutations,
    _beaconRoomCase.readWatermarkChanges.map((_) {}),
    _bookkeepingRefreshSignal.stream,
    _blockCase.changes.map((_) {}),
  ]);

  Stream<HelpOfferEvent> get helpOfferChanges =>
      _forwardRepository.helpOfferChanges;

  Stream<String> get forwardCommandCompleted =>
      _forwardRepository.forwardCommandCompleted;

  Stream<String> get deskRelevantChanges => MergeStream<String>([
    _beaconRoomCase.deskRelevantChanges,
    _forwardRepository.forwardChanges,
    _forwardRepository.helpOfferChanges.map((event) => event.beaconId),
    // roomSeenPeer is presence-only; omitted from desk refetch ids (see BeaconThreadsCase).
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

  /// The read started in this event-loop turn, if any.
  ({String userId, Future<List<InboxItem>> read})? _turnRead;
  int _turnReadEpoch = 0;
  int? _sharedReadEpoch;

  /// Inbox lists mounted together (Home's and Watching's) share one turn's read
  /// while it is still open on this case. [forceFresh] skips sharing.
  Future<List<InboxItem>> fetch({
    required String userId,
    bool forceFresh = false,
  }) {
    if (!forceFresh) {
      final shared = _turnRead;
      if (shared != null &&
          shared.userId == userId &&
          _sharedReadEpoch == _turnReadEpoch) {
        return shared.read;
      }
    }
    final epoch = ++_turnReadEpoch;
    final turnRead = (userId: userId, read: _repository.fetch(userId: userId));
    _turnRead = turnRead;
    _sharedReadEpoch = epoch;
    Timer.run(() {
      if (identical(_turnRead, turnRead)) _turnRead = null;
      if (_sharedReadEpoch == epoch) _sharedReadEpoch = null;
    });
    return turnRead.read;
  }

  Future<({List<InboxItem> page, int totalCount})>
  fetchActivityOffersFirstPage({
    required String userId,
    int limit = InboxRepository.activityOffersPageSize,
  }) => _repository.fetchActivityOffersFirstPage(userId: userId, limit: limit);

  Future<List<InboxItem>> fetchActivityOffersPage({
    required String userId,
    required DateTime cursorAt,
    required String cursorBeaconId,
    int limit = InboxRepository.activityOffersPageSize,
  }) => _repository.fetchActivityOffersPage(
    userId: userId,
    cursorAt: cursorAt,
    cursorBeaconId: cursorBeaconId,
    limit: limit,
  );

  Future<int> fetchOpenForwardsCount() => _repository.fetchOpenForwardsCount();

  Future<InboxItem?> fetchOpenForwardForBeacon({
    required String userId,
    required String beaconId,
  }) => _repository.fetchOpenForwardForBeacon(
    userId: userId,
    beaconId: beaconId,
  );

  Future<List<InboxItem>> fetchInboxItemsForBeacons({
    required String userId,
    required List<String> beaconIds,
  }) => _repository.fetchInboxItemsForBeacons(
    userId: userId,
    beaconIds: beaconIds,
  );

  Future<void> setStatus({
    required String beaconId,
    required InboxItemStatus status,
    String rejectionMessage = '',
  }) => _repository.setStatus(
    beaconId: beaconId,
    status: status,
    rejectionMessage: rejectionMessage,
  );

  /// After «Не смогу» on an author invite (#664) declined it: keeps the
  /// rejection dialog's optional [message] on the inbox row, the way «Не могу
  /// помочь» does. Best-effort — the decline itself already went through, so
  /// a failed write is swallowed; an empty [message] writes nothing.
  Future<void> recordInviteDeclineNote({
    required String beaconId,
    required String message,
  }) async {
    if (message.isEmpty) return;
    try {
      await _repository.setStatus(
        beaconId: beaconId,
        status: InboxItemStatus.rejected,
        rejectionMessage: message,
      );
    } on Object {
      // The decline itself succeeded; the note is best-effort.
    }
  }

  /// «Can't help» (#486): the author is told, with [message]. False when
  /// the server refused (nothing to answer any more).
  Future<bool> cantHelp({required String beaconId, String message = ''}) =>
      _repository.cantHelp(beaconId: beaconId, message: message);

  Future<void> dismiss({required String beaconId, String privateNote = ''}) =>
      _repository.dismiss(beaconId: beaconId, privateNote: privateNote);

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
