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

  /// Inbox list refresh after local writes.
  late final Stream<void> localMutations = MergeStream<void>([
    _repository.localMutations,
    _bookkeepingRefreshSignal.stream,
    _blockCase.changes.map((_) {}),
  ]).doOnData((_) => _invalidateRefreshRead()).asBroadcastStream();

  /// A Request's Discussion read watermark moved (this or another session of
  /// the reader): its card's unread is recomputed locally, never refetched.
  Stream<String> get readWatermarkChanges =>
      _beaconRoomCase.readWatermarkChanges;

  Stream<HelpOfferEvent> get helpOfferChanges =>
      _forwardRepository.helpOfferChanges;

  late final Stream<String> forwardCommandCompleted = _forwardRepository
      .forwardCommandCompleted
      .doOnData((_) => _invalidateRefreshRead())
      .asBroadcastStream();

  late final Stream<String> deskRelevantChanges = MergeStream<String>([
    _beaconRoomCase.deskRelevantChanges,
    _forwardRepository.forwardChanges,
    _forwardRepository.helpOfferChanges.map((event) => event.beaconId),
    // roomSeenPeer is presence-only and room_seen is the viewer's read
    // cursor (see BeaconThreadsCase); neither is a desk refetch.
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
        })
        .map((change) => change.aggregateId),
  ]).doOnData((_) => _invalidateRefreshRead()).asBroadcastStream();

  late final Stream<void> catchUps = _realtimeSyncCase.catchUps
      .map((_) {})
      .doOnData((_) => _invalidateRefreshRead())
      .asBroadcastStream();

  final _refreshReads = <String, Future<List<InboxItem>>>{};

  void _invalidateRefreshRead() => _refreshReads.clear();

  /// Background observers share this refresh epoch's result, including after
  /// it completes. The next hint, catch-up or local write starts a fresh epoch.
  /// Explicit fetches and [forceFresh] bypass sharing.
  Future<List<InboxItem>> fetch({
    required String userId,
    bool forceFresh = false,
    bool shareRefresh = false,
  }) {
    if (shareRefresh && !forceFresh) {
      return _refreshReads.putIfAbsent(
        userId,
        () => _repository.fetch(userId: userId),
      );
    }
    _invalidateRefreshRead();
    return _repository.fetch(userId: userId);
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

  /// Undo of [recordInviteDeclineNote]: the invitation is pending again, so
  /// the row is no longer a rejected one. Best-effort, like the write it
  /// undoes; an empty [message] means nothing was written.
  Future<void> forgetInviteDeclineNote({
    required String beaconId,
    required String message,
  }) async {
    if (message.isEmpty) return;
    try {
      await _repository.setStatus(
        beaconId: beaconId,
        status: InboxItemStatus.needsMe,
      );
    } on Object {
      // The invitation is back; a stale note is harmless.
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
