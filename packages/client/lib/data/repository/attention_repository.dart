import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart';

import 'package:tentura/data/service/remote_api_client/remote_request_client.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/attention/entity/activity_beacon_attention.dart';
import 'package:tentura/domain/attention/entity/activity_offer_sort_row.dart';
import 'package:tentura/domain/attention/entity/attention_clear.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/entity/attention_summary.dart';
import 'package:tentura/domain/attention/entity/my_work_beacon_attention.dart';
import 'package:tentura/domain/attention/port/attention_repository_port.dart';
import 'package:tentura/features/attention/data/gql/_g/activity_attention.req.gql.dart';
import 'package:tentura/features/attention/data/gql/_g/attention_clear.req.gql.dart';
import 'package:tentura/features/attention/data/gql/_g/attention_clear_snapshot.req.gql.dart';
import 'package:tentura/features/attention/data/gql/_g/attention_dismiss_all.req.gql.dart';
import 'package:tentura/features/attention/data/gql/_g/attention_reconcile.req.gql.dart';
import 'package:tentura/features/attention/data/gql/_g/attention_request_history.data.gql.dart';
import 'package:tentura/features/attention/data/gql/_g/attention_request_history.req.gql.dart';
import 'package:tentura/features/attention/data/gql/_g/attention_undo.req.gql.dart';
import 'package:tentura/features/attention/data/gql/_g/activity_offers_v2.req.gql.dart';
import 'package:tentura/features/attention/data/gql/_g/attention_feed.data.gql.dart';
import 'package:tentura/features/attention/data/gql/_g/attention_feed.req.gql.dart';
import 'package:tentura/features/attention/data/gql/_g/attention_receipt_fields.data.gql.dart';
import 'package:tentura/features/attention/data/gql/_g/attention_mark_all_seen.req.gql.dart';
import 'package:tentura/features/attention/data/gql/_g/attention_mark_seen.req.gql.dart';
import 'package:tentura/features/attention/data/gql/_g/attention_mark_seen_for_beacon.req.gql.dart';
import 'package:tentura/features/attention/data/gql/_g/attention_mark_unseen.req.gql.dart';
import 'package:tentura/features/attention/data/gql/_g/attention_live_obligations.req.gql.dart';
import 'package:tentura/features/attention/data/gql/_g/attention_markers.req.gql.dart';
import 'package:tentura/features/attention/data/gql/_g/attention_settle.req.gql.dart';
import 'package:tentura/features/attention/data/gql/_g/attention_surface_summary.req.gql.dart';
import 'package:tentura/features/attention/data/gql/_g/my_work_attention.data.gql.dart';
import 'package:tentura/features/attention/data/gql/_g/my_work_attention.req.gql.dart';

@LazySingleton(
  as: AttentionRepositoryPort,
  env: [Environment.dev, Environment.prod],
)
final class AttentionRepository implements AttentionRepositoryPort {
  AttentionRepository(this._remoteClient);

  final RemoteRequestClient _remoteClient;

  static const _label = 'Attention';
  static final _log = Logger('AttentionRepository');

  @override
  Future<AttentionFeed> fetch({
    required AttentionView view,
    String? cursor,
    String? search,
    int limit = 50,
    AttentionSurface? surface,
  }) async {
    final data = await _remoteClient
        .request(
          GAttentionFeedReq(
            (request) => request.vars
              ..view = view.name
              ..cursor = cursor
              ..search = search
              ..limit = limit
              ..surface = surface?.wireName,
          ),
        )
        .firstWhere((response) => response.dataSource == DataSource.Link)
        .then((response) => response.dataOrThrow(label: _label));
    final feed = data.attentionFeed;
    return AttentionFeed(
      summary: AttentionSummary(
        unreadTotal: feed.summary.unreadTotal,
        needsYouTotal: feed.summary.needsYouTotal,
      ),
      page: AttentionFeedPage(
        nextCursor: feed.page.nextCursor,
        items: _uniqueByReceiptId([
          for (final item in feed.page.items) _mapFeedReceipt(item),
        ]),
      ),
    );
  }

