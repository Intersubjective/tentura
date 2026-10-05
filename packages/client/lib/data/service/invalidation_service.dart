import 'dart:async';
import 'dart:convert';

import 'package:injectable/injectable.dart';
import 'package:meta/meta.dart';
import 'package:rxdart/rxdart.dart';

import 'package:tentura/data/service/remote_api_client/realtime_transport_status.dart';
import 'package:tentura/domain/entity/quoted_fact.dart';
import 'package:tentura/domain/entity/realtime/realtime_catch_up.dart';
import 'package:tentura/domain/entity/realtime/realtime_connection_status.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/entity/realtime/realtime_room_message_paint.dart';
import 'package:tentura/domain/entity/realtime/realtime_seen_peer.dart';
import 'package:tentura/domain/entity/room_message_attachment.dart';
import 'package:tentura/domain/entity/room_message_mention_span.dart';
import 'package:tentura/domain/port/realtime_sync_port.dart';

import 'remote_api_service.dart';

Stream<List<T>> _bufferAfterFirstEvent<T>(
  Stream<T> source,
  Duration window,
) {
  late final StreamController<List<T>> output;
  StreamSubscription<T>? input;
  Timer? timer;
  final pending = <T>[];

  void flush() {
    timer = null;
    if (pending.isEmpty) return;
    output.add(List<T>.of(pending));
    pending.clear();
  }

  output = StreamController<List<T>>(
    onListen: () {
      input = source.listen(
        (event) {
          pending.add(event);
          timer ??= Timer(window, flush);
        },
        onError: output.addError,
        onDone: () {
          timer?.cancel();
          flush();
          unawaited(output.close());
        },
      );
    },
    onPause: () => input?.pause(),
    onResume: () => input?.resume(),
    onCancel: () async {
      timer?.cancel();
      pending.clear();
      await input?.cancel();
    },
  );
  return output.stream;
}

/// Maps the V2 WebSocket wire protocol into the shared domain sync boundary.
///
/// Entity hints identify server-owned projections. They never carry derived
/// state, and bursts are coalesced by `(kind, aggregateId)` before consumers
/// refetch authoritative snapshots.
@Singleton(as: RealtimeSyncPort)
class InvalidationService implements RealtimeSyncPort {
  InvalidationService(RemoteApiService remoteApiService) {
    _messageSubscription = _subscribe(remoteApiService.webSocketMessages);
    _transportSubscription = remoteApiService.realtimeTransportStatus.listen(
      _onTransportStatus,
    );
  }

  /// Unit tests without [RemoteApiService] / WebSocket wiring.
  @visibleForTesting
  InvalidationService.forTesting(
    Stream<Map<String, dynamic>> messages, {
    Stream<RealtimeTransportStatus>? transportStatuses,
  }) {
    _messageSubscription = _subscribe(messages);
    _transportSubscription =
        (transportStatuses ?? const Stream<RealtimeTransportStatus>.empty())
            .listen(_onTransportStatus);
  }

  // Leave enough room to collapse one transaction's trigger burst while
  // preserving the 1.5 s end-to-end connected-delivery budget.
  static const _batchWindow = Duration(milliseconds: 100);
  static const _roomMessageBatchWindow = Duration(milliseconds: 16);

  late final StreamSubscription<Map<String, dynamic>> _messageSubscription;
  late final StreamSubscription<RealtimeTransportStatus> _transportSubscription;

  String? _activeAccountId;
  int _latestConnectionEpoch = 0;
  bool _hasAuthenticatedCurrentAccount = false;

  final _entityChangeController =
      StreamController<RealtimeEntityChange>.broadcast();
  final _catchUpController = StreamController<RealtimeCatchUp>.broadcast();
  final _connectionStatusSubject =
      BehaviorSubject<RealtimeConnectionStatus>.seeded(
        const RealtimeConnectionStatus(
          connectionEpoch: 0,
          phase: RealtimeConnectionPhase.unbound,
        ),
      );

