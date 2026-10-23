import 'package:tentura/domain/attention/entity/attention_clear.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/entity/attention_summary.dart';

import '../../../support/attention_repository_fake_base.dart';

/// #601 (option B) — a stateful stand-in for the server's attention store
/// with the new un-clear command, so a test can "reload" (a fresh
/// `AttentionCase` over the same instance) and see what was persisted.
///
/// It mirrors the real server and nothing more:
/// * `attentionMarkUnseen` writes `seen_at` only (the read axis);
/// * `attentionMarkUnread` (#601, new) resets `seen_at` AND the clear facts
///   of the caller's optional receipts — `AttentionAckRepository.markUnread`;
/// * the `unread` view and `unreadTotal` are the server's active-attention
///   rule, hard-coded here from the SQL (`AttentionDismissibleSql`:
///   `(NOT requires_action AND cleared_at IS NULL) OR (requires_action AND
///   settlement_kind IS NULL)`) — deliberately NOT the client's
///   `isInUnreadView` / `isActiveOptional`.
final class MarkUnreadServerFake extends AttentionRepositoryFake {
  MarkUnreadServerFake(Iterable<AttentionReceipt> receipts)
    : _rows = {for (final r in receipts) r.id: r};

  final Map<String, AttentionReceipt> _rows;

  /// Every id the client sent through `attentionMarkUnseen` (read axis only).
  final markUnseenIds = <String>[];

  /// Every id the client sent through `attentionMarkUnread` (#601 un-clear).
  final markUnreadIds = <String>[];

  /// When true every write fails the way an offline link does.
  bool failWrites = false;

  /// When true `attentionMarkUnread` answers but un-clears no row (0).
  bool unreadChangesNothing = false;

  AttentionReceipt row(String id) => _rows[id]!;

  static bool _serverActiveOptional(AttentionReceipt r) =>
      !r.requiresAction && r.clearedAt == null;

  static bool _serverLiveObligation(AttentionReceipt r) =>
      r.requiresAction && r.settlementKind == null;

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
    var updated = 0;
    for (final id in ids) {
      final r = _rows[id];
      if (r == null || r.seenAt != null) continue;
      _rows[id] = r.copyWith(seenAt: DateTime.utc(2026, 10, 22));
      updated++;
    }
    return updated;
  }

  @override
  Future<int> markUnseen(List<String> ids) async {
    if (failWrites) throw StateError('offline');
    markUnseenIds.addAll(ids);
    var updated = 0;
    for (final id in ids) {
      final r = _rows[id];
      if (r == null || r.seenAt == null) continue;
      _rows[id] = r.copyWith(seenAt: null);
      updated++;
    }
    return updated;
  }

  /// #601 — the new port method: `attentionMarkUnread`.
  @override
  Future<int> markUnread(List<String> ids) async {
    if (failWrites) throw StateError('offline');
    markUnreadIds.addAll(ids);
    if (unreadChangesNothing) return 0;
    var updated = 0;
    for (final id in ids) {
      final r = _rows[id];
      if (r == null || r.requiresAction) continue;
      if (r.seenAt == null && r.clearedAt == null) continue;
      _rows[id] = r.copyWith(
        seenAt: null,
        clearedAt: null,
        clearReason: null,
      );
      updated++;
    }
    return updated;
  }

  @override
  Future<int> markAllSeen({AttentionSurface? surface}) async {
    if (failWrites) throw StateError('offline');
    return markSeen([
      for (final r in _rows.values)
        if (r.seenAt == null) r.id,
    ]);
  }

  @override
  Future<int> settle({required String receiptId, required String kind}) async {
    if (failWrites) throw StateError('offline');
    return 0;
  }
}

/// A read optional receipt; [cleared] puts it on the Done side (off Unread).
AttentionReceipt markUnreadTestReceipt(
  String id, {
  required int minute,
  bool seen = true,
  bool cleared = false,
}) => AttentionReceipt(
  id: id,
  category: 'social',
  kind: 'mutualConnectionFormed',
  priority: 'normal',
  title: 'Vadim · New connection',
  body: 'You are now connected on Tentura.',
  actionUrl: '/#/',
  createdAt: DateTime.utc(2026, 10, 22, 9, minute),
  collapsedCount: 1,
  presentationPayloadJson: '{}',
  surface: AttentionSurface.activity,
  seenAt: seen ? DateTime.utc(2026, 10, 22, 10) : null,
  clearedAt: cleared ? DateTime.utc(2026, 10, 22, 10) : null,
  clearReason: cleared ? AttentionClearReason.explicit : null,
);