  AttentionReceipt _mapFeedReceipt(
    GAttentionFeedData_attentionFeed_page_items item,
  ) => _mapReceiptFields(
    item,
    eventsPreview: [
      for (final preview in item.eventsPreview) _mapReceiptFields(preview),
    ],
  );

  AttentionReceipt _mapReceiptFields(
    GAttentionReceiptFields item, {
    List<AttentionReceipt> eventsPreview = const [],
  }) => _mapReceiptWire(
    id: item.id,
    category: item.category,
    kind: item.kind,
    priority: item.priority,
    title: item.title,
    body: item.body,
    actionUrl: item.actionUrl,
    createdAt: item.createdAt,
    seenAt: item.seenAt,
    collapsedCount: item.collapsedCount,
    beaconId: item.beaconId,
    coordinationItemId: item.coordinationItemId,
    actorUserId: item.actorUserId,
    sourceEventKey: item.sourceEventKey,
    destinationKind: item.destinationKind,
    targetEntityId: item.targetEntityId,
    presentationKey: item.presentationKey,
    presentationPayloadJson: item.presentationPayloadJson,
    inAppPreferenceClass: item.inAppPreferenceClass,
    requiresAction: item.requiresAction,
    attentionThreadKey: item.attentionThreadKey,
    settlementKind: item.settlementKind,
    settledAt: item.settledAt,
    clearedAt: item.clearedAt,
    clearReason: item.clearReason,
    surface: item.surface,
    itemKind: item.itemKind,
    forwardOutcome: item.forwardOutcome,
    forwardCount: item.forwardCount,
    digestCount: item.digestCount,
    eventTotal: item.eventTotal,
    eventUnseenCount: item.eventUnseenCount,
    provenanceJson: item.provenanceJson,
    beaconAuthorId: item.beaconAuthorId,
    beaconAuthorName: item.beaconAuthorName,
    beaconAuthorImageId: item.beaconAuthorImageId,
    beaconImageId: item.beaconImageId,
    beaconEndAt: item.beaconEndAt,
    allowsForward: item.allowsForward,
    eventsPreview: eventsPreview,
  );

  AttentionReceipt _mapMyWorkReceipt(
    GMyWorkAttentionData_myWorkAttention_latestUnseen item,
  ) => _mapReceiptWire(
    id: item.id,
    category: item.category,
    kind: item.kind,
    priority: item.priority,
    title: item.title,
    body: item.body,
    actionUrl: item.actionUrl,
    createdAt: item.createdAt,
    seenAt: item.seenAt,
    collapsedCount: item.collapsedCount,
    beaconId: item.beaconId,
    coordinationItemId: item.coordinationItemId,
    actorUserId: item.actorUserId,
    sourceEventKey: item.sourceEventKey,
    destinationKind: item.destinationKind,
    targetEntityId: item.targetEntityId,
    presentationKey: item.presentationKey,
    presentationPayloadJson: item.presentationPayloadJson,
    inAppPreferenceClass: item.inAppPreferenceClass,
    requiresAction: item.requiresAction,
    attentionThreadKey: item.attentionThreadKey,
    settlementKind: item.settlementKind,
    settledAt: item.settledAt,
    clearedAt: item.clearedAt,
    clearReason: item.clearReason,
    surface: item.surface,
    itemKind: item.itemKind,
    forwardOutcome: item.forwardOutcome,
    forwardCount: item.forwardCount,
    digestCount: item.digestCount,
  );