  @override
  late final Stream<RealtimeEntityChange> entityChanges = Rx.merge([
    _bufferAfterFirstEvent(
      _entityChangeController.stream.where(
        (change) => change.kind == RealtimeEntityKind.roomMessage,
      ),
      _roomMessageBatchWindow,
    ).expand(_deduplicateEntityChanges),
    _bufferAfterFirstEvent(
      _entityChangeController.stream.where(
        (change) => change.kind != RealtimeEntityKind.roomMessage,
      ),
      _batchWindow,
    ).expand(_deduplicateEntityChanges),
  ]).asBroadcastStream();

  @override
  late final Stream<RealtimeCatchUp> catchUps = _bufferAfterFirstEvent(
    _catchUpController.stream,
    _batchWindow,
  ).expand(_deduplicateCatchUps).asBroadcastStream();

  @override
  Stream<RealtimeConnectionStatus> get connectionStatuses =>
      _connectionStatusSubject.stream;

  StreamSubscription<Map<String, dynamic>> _subscribe(
    Stream<Map<String, dynamic>> messages,
  ) => messages.listen(_onMessage);

  void _onMessage(Map<String, dynamic> message) {
    if (message['path'] != 'entity_changes') return;
    switch (message['type']) {
      case 'subscription':
        _onInvalidation(message);
      case 'control':
        _onServerControl(message);
    }
  }

  void _onInvalidation(Map<String, dynamic> message) {
    final payload = _normalizeJsonObject(message['payload']);
    if (payload == null) return;
    final id = payload['id'];
    final kind = RealtimeEntityKind.fromWire(payload['entity']);
    final operation = _operationFromWire(payload['event']);
    final actorUserId = payload['actor_user_id'];
    if (id is! String || id.isEmpty || kind == null || operation == null) {
      return;
    }
    if (actorUserId != null && actorUserId is! String) {
      return;
    }
    final childId = _parseChildId(payload['message_id']);
    final paint = _parseRoomMessagePaint(
      kind: kind,
      operation: operation,
      aggregateId: id,
      childId: childId,
      rawMessage: payload['message'],
    );
    final seenPeer = _parseSeenPeer(
      kind: kind,
      seenUserId: payload['seen_user_id'],
      lastSeenAtRaw: payload['last_seen_at'],
    );
    if (kind == RealtimeEntityKind.roomSeenPeer && seenPeer == null) {
      return;
    }
    final lastSeenAtRaw = payload['last_seen_at'];
    final peopleSeenAt =
        kind == RealtimeEntityKind.peopleSeen && lastSeenAtRaw is String
        ? DateTime.tryParse(lastSeenAtRaw)?.toUtc()
        : null;
    if (kind == RealtimeEntityKind.peopleSeen && peopleSeenAt == null) {
      return;
    }

    _entityChangeController.add(
      RealtimeEntityChange(
        kind: kind,
        aggregateId: id,
        operation: operation,
        source: RealtimeChangeSource.serverInvalidation,
        actorUserId: actorUserId as String?,
        childId: childId,
        roomMessagePaint: paint,
        seenPeer: seenPeer,
        peopleSeenAt: peopleSeenAt,
      ),
    );
  }

  void _onServerControl(Map<String, dynamic> message) {
    final payload = _normalizeJsonObject(message['payload']);
    if (payload == null || payload['intent'] != 'catch_up') return;
    final reason = switch (payload['reason']) {
      'pg_listener_recovered' => RealtimeCatchUpReason.pgListenerRecovered,
      'server_requested' ||
      'protocol_change' => RealtimeCatchUpReason.serverRequested,
      _ => null,
    };
    if (reason != null) requestCatchUp(reason);
  }

