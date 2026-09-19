import 'dart:async';

import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_clear.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/entity/attention_summary.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';

import '../../support/attention_repository_fake_base.dart';

const attentionCaseTestFeedDest = AttentionFeedDestinationId.activityStream;

AttentionFeedSession attentionCaseTestFeedSession(AttentionCase attention) =>
    attention.feedSession(attentionCaseTestFeedDest);

final class AttentionCaseTestAccounts implements AttentionAccountPort {
  final _changes = StreamController<String>.broadcast();

  @override
  Stream<String> get currentAccountChanges => _changes.stream;

  void emit(String accountId) => _changes.add(accountId);

  Future<void> dispose() => _changes.close();
}

final class AttentionCaseTestRepository extends AttentionRepositoryFake {
  final List<Completer<AttentionFeed>> pendingFetches = [];
  final List<Completer<int>> pendingMarkSeen = [];
  final List<Completer<int>> pendingMarkUnseen = [];
  final List<Completer<int>> pendingMarkAllSeen = [];
  final List<List<String>> markSeenCalls = [];
  final List<List<String>> markUnseenCalls = [];
  int markAllSeenCalls = 0;
  final List<Completer<int>> pendingSettles = [];
  final List<Completer<AttentionDismissAllResult>> pendingDismissAll = [];
  final List<({String operationId, int? maxBatches})> dismissAllCalls = [];
  final List<({String receiptId, String kind})> settles = [];
  final List<
    ({
      AttentionView view,
      String? cursor,
      String? search,
      AttentionSurface? surface,
    })
  >
  fetches = [];
  final List<Completer<AttentionSurfaceSummary>> pendingSurfaceSummaries = [];
  int surfaceSummaryCalls = 0;
  final List<String> markSeenForBeaconCalls = [];
  final List<Set<String>> markerQueries = [];
  Set<String> unreadBeaconIds = const {};
  int fetchCalls = 0;

  @override
  Future<AttentionFeed> fetch({
    required AttentionView view,
    String? cursor,
    String? search,
    int limit = 50,
    AttentionSurface? surface,
  }) {
    fetchCalls++;
    fetches.add((
      view: view,
      cursor: cursor,
      search: search,
      surface: surface,
    ));
    return pendingFetches.removeAt(0).future;
  }

  @override
  Future<AttentionSurfaceSummary> surfaceSummary() {
    surfaceSummaryCalls++;
    if (pendingSurfaceSummaries.isEmpty) {
      return Future.value(
        const AttentionSurfaceSummary(
          activityUnreadTotal: 0,
          myWorkUnreadTotal: 0,
          needsYouTotal: 0,
        ),
      );
    }
    return pendingSurfaceSummaries.removeAt(0).future;
  }

  @override
  Future<int> markSeenForBeacon(String beaconId) async {
    markSeenForBeaconCalls.add(beaconId);
    return 0;
  }

  @override
  Future<Set<String>> unreadForBeacons(Set<String> beaconIds) async {
    markerQueries.add(Set<String>.from(beaconIds));
    return unreadBeaconIds.intersection(beaconIds);
  }

  @override
  Future<Set<String>> liveObligationBeacons() async => const {};

  @override
  Future<int> markAllSeen({AttentionSurface? surface}) {
    markAllSeenCalls++;
    return pendingMarkAllSeen.removeAt(0).future;
  }

  @override
  Future<int> markSeen(List<String> ids) {
    markSeenCalls.add(List<String>.from(ids));
    return pendingMarkSeen.removeAt(0).future;
  }

  @override
  Future<int> markUnseen(List<String> ids) {
    markUnseenCalls.add(List<String>.from(ids));
    return pendingMarkUnseen.removeAt(0).future;
  }

  @override
  Future<AttentionDismissAllResult> dismissAll({
    required String operationId,
    int? maxBatches,
  }) {
    dismissAllCalls.add((operationId: operationId, maxBatches: maxBatches));
    return pendingDismissAll.removeAt(0).future;
  }

  @override
  Future<int> settle({required String receiptId, required String kind}) {
    settles.add((receiptId: receiptId, kind: kind));
    return pendingSettles.removeAt(0).future;
  }
}

AttentionFeed attentionCaseTestFeed({
  int unread = 1,
  List<AttentionReceipt>? items,
}) => AttentionFeed(
  summary: AttentionSummary(unreadTotal: unread),
  page: AttentionFeedPage(items: items ?? [attentionCaseTestReceipt()]),
);

AttentionReceipt attentionCaseTestReceipt({String id = 'receipt-1'}) =>
    AttentionReceipt(
      id: id,
      category: 'asksOfMe',
      kind: 'needsMe',
      priority: 'normal',
      title: 'Title',
      body: 'Body',
      actionUrl: '/#/',
      createdAt: DateTime.utc(2026),
      collapsedCount: 1,
      presentationPayloadJson: '{}',
      surface: AttentionSurface.activity,
    );

AttentionReceipt attentionCaseTestSeenReceipt({String id = 'receipt-1'}) =>
    attentionCaseTestReceipt(id: id).copyWith(seenAt: DateTime.utc(2026, 1, 2));

Future<void> attentionCaseTestSettle() => Future<void>.delayed(Duration.zero);