  AttentionReceipt _mapMyWorkObligationReceipt(
    GMyWorkAttentionData_myWorkAttention_liveObligations item,
  ) => _mapReceiptWire(
    id: item.id,
    category: item.category,
    kind: item.kind,
    priority: item.priority,
    title: item.title,
    body: item.body,
    actionUrl: item.actionUrl,
    createdAt: item.createdAt,
    seenAt: item.seenAt,
    collapsedCount: item.collapsedCount,
    beaconId: item.beaconId,
    coordinationItemId: item.coordinationItemId,
    actorUserId: item.actorUserId,
    sourceEventKey: item.sourceEventKey,
    destinationKind: item.destinationKind,
    targetEntityId: item.targetEntityId,
    presentationKey: item.presentationKey,
    presentationPayloadJson: item.presentationPayloadJson,
    inAppPreferenceClass: item.inAppPreferenceClass,
    requiresAction: item.requiresAction,
    attentionThreadKey: item.attentionThreadKey,
    settlementKind: item.settlementKind,
    settledAt: item.settledAt,
    clearedAt: item.clearedAt,
    clearReason: item.clearReason,
    surface: item.surface,
    itemKind: item.itemKind,
    forwardOutcome: item.forwardOutcome,
    forwardCount: item.forwardCount,
    digestCount: item.digestCount,
  );

  AttentionReceipt _mapReceiptWire({
    required String id,
    required String category,
    required String kind,
    required String priority,
    required String title,
    required String body,
    required String actionUrl,
    required String createdAt,
    String? seenAt,
    required int collapsedCount,
    String? beaconId,
    String? coordinationItemId,
    String? actorUserId,
    String? sourceEventKey,
    String? destinationKind,
    String? targetEntityId,
    String? presentationKey,
    required String presentationPayloadJson,
    String? inAppPreferenceClass,
    required bool requiresAction,
    String? attentionThreadKey,
    String? settlementKind,
    String? settledAt,
    required String surface,
    required String itemKind,
    String? forwardOutcome,
    int? forwardCount,
    int? digestCount,
    String? clearedAt,
    String? clearReason,
    int? eventTotal,
    int? eventUnseenCount,
    String? provenanceJson,
    String? beaconAuthorId,
    String? beaconAuthorName,
    String? beaconAuthorImageId,
    String? beaconImageId,
    String? beaconEndAt,
    bool? allowsForward,
    List<AttentionReceipt> eventsPreview = const [],
  }) {
    final parsedSurface = _parseSurface(surface);
    final parsedItemKind = _parseItemKind(itemKind);
    final parsedForwardOutcome = AttentionForwardOutcome.fromWire(
      forwardOutcome,
    );
    final parsedClearReason = AttentionClearReason.fromWire(clearReason);
    if (parsedClearReason == AttentionClearReason.unknown) {
      _log.warning('[$_label] unknown clearReason wire value: $clearReason');
    }
    if (forwardOutcome != null && parsedForwardOutcome == null) {
      _log.warning(
        '[$_label] unknown forwardOutcome wire value: $forwardOutcome',
      );
    }
    return AttentionReceipt(
      id: id,
      category: category,
      kind: kind,
      priority: priority,
      title: title,
      body: body,
      actionUrl: actionUrl,
      createdAt: DateTime.parse(createdAt),
      seenAt: seenAt == null ? null : DateTime.tryParse(seenAt),
      collapsedCount: collapsedCount,
      beaconId: beaconId,
      coordinationItemId: coordinationItemId,
      actorUserId: actorUserId,
      sourceEventKey: sourceEventKey,
      destinationKind: destinationKind,
      targetEntityId: targetEntityId,
      presentationKey: presentationKey,
      presentationPayloadJson: presentationPayloadJson,
      inAppPreferenceClass: inAppPreferenceClass,
      requiresAction: requiresAction,
      attentionThreadKey: attentionThreadKey,
      settlementKind: settlementKind,
      settledAt: settledAt == null ? null : DateTime.tryParse(settledAt),
      clearedAt: clearedAt == null ? null : DateTime.tryParse(clearedAt),
      clearReason: parsedClearReason,
      surface: parsedSurface,
      itemKind: parsedItemKind,
      forwardOutcome: parsedForwardOutcome,
      forwardCount: forwardCount,
      digestCount: digestCount,
      eventTotal: eventTotal,
      eventUnseenCount: eventUnseenCount,
      provenanceJson: provenanceJson,
      beaconAuthorId: beaconAuthorId,
      beaconAuthorName: beaconAuthorName,
      beaconAuthorImageId: beaconAuthorImageId,
      beaconImageId: beaconImageId,
      beaconEndAt: beaconEndAt == null ? null : DateTime.tryParse(beaconEndAt),
      allowsForward: allowsForward,
      eventsPreview: eventsPreview,
    );
  }