  void _onTransportStatus(RealtimeTransportStatus transportStatus) {
    if (transportStatus.connectionEpoch < _latestConnectionEpoch) return;

    final accountChanged =
        transportStatus.accountId != null &&
        transportStatus.accountId != _activeAccountId;
    if (transportStatus.connectionEpoch > _latestConnectionEpoch) {
      _latestConnectionEpoch = transportStatus.connectionEpoch;
    }
    if (transportStatus.phase == RealtimeTransportPhase.unbound) {
      _activeAccountId = null;
      _hasAuthenticatedCurrentAccount = false;
    } else if (accountChanged) {
      _activeAccountId = transportStatus.accountId;
      _hasAuthenticatedCurrentAccount = false;
    }

    final status = RealtimeConnectionStatus(
      accountId: transportStatus.accountId,
      connectionEpoch: transportStatus.connectionEpoch,
      phase: _connectionPhase(transportStatus.phase),
    );
    if (_connectionStatusSubject.value != status) {
      _connectionStatusSubject.add(status);
    }

    if (transportStatus.phase != RealtimeTransportPhase.authenticated ||
        transportStatus.accountId == null) {
      return;
    }
    if (_hasAuthenticatedCurrentAccount) {
      _catchUpController.add(
        RealtimeCatchUp(
          accountId: transportStatus.accountId!,
          connectionEpoch: transportStatus.connectionEpoch,
          reason: transportStatus.cause == RealtimeReconnectCause.pongTimeout
              ? RealtimeCatchUpReason.pongTimeout
              : RealtimeCatchUpReason.webSocketReconnected,
        ),
      );
    }
    _hasAuthenticatedCurrentAccount = true;
  }

  @override
  void requestCatchUp(RealtimeCatchUpReason reason) {
    final accountId = _activeAccountId;
    if (accountId == null) return;
    _catchUpController.add(
      RealtimeCatchUp(
        accountId: accountId,
        connectionEpoch: _latestConnectionEpoch,
        reason: reason,
      ),
    );
  }

  static Iterable<RealtimeEntityChange> _deduplicateEntityChanges(
    List<RealtimeEntityChange> batch,
  ) {
    final latestByProjectionKey =
        <
          (RealtimeEntityKind, String, String?, String?, DateTime?),
          RealtimeEntityChange
        >{};
    for (final change in batch) {
      latestByProjectionKey[(
            change.kind,
            change.aggregateId,
            change.roomMessagePaint?.id,
            change.seenPeer?.userId,
            change.peopleSeenAt,
          )] =
          change;
    }
    return latestByProjectionKey.values;
  }

  static String? _parseChildId(Object? raw) =>
      raw is String && raw.isNotEmpty ? raw : null;

  static RealtimeSeenPeer? _parseSeenPeer({
    required RealtimeEntityKind kind,
    required Object? seenUserId,
    required Object? lastSeenAtRaw,
  }) {
    if (kind != RealtimeEntityKind.roomSeenPeer) {
      return null;
    }
    if (seenUserId is! String || seenUserId.isEmpty) {
      return null;
    }
    if (lastSeenAtRaw is! String) {
      return null;
    }
    final lastSeenAt = DateTime.tryParse(lastSeenAtRaw);
    if (lastSeenAt == null) {
      return null;
    }
    return RealtimeSeenPeer(userId: seenUserId, lastSeenAt: lastSeenAt);
  }

