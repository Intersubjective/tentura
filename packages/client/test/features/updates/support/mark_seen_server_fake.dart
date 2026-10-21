import 'package:tentura/domain/attention/entity/attention_clear.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/entity/attention_summary.dart';

import '../../../support/attention_repository_fake_base.dart';

/// #336 — a stateful stand-in for the server's attention store, so a test
/// can "reload" (build a fresh `AttentionCase` over the same instance) and see
/// what the mutations actually persisted.
///
/// It mirrors the real server's two axes and nothing more:
/// * `attentionMarkSeen` writes `seen_at` only (`AttentionRepository.markSeen`
///   on the server never touches `cleared_at`);
/// * an explicit single-receipt clear (`clearSnapshot` + `clear`) writes
///   `cleared_at`;
/// * the `unread` view and `unreadTotal` are the server's active-attention
///   rule, hard-coded here from the SQL (`AttentionDismissibleSql.activeAttention`
///   in packages/server/lib/data/repository/attention_dismissible_sql.dart:
///   `(NOT requires_action AND cleared_at IS NULL) OR (requires_action AND
///   settlement_kind IS NULL)`) — deliberately NOT the client's
///   `isInUnreadView` / `isActiveOptional`, so a fix that bends the client
///   predicates cannot also bend this "server".
final class MarkSeenServerFake extends AttentionRepositoryFake {
  MarkSeenServerFake(Iterable<AttentionReceipt> receipts)
    : _rows = {for (final r in receipts) r.id: r};

  final Map<String, AttentionReceipt> _rows;

  /// Every id the client sent through `attentionMarkSeen`.
  final markSeenIds = <String>[];

  /// Every receipt id the client captured for an explicit clear.
  final clearedIds = <String>[];

  /// When true every write fails the way an offline link does.
  bool failWrites = false;

  /// Every receipt id the client asked to capture for a clear (before the
  /// server filtered it).
  final clearRequestedIds = <String>[];

  AttentionReceipt row(String id) => _rows[id]!;

  /// Server SQL `activeOptional`: `NOT requires_action AND cleared_at IS NULL`.
  static bool _serverActiveOptional(AttentionReceipt r) =>
      !r.requiresAction && r.clearedAt == null;

  /// Server SQL `liveObligation`: `requires_action AND settlement_kind IS NULL`.
  static bool _serverLiveObligation(AttentionReceipt r) =>
      r.requiresAction && r.settlementKind == null;

  /// Server SQL `activeAttention` — the `unread` view and `unread_total`.
  static bool _serverUnread(AttentionReceipt r) =>
      _serverActiveOptional(r) || _serverLiveObligation(r);

  List<AttentionReceipt> get _ordered =>
      _rows.values.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  @override
  Future<AttentionFeed> fetch({
    required AttentionView view,
    String? cursor,
    String? search,
    int limit = 50,
    AttentionSurface? surface,
  }) async {
    final unread = _ordered.where(_serverUnread).toList(growable: false);
    final items = switch (view) {
      AttentionView.all => _ordered,
      AttentionView.unread => unread,
      AttentionView.needsYou =>
        _ordered.where(_serverLiveObligation).toList(growable: false),
    };
    return AttentionFeed(
      summary: AttentionSummary(
        unreadTotal: unread.length,
        needsYouTotal: _ordered.where(_serverLiveObligation).length,
      ),
      page: AttentionFeedPage(items: items),
    );
  }

  @override
  Future<Set<String>> unreadForBeacons(Set<String> beaconIds) async => {};

  @override
  Future<Set<String>> liveObligationBeacons() async => const {};

  @override
  Future<int> markSeen(List<String> ids) async {
    if (failWrites) throw StateError('offline');
    markSeenIds.addAll(ids);
    var updated = 0;
    for (final id in ids) {
      final r = _rows[id];
      if (r == null || r.seenAt != null) continue;
      _rows[id] = r.copyWith(seenAt: DateTime.utc(2026, 10, 14));
      updated++;
    }
    return updated;
  }

  @override
  Future<int> markUnseen(List<String> ids) async {
    if (failWrites) throw StateError('offline');
    var updated = 0;
    for (final id in ids) {
      final r = _rows[id];
      if (r == null || r.seenAt == null) continue;
      _rows[id] = r.copyWith(seenAt: null);
      updated++;
    }
    return updated;
  }

  @override
  Future<int> markAllSeen({AttentionSurface? surface}) async {
    if (failWrites) throw StateError('offline');
    final ids = _rows.values
        .where((r) => r.seenAt == null)
        .map((r) => r.id)
        .toList(growable: false);
    return markSeen(ids);
  }

  @override
  Future<int> settle({required String receiptId, required String kind}) async {
    if (failWrites) throw StateError('offline');
    return 0;
  }

  @override
  Future<AttentionClearSnapshot> clearSnapshot({
    required AttentionClearCaptureKind kind,
    String? beaconId,
    String? receiptId,
  }) async {
    if (receiptId != null) clearRequestedIds.add(receiptId);
    if (failWrites) throw StateError('offline');
    final members = [
      for (final r in _rows.values)
        if (_serverActiveOptional(r) &&
            ((receiptId != null && r.id == receiptId) ||
                (receiptId == null &&
                    beaconId != null &&
                    r.beaconId == beaconId)))
          r.id,
    ];
    return AttentionClearSnapshot(
      snapshotToken: 'snap:${members.join(',')}',
      receiptIds: members,
    );
  }

  @override
  Future<AttentionClearResult> clear({
    required String snapshotToken,
    required String operationId,
  }) async {
    if (failWrites) throw StateError('offline');
    final body = snapshotToken.substring('snap:'.length);
    final ids = body.isEmpty ? const <String>[] : body.split(',');
    for (final id in ids) {
      final r = _rows[id];
      if (r == null) continue;
      _rows[id] = r.copyWith(clearedAt: DateTime.utc(2026, 10, 14));
      clearedIds.add(id);
    }
    return AttentionClearResult(
      operationId: operationId,
      status: AttentionOperationStatus.complete,
      appliedReceiptIds: ids,
    );
  }
}

AttentionReceipt markSeenTestReceipt(String id, {required int minute}) =>
    AttentionReceipt(
      id: id,
      category: 'social',
      kind: 'mutualConnectionFormed',
      priority: 'normal',
      title: 'Vadim · New connection',
      body: 'You are now connected on Tentura.',
      actionUrl: '/#/',
      createdAt: DateTime.utc(2026, 10, 14, 9, minute),
      collapsedCount: 1,
      presentationPayloadJson: '{}',
      surface: AttentionSurface.activity,
    );