  AttentionSurface _parseSurface(String wire) {
    final parsed = AttentionSurface.fromWire(wire);
    if (parsed == AttentionSurface.activity &&
        wire != AttentionSurface.activityWire) {
      _log.warning('[$_label] unknown surface wire value: $wire');
    }
    return parsed;
  }

  AttentionItemKind _parseItemKind(String wire) {
    final parsed = AttentionItemKind.fromWire(wire);
    if (parsed == AttentionItemKind.receipt &&
        wire != AttentionItemKind.receiptWire) {
      _log.warning('[$_label] unknown itemKind wire value: $wire');
    }
    return parsed;
  }

  List<AttentionReceipt> _uniqueByReceiptId(
    Iterable<AttentionReceipt> items,
  ) => items
      .fold<Map<String, AttentionReceipt>>(
        {},
        (byId, receipt) => byId..[receipt.id] = receipt,
      )
      .values
      .toList(growable: false);

  @override
  Future<Set<String>> unreadForBeacons(Set<String> beaconIds) async {
    if (beaconIds.isEmpty) return const {};
    final data = await _remoteClient
        .request(
          GAttentionMarkersReq(
            (request) => request.vars.beaconIds.addAll(beaconIds),
          ),
        )
        .firstWhere((response) => response.dataSource == DataSource.Link)
        .then((response) => response.dataOrThrow(label: _label));
    return data.attentionMarkers.unreadBeaconIds.toSet();
  }

  @override
  Future<Set<String>> liveObligationBeacons() async {
    final data = await _remoteClient
        .request(GAttentionLiveObligationsReq())
        .firstWhere((response) => response.dataSource == DataSource.Link)
        .then((response) => response.dataOrThrow(label: _label));
    return data.liveObligationBeacons.toSet();
  }

  @override
  Future<int> markSeen(List<String> ids) async {
    if (ids.isEmpty) return 0;
    final data = await _remoteClient
        .request(
          GAttentionMarkSeenReq((request) => request.vars.ids.addAll(ids)),
        )
        .firstWhere((response) => response.dataSource == DataSource.Link)
        .then((response) => response.dataOrThrow(label: _label));
    return data.attentionMarkSeen;
  }

  @override
  Future<int> markUnseen(List<String> ids) async {
    if (ids.isEmpty) return 0;
    final data = await _remoteClient
        .request(
          GAttentionMarkUnseenReq((request) => request.vars.ids.addAll(ids)),
        )
        .firstWhere((response) => response.dataSource == DataSource.Link)
        .then((response) => response.dataOrThrow(label: _label));
    return data.attentionMarkUnseen;
  }

  @override
  Future<int> markAllSeen({AttentionSurface? surface}) async {
    final data = await _remoteClient
        .request(
          GAttentionMarkAllSeenReq(
            (request) => request.vars.surface = surface?.wireName,
          ),
        )
        .firstWhere((response) => response.dataSource == DataSource.Link)
        .then((response) => response.dataOrThrow(label: _label));
    return data.attentionMarkAllSeen;
  }

  @override
  Future<AttentionSurfaceSummary> surfaceSummary() async {
    final data = await _remoteClient
        .request(GAttentionSurfaceSummaryReq())
        .firstWhere((response) => response.dataSource == DataSource.Link)
        .then((response) => response.dataOrThrow(label: _label));
    final summary = data.attentionSurfaceSummary;
    return AttentionSurfaceSummary(
      activityUnreadTotal: summary.activityUnreadTotal,
      myWorkUnreadTotal: summary.myWorkUnreadTotal,
      needsYouTotal: summary.needsYouTotal,
    );
  }