  static RealtimeRoomMessagePaint? _parseRoomMessagePaint({
    required RealtimeEntityKind? kind,
    required RealtimeOperation? operation,
    required String aggregateId,
    required String? childId,
    required Object? rawMessage,
  }) {
    if (kind != RealtimeEntityKind.roomMessage ||
        operation != RealtimeOperation.insert ||
        childId == null ||
        rawMessage == null) {
      return null;
    }
    final message = _normalizeJsonObject(rawMessage);
    if (message == null) {
      return null;
    }
    final id = message['id'];
    final beaconId = message['beaconId'];
    final authorId = message['authorId'];
    final body = message['body'];
    final createdAtRaw = message['createdAt'];
    final editedAtRaw = message['editedAt'];
    final mentionsRaw = message['mentions'];
    final threadItemIdRaw = message['threadItemId'];
    final systemMessageKindRaw = message['systemMessageKind'];
    if (systemMessageKindRaw != null && systemMessageKindRaw is! int) {
      return null;
    }
    // A system line may have no author (plan auto-assignment).
    final isSystemLine = systemMessageKindRaw is int;
    if (id is! String ||
        id.isEmpty ||
        beaconId is! String ||
        beaconId.isEmpty ||
        authorId is! String ||
        (authorId.isEmpty && !isSystemLine) ||
        body is! String ||
        createdAtRaw is! String) {
      return null;
    }
    if (id != childId || beaconId != aggregateId) {
      return null;
    }
    final createdAt = DateTime.tryParse(createdAtRaw);
    if (createdAt == null) {
      return null;
    }
    DateTime? editedAt;
    if (editedAtRaw is String) {
      editedAt = DateTime.tryParse(editedAtRaw);
      if (editedAt == null) {
        return null;
      }
    } else if (editedAtRaw != null) {
      return null;
    }
    final mentions = mentionsRaw is List
        ? mentionsRaw.whereType<String>().toList(growable: false)
        : const <String>[];
    final mentionSpansRaw = message['mentionSpans'];
    final mentionSpans = <RoomMessageMentionSpan>[];
    if (mentionSpansRaw != null) {
      if (mentionSpansRaw is! List) return null;
      for (final raw in mentionSpansRaw) {
        if (raw is! Map ||
            raw['userId'] is! String ||
            raw['offset'] is! int ||
            raw['length'] is! int) {
          return null;
        }
        mentionSpans.add(
          RoomMessageMentionSpan(
            userId: raw['userId']! as String,
            offset: raw['offset']! as int,
            length: raw['length']! as int,
          ),
        );
      }
    }
    final threadItemId = threadItemIdRaw is String && threadItemIdRaw.isNotEmpty
        ? threadItemIdRaw
        : null;
    final replyToMessageIdRaw = message['replyToMessageId'];
    final replyToAuthorIdRaw = message['replyToAuthorId'];
    final replyToAuthorTitleRaw = message['replyToAuthorTitle'];
    final replyToBodyExcerptRaw = message['replyToBodyExcerpt'];
    final replyToHasAttachmentsRaw = message['replyToHasAttachments'];
    String? replyToMessageId;
    if (replyToMessageIdRaw != null) {
      if (replyToMessageIdRaw is! String) return null;
      replyToMessageId = replyToMessageIdRaw.isNotEmpty
          ? replyToMessageIdRaw
          : null;
    }
    String? replyToAuthorId;
    if (replyToAuthorIdRaw != null) {
      if (replyToAuthorIdRaw is! String) return null;
      replyToAuthorId = replyToAuthorIdRaw.isNotEmpty
          ? replyToAuthorIdRaw
          : null;
    }
    String? replyToAuthorTitle;
    if (replyToAuthorTitleRaw != null) {
      if (replyToAuthorTitleRaw is! String) return null;
      replyToAuthorTitle = replyToAuthorTitleRaw;
    }
    String? replyToBodyExcerpt;
    if (replyToBodyExcerptRaw != null) {
      if (replyToBodyExcerptRaw is! String) return null;
      replyToBodyExcerpt = replyToBodyExcerptRaw;
    }
    var replyToHasAttachments = false;
    if (replyToHasAttachmentsRaw != null) {
      if (replyToHasAttachmentsRaw is! bool) return null;
      replyToHasAttachments = replyToHasAttachmentsRaw;
    }
    final semanticMarkerRaw = message['semanticMarker'];
    if (semanticMarkerRaw != null && semanticMarkerRaw is! int) {
      return null;
    }
    final systemPayloadRaw = message['systemPayload'];
    if (systemPayloadRaw != null && systemPayloadRaw is! Map) {
      return null;
    }
    final systemPayload = _normalizeJsonObject(systemPayloadRaw);
    final quotedFactRaw = message['quotedFact'];
    if (quotedFactRaw != null && quotedFactRaw is! Map) {
      return null;
    }
    final quotedFact = _parseQuotedFact(quotedFactRaw);
    if (quotedFactRaw != null && quotedFact == null) {
      return null;
    }
    return RealtimeRoomMessagePaint(
      id: id,
      beaconId: beaconId,
      authorId: authorId,
      body: body,
      createdAt: createdAt,
      editedAt: editedAt,
      mentions: mentions,
      mentionSpans: mentionSpans,
      threadItemId: threadItemId,
      replyToMessageId: replyToMessageId,
      replyToAuthorId: replyToAuthorId,
      replyToAuthorTitle: replyToAuthorTitle,
      replyToBodyExcerpt: replyToBodyExcerpt,
      replyToHasAttachments: replyToHasAttachments,
      semanticMarker: semanticMarkerRaw as int?,
      systemMessageKind: systemMessageKindRaw as int?,
      systemPayload: systemPayload,
      quotedFact: quotedFact,
    );
  }