  @override
  Future<int> markSeenForBeacon(String beaconId) async {
    final data = await _remoteClient
        .request(
          GAttentionMarkSeenForBeaconReq(
            (request) => request.vars.beaconId = beaconId,
          ),
        )
        .firstWhere((response) => response.dataSource == DataSource.Link)
        .then((response) => response.dataOrThrow(label: _label));
    return data.attentionMarkSeenForBeacon;
  }

  @override
  Future<List<MyWorkBeaconAttention>> myWorkAttention(
    Set<String> beaconIds,
  ) async {
    if (beaconIds.isEmpty) return const [];
    final data = await _remoteClient
        .request(
          GMyWorkAttentionReq(
            (request) => request.vars.beaconIds.addAll(beaconIds),
          ),
        )
        .firstWhere((response) => response.dataSource == DataSource.Link)
        .then((response) => response.dataOrThrow(label: _label));
    return [
      for (final row in data.myWorkAttention)
        MyWorkBeaconAttention(
          beaconId: row.beaconId,
          unseenCount: row.unseenCount,
          needsYouAt: row.needsYouAt == null
              ? null
              : DateTime.tryParse(row.needsYouAt!),
          firstEntryAt: row.firstEntryAt == null
              ? null
              : DateTime.tryParse(row.firstEntryAt!),
          latestUnseen: row.latestUnseen == null
              ? null
              : _mapMyWorkReceipt(row.latestUnseen!),
          liveObligations: [
            for (final obligation in row.liveObligations)
              _mapMyWorkObligationReceipt(obligation),
          ],
        ),
    ];
  }

  @override
  Future<ActivityOfferPage> activityOffers({
    String? cursor,
    int limit = 20,
  }) async {
    final data = await _remoteClient
        .request(
          GActivityOffersV2Req(
            (request) => request.vars
              ..cursor = cursor
              ..limit = limit,
          ),
        )
        .firstWhere((response) => response.dataSource == DataSource.Link)
        .then((response) => response.dataOrThrow(label: _label));
    final page = data.activityOffers;
    return ActivityOfferPage(
      totalCount: page.totalCount,
      nextCursor: page.nextCursor,
      items: [
        for (final row in page.items)
          ActivityOfferSortRow(
            beaconId: row.beaconId,
            listPositionAt: DateTime.parse(row.listPositionAt),
            effectiveActivityAt: DateTime.parse(row.effectiveActivityAt),
            latestForwardAt: DateTime.parse(row.latestForwardAt),
            unseen: row.unseen,
            eventTotal: row.eventTotal,
            eventUnseenCount: row.eventUnseenCount,
            eventsPreview: [
              for (final preview in row.eventsPreview)
                _mapReceiptFields(preview),
            ],
          ),
      ],
    );
  }

  @override
  Future<ActivityBeaconAttention> activityAttention({
    required String beaconId,
    String? cursor,
    int limit = 20,
  }) async {
    final data = await _remoteClient
        .request(
          GActivityAttentionReq(
            (request) => request.vars
              ..beaconId = beaconId
              ..cursor = cursor
              ..limit = limit,
          ),
        )
        .firstWhere((response) => response.dataSource == DataSource.Link)
        .then((response) => response.dataOrThrow(label: _label));
    final page = data.activityAttention;
    return ActivityBeaconAttention(
      beaconId: page.beaconId,
      eventTotal: page.eventTotal,
      unseenCount: page.unseenCount,
      latestAt: DateTime.parse(page.latestAt),
      nextCursor: page.nextCursor,
      events: [
        for (final event in page.events) _mapReceiptFields(event),
      ],
    );
  }

  @override
  Future<int> settle({
    required String receiptId,
    required String kind,
  }) async {
    final data = await _remoteClient
        .request(
          GAttentionSettleReq(
            (request) => request.vars
              ..receiptId = receiptId
              ..kind = kind,
          ),
        )
        .firstWhere((response) => response.dataSource == DataSource.Link)
        .then((response) => response.dataOrThrow(label: _label));
    return data.attentionSettle;
  }

  @override
  Future<AttentionClearSnapshot> clearSnapshot({
    required AttentionClearCaptureKind kind,
    String? beaconId,
    String? receiptId,
  }) async {
    final data = await _remoteClient
        .request(
          GAttentionClearSnapshotReq(
            (request) => request.vars
              ..kind = kind.wireName
              ..beaconId = beaconId
              ..receiptId = receiptId,
          ),
        )
        .firstWhere((response) => response.dataSource == DataSource.Link)
        .then((response) => response.dataOrThrow(label: _label));
    final snapshot = data.attentionClearSnapshot;
    return AttentionClearSnapshot(
      snapshotToken: snapshot.snapshotToken,
      receiptIds: snapshot.receiptIds.toList(growable: false),
      outcomeGeneration: snapshot.outcomeGeneration,
      decisionRevision: snapshot.decisionRevision,
    );
  }

  @override
  Future<AttentionClearResult> clear({
    required String snapshotToken,
    required String operationId,
  }) async {
    final data = await _remoteClient
        .request(
          GAttentionClearReq(
            (request) => request.vars
              ..snapshotToken = snapshotToken
              ..operationId = operationId,
          ),
        )
        .firstWhere((response) => response.dataSource == DataSource.Link)
        .then((response) => response.dataOrThrow(label: _label));
    final result = data.attentionClear;
    return AttentionClearResult(
      operationId: result.operationId,
      status: _parseStatus(result.status),
      appliedReceiptIds: result.appliedReceiptIds.toList(growable: false),
      skippedReceiptIds: result.skippedReceiptIds.toList(growable: false),
      deniedReceiptIds: result.deniedReceiptIds.toList(growable: false),
    );
  }

  @override
  Future<AttentionDismissAllResult> dismissAll({
    required String operationId,
    int? maxBatches,
  }) async {
    final data = await _remoteClient
        .request(
          GAttentionDismissAllReq(
            (request) => request.vars
              ..operationId = operationId
              ..maxBatches = maxBatches,
          ),
        )
        .firstWhere((response) => response.dataSource == DataSource.Link)
        .then((response) => response.dataOrThrow(label: _label));
    final result = data.attentionDismissAll;
    return AttentionDismissAllResult(
      operationId: result.operationId,
      status: _parseStatus(result.status),
      appliedReceiptIds: result.appliedReceiptIds.toList(growable: false),
      appliedOutcomeBeaconIds: result.appliedOutcomeBeaconIds.toList(
        growable: false,
      ),
      appliedCount: result.appliedCount,
      skipped: [
        for (final member in result.skipped)
          _mapSweepMember(member.kind, member.id, member.reason),
      ],
      failed: [
        for (final member in result.failed)
          _mapSweepMember(member.kind, member.id, member.reason),
      ],
      pendingCount: result.pendingCount,
      undoToken: result.undoToken,
      undoDeadline: result.undoDeadline == null
          ? null
          : DateTime.tryParse(result.undoDeadline!),
    );
  }

  @override
  Future<AttentionUndoResult> undo({
    required String operationId,
    required String undoToken,
  }) async {
    final data = await _remoteClient
        .request(
          GAttentionUndoReq(
            (request) => request.vars
              ..operationId = operationId
              ..undoToken = undoToken,
          ),
        )
        .firstWhere((response) => response.dataSource == DataSource.Link)
        .then((response) => response.dataOrThrow(label: _label));
    final result = data.attentionUndo;
    final refusal = AttentionUndoRefusal.fromWire(result.refusal);
    if (refusal == AttentionUndoRefusal.unknown) {
      _log.warning('[$_label] unknown undo refusal wire value: ${result.refusal}');
    }
    return AttentionUndoResult(
      operationId: result.operationId,
      status: _parseStatus(result.status),
      restoredReceiptIds: result.restoredReceiptIds.toList(growable: false),
      restoredOutcomeBeaconIds: result.restoredOutcomeBeaconIds.toList(
        growable: false,
      ),
      skipped: [
        for (final member in result.skipped)
          _mapUndoMember(member.kind, member.id, member.reason),
      ],
      failed: [
        for (final member in result.failed)
          _mapUndoMember(member.kind, member.id, member.reason),
      ],
      refusal: refusal,
    );
  }