  static QuotedFact? _parseQuotedFact(Object? raw) {
    final map = _normalizeJsonObject(raw);
    if (map == null) return null;
    final factCardId = map['factCardId'];
    final seq = map['seq'];
    final text = map['text'];
    final status = map['status'];
    final currentSeq = map['currentSeq'];
    if (factCardId is! String ||
        factCardId.isEmpty ||
        seq is! int ||
        text is! String ||
        status is! int ||
        currentSeq is! int) {
      return null;
    }
    final pinnedById = map['pinnedById'];
    if (pinnedById != null && pinnedById is! String) {
      return null;
    }
    final pinnedByTitle = map['pinnedByTitle'];
    if (pinnedByTitle != null && pinnedByTitle is! String) {
      return null;
    }
    final visibility = map['visibility'];
    if (visibility != null && visibility is! int) {
      return null;
    }
    final attachmentsJson = map['attachmentsJson'];
    if (attachmentsJson != null && attachmentsJson is! String) {
      return null;
    }
    return QuotedFact(
      factCardId: factCardId,
      seq: seq,
      currentSeq: currentSeq,
      status: status,
      factText: text,
      pinnedById: pinnedById as String?,
      pinnedByTitle: pinnedByTitle as String? ?? '',
      visibility: visibility as int? ?? 0,
      attachments: attachmentsJson is String
          ? parseRoomMessageAttachmentsJson(attachmentsJson)
          : const [],
    );
  }

  static Iterable<RealtimeCatchUp> _deduplicateCatchUps(
    List<RealtimeCatchUp> batch,
  ) {
    final latestByGeneration = <(String, int), RealtimeCatchUp>{};
    for (final catchUp in batch) {
      latestByGeneration[(catchUp.accountId, catchUp.connectionEpoch)] =
          catchUp;
    }
    return latestByGeneration.values;
  }

  static RealtimeConnectionPhase _connectionPhase(
    RealtimeTransportPhase phase,
  ) => switch (phase) {
    RealtimeTransportPhase.unbound => RealtimeConnectionPhase.unbound,
    RealtimeTransportPhase.connecting => RealtimeConnectionPhase.connecting,
    RealtimeTransportPhase.authenticating =>
      RealtimeConnectionPhase.authenticating,
    RealtimeTransportPhase.authenticated =>
      RealtimeConnectionPhase.authenticated,
    RealtimeTransportPhase.disconnected => RealtimeConnectionPhase.disconnected,
  };

  static RealtimeOperation? _operationFromWire(Object? raw) => switch (raw) {
    'insert' => RealtimeOperation.insert,
    'update' => RealtimeOperation.update,
    'delete' => RealtimeOperation.delete,
    _ => null,
  };

  /// WebSocket `jsonDecode` may retain JS-backed values; round-trip so payload
  /// values are plain Dart objects before closed-enum mapping.
  static Map<String, dynamic>? _normalizeJsonObject(Object? value) {
    if (value == null) return null;
    try {
      final decoded = jsonDecode(jsonEncode(value));
      if (decoded is! Map) return null;
      return Map<String, dynamic>.from(decoded);
    } on Object {
      return null;
    }
  }

  @disposeMethod
  @override
  Future<void> dispose() async {
    await _messageSubscription.cancel();
    await _transportSubscription.cancel();
    await _entityChangeController.close();
    await _catchUpController.close();
    await _connectionStatusSubject.close();
  }
}