  @override
  Future<AttentionReconcileResult> reconcile() async {
    final data = await _remoteClient
        .request(GAttentionReconcileReq())
        .firstWhere((response) => response.dataSource == DataSource.Link)
        .then((response) => response.dataOrThrow(label: _label));
    final result = data.attentionReconcile;
    return AttentionReconcileResult(
      summary: AttentionSurfaceSummary(
        activityUnreadTotal: result.summary.activityUnreadTotal,
        myWorkUnreadTotal: result.summary.myWorkUnreadTotal,
        needsYouTotal: result.summary.needsYouTotal,
      ),
      createdObligationCount: result.createdObligationCount,
      settledObligationCount: result.settledObligationCount,
      unrepairableObligationCount: result.unrepairableObligationCount,
    );
  }

  @override
  Future<AttentionFeedPage> requestHistory({
    required String beaconId,
    String? cursor,
    int limit = 20,
  }) async {
    final data = await _remoteClient
        .request(
          GAttentionRequestHistoryReq(
            (request) => request.vars
              ..beaconId = beaconId
              ..cursor = cursor
              ..limit = limit,
          ),
        )
        .firstWhere((response) => response.dataSource == DataSource.Link)
        .then((response) => response.dataOrThrow(label: _label));
    final page = data.attentionRequestHistory;
    return AttentionFeedPage(
      nextCursor: page.nextCursor,
      items: _uniqueByReceiptId([
        for (final item in page.items) _mapHistoryReceipt(item),
      ]),
    );
  }

  AttentionReceipt _mapHistoryReceipt(
    GAttentionRequestHistoryData_attentionRequestHistory_items item,
  ) => _mapReceiptFields(
    item,
    eventsPreview: [
      for (final preview in item.eventsPreview) _mapReceiptFields(preview),
    ],
  );

  // Ferry emits a distinct class per selection set, so `skipped` and `failed`
  // have no common supertype even though they carry the same three fields.
  AttentionSweepMember _mapSweepMember(String kind, String id, String? reason) {
    final parsed = AttentionSweepSkipReason.fromWire(reason);
    if (parsed == AttentionSweepSkipReason.unknown) {
      _log.warning('[$_label] unknown sweep skip reason: $reason');
    }
    return AttentionSweepMember(
      id: id,
      kind: _parseMemberKind(kind),
      reason: parsed,
    );
  }

  AttentionUndoMember _mapUndoMember(String kind, String id, String? reason) {
    final parsed = AttentionUndoSkipReason.fromWire(reason);
    if (parsed == AttentionUndoSkipReason.unknown) {
      _log.warning('[$_label] unknown undo skip reason: $reason');
    }
    return AttentionUndoMember(
      id: id,
      kind: _parseMemberKind(kind),
      reason: parsed,
    );
  }

  AttentionOperationStatus _parseStatus(String wire) {
    final parsed =
        AttentionOperationStatus.fromWire(wire) ??
        AttentionOperationStatus.unknown;
    if (parsed == AttentionOperationStatus.unknown) {
      _log.warning('[$_label] unknown operation status wire value: $wire');
    }
    return parsed;
  }

  AttentionSweepMemberKind _parseMemberKind(String wire) {
    final parsed =
        AttentionSweepMemberKind.fromWire(wire) ??
        AttentionSweepMemberKind.unknown;
    if (parsed == AttentionSweepMemberKind.unknown) {
      _log.warning('[$_label] unknown sweep member kind: $wire');
    }
    return parsed;
  }
}
