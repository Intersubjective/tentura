import 'package:ferry/ferry.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/data/repository/attention_repository.dart';
import 'package:tentura/data/service/remote_api_client/remote_request_client.dart';
import 'package:tentura/domain/attention/entity/attention_clear.dart';
import 'package:tentura/features/attention/data/gql/_g/attention_clear.data.gql.dart';
import 'package:tentura/features/attention/data/gql/_g/attention_clear.req.gql.dart';
import 'package:tentura/features/attention/data/gql/_g/attention_clear_snapshot.data.gql.dart';
import 'package:tentura/features/attention/data/gql/_g/attention_clear_snapshot.req.gql.dart';
import 'package:tentura/features/attention/data/gql/_g/attention_dismiss_all.data.gql.dart';
import 'package:tentura/features/attention/data/gql/_g/attention_dismiss_all.req.gql.dart';
import 'package:tentura/features/attention/data/gql/_g/attention_reconcile.data.gql.dart';
import 'package:tentura/features/attention/data/gql/_g/attention_reconcile.req.gql.dart';
import 'package:tentura/features/attention/data/gql/_g/attention_request_history.data.gql.dart';
import 'package:tentura/features/attention/data/gql/_g/attention_request_history.req.gql.dart';
import 'package:tentura/features/attention/data/gql/_g/attention_undo.data.gql.dart';
import 'package:tentura/features/attention/data/gql/_g/attention_undo.req.gql.dart';

void main() {
  final remote = _FixtureRemoteClient();
  final repository = AttentionRepository(remote);

  tearDown(remote.reset);

  test('clearSnapshot sends the capture kind and maps the token', () async {
    remote.snapshotData = GAttentionClearSnapshotData.fromJson({
      '__typename': 'query_root',
      'attentionClearSnapshot': {
        '__typename': 'v2_AttentionClearSnapshot',
        'snapshotToken': 'snap-1',
        'receiptIds': ['r-1', 'r-2'],
        'outcomeGeneration': 3,
        'decisionRevision': 7,
      },
    })!;
    final snapshot = await repository.clearSnapshot(
      kind: AttentionClearCaptureKind.requestOpen,
      beaconId: 'B1',
    );
    expect(snapshot.snapshotToken, 'snap-1');
    expect(snapshot.receiptIds, ['r-1', 'r-2']);
    expect(snapshot.outcomeGeneration, 3);
    expect(snapshot.decisionRevision, 7);
    expect(remote.lastSnapshotVars, ('request_open', 'B1', null));
  });

  test('clear maps a partial answer with its skipped and denied members',
      () async {
    remote.clearData = GAttentionClearData.fromJson({
      '__typename': 'mutation_root',
      'attentionClear': {
        '__typename': 'v2_AttentionClearResult',
        'operationId': 'op-1',
        'appliedReceiptIds': ['r-1'],
        'skippedReceiptIds': ['r-2'],
        'deniedReceiptIds': ['r-3'],
        'status': 'partial',
      },
    })!;
    final result = await repository.clear(
      snapshotToken: 'snap-1',
      operationId: 'op-1',
    );
    expect(result.status, AttentionOperationStatus.partial);
    expect(result.isComplete, isFalse);
    expect(result.appliedReceiptIds, ['r-1']);
    expect(result.skippedReceiptIds, ['r-2']);
    expect(result.deniedReceiptIds, ['r-3']);
    expect(result.hasRefusals, isTrue);
  });

  test('dismissAll maps typed skip reasons, pending count and undo token',
      () async {
    remote.dismissAllData = GAttentionDismissAllData.fromJson({
      '__typename': 'mutation_root',
      'attentionDismissAll': {
        '__typename': 'v2_AttentionDismissAllResult',
        'operationId': 'op-2',
        'appliedReceiptIds': ['r-1'],
        'appliedOutcomeBeaconIds': ['B2'],
        'appliedCount': 2,
        'skipped': [
          {
            '__typename': 'v2_AttentionSweepMember',
            'kind': 'receipt',
            'id': 'r-2',
            'reason': 'awaiting_decision',
          },
        ],
        'failed': [
          {
            '__typename': 'v2_AttentionSweepMember',
            'kind': 'outcome',
            'id': 'B3',
            'reason': 'teleported_away',
          },
        ],
        'pendingCount': 4,
        'status': 'partial',
        'undoToken': 'undo-1',
        'undoDeadline': '2026-09-19T10:00:30.000Z',
      },
    })!;
    final result = await repository.dismissAll(
      operationId: 'op-2',
      maxBatches: 2,
    );
    expect(result.appliedCount, 2);
    expect(result.appliedOutcomeBeaconIds, ['B2']);
    expect(result.skipped.single.reason,
        AttentionSweepSkipReason.awaitingDecision);
    expect(result.failed.single.kind, AttentionSweepMemberKind.outcome);
    expect(result.failed.single.reason, AttentionSweepSkipReason.unknown);
    expect(result.needsResume, isTrue);
    expect(result.isComplete, isFalse);
    expect(result.canUndo, isTrue);
    expect(result.undoDeadline, DateTime.utc(2026, 9, 19, 10, 0, 30));
  });

  test('undo maps a whole-operation refusal', () async {
    remote.undoData = GAttentionUndoData.fromJson({
      '__typename': 'mutation_root',
      'attentionUndo': {
        '__typename': 'v2_AttentionUndoResult',
        'operationId': 'op-2',
        'restoredReceiptIds': <String>[],
        'restoredOutcomeBeaconIds': <String>[],
        'restoredCount': 0,
        'skipped': <Map<String, dynamic>>[],
        'failed': <Map<String, dynamic>>[],
        'status': 'denied',
        'refusal': 'expired',
      },
    })!;
    final result = await repository.undo(
      operationId: 'op-2',
      undoToken: 'undo-1',
    );
    expect(result.refusal, AttentionUndoRefusal.expired);
    expect(result.isRefused, isTrue);
    expect(result.isComplete, isFalse);
  });

  test('undo maps per-member skip reasons on its own vocabulary', () async {
    remote.undoData = GAttentionUndoData.fromJson({
      '__typename': 'mutation_root',
      'attentionUndo': {
        '__typename': 'v2_AttentionUndoResult',
        'operationId': 'op-2',
        'restoredReceiptIds': ['r-1'],
        'restoredOutcomeBeaconIds': ['B2'],
        'restoredCount': 2,
        'skipped': [
          {
            '__typename': 'v2_AttentionUndoMember',
            'kind': 'receipt',
            'id': 'r-2',
            'reason': 'cleared_by_another_operation',
          },
        ],
        'failed': <Map<String, dynamic>>[],
        'status': 'partial',
        'refusal': null,
      },
    })!;
    final result = await repository.undo(
      operationId: 'op-2',
      undoToken: 'undo-1',
    );
    expect(result.isRefused, isFalse);
    expect(result.restoredCount, 2);
    expect(
      result.skipped.single.reason,
      AttentionUndoSkipReason.clearedByAnotherOperation,
    );
  });

  test('reconcile maps repair counts and the authoritative summary', () async {
    remote.reconcileData = GAttentionReconcileData.fromJson({
      '__typename': 'mutation_root',
      'attentionReconcile': {
        '__typename': 'v2_AttentionReconcileResult',
        'createdObligationCount': 1,
        'settledObligationCount': 2,
        'unrepairableObligationCount': 3,
        'summary': {
          '__typename': 'AttentionSurfaceSummary',
          'activityUnreadTotal': 4,
          'myWorkUnreadTotal': 5,
          'needsYouTotal': 6,
          // CHANGES IN U17c: D15 step 6 asks the client to *replace* its
          // cached indicators with what came back, and the document used to
          // ask for three of the seven fields. The four §6 indicators would
          // have defaulted to false/0 on adoption, so the repair meant to
          // make the badges correct would have blanked a dot the account
          // still owes. Each value below is one no default can produce.
          'myDeskDot': true,
          'myDeskCount': 7,
          'forYouDot': true,
          'forYouSweepEligible': true,
        },
      },
    })!;
    final result = await repository.reconcile();
    expect(result.createdObligationCount, 1);
    expect(result.settledObligationCount, 2);
    expect(result.unrepairableObligationCount, 3);
    expect(result.isFullyRepaired, isFalse);
    expect(result.summary.needsYouTotal, 6);
    expect(
      result.summary.myDeskDot,
      isTrue,
      reason: 'a defaulted myDeskDot would blank a dot the account owes',
    );
    expect(
      result.summary.myDeskCount,
      7,
      reason: '§6 my desk.count is its own field, not needsYouTotal (6)',
    );
    expect(result.summary.forYouDot, isTrue);
    expect(result.summary.forYouSweepEligible, isTrue);
  });

  test('requestHistory maps cleared receipts and the next cursor', () async {
    remote.historyData = GAttentionRequestHistoryData.fromJson({
      '__typename': 'query_root',
      'attentionRequestHistory': {
        '__typename': 'AttentionPage',
        'nextCursor': 'cursor-2',
        'items': [
          {
            ..._wireReceipt(),
            'clearedAt': '2026-09-19T09:00:00.000Z',
            'clearReason': 'sweep',
            'eventsPreview': [_wireReceipt(id: 'r-child')],
          },
        ],
      },
    })!;
    final page = await repository.requestHistory(beaconId: 'B1');
    expect(page.nextCursor, 'cursor-2');
    final item = page.items.single;
    expect(item.isCleared, isTrue);
    expect(item.clearReason, AttentionClearReason.sweep);
    expect(item.eventsPreview.single.id, 'r-child');
  });
}

Map<String, dynamic> _wireReceipt({String id = 'r-1'}) => {
  '__typename': 'AttentionReceipt',
  'id': id,
  'category': 'connections',
  'kind': 'inviteAccepted',
  'priority': 'normal',
  'title': 'Title',
  'body': 'Body',
  'actionUrl': '/#/',
  'createdAt': '2026-09-19T08:00:00.000Z',
  'seenAt': null,
  'collapsedCount': 1,
  'beaconId': 'B1',
  'coordinationItemId': null,
  'actorUserId': null,
  'sourceEventKey': null,
  'destinationKind': null,
  'targetEntityId': null,
  'presentationKey': null,
  'presentationPayloadJson': '{}',
  'inAppPreferenceClass': null,
  'requiresAction': false,
  'attentionThreadKey': null,
  'settlementKind': null,
  'settledAt': null,
  'clearedAt': null,
  'clearReason': null,
  'surface': 'activity',
  'itemKind': 'receipt',
  'forwardOutcome': null,
  'forwardCount': null,
  'digestCount': null,
  'eventTotal': null,
  'eventUnseenCount': null,
  'provenanceJson': null,
  'beaconAuthorId': null,
  'beaconAuthorName': null,
  'beaconAuthorImageId': null,
  'beaconImageId': null,
  'beaconEndAt': null,
  'allowsForward': null,
};

final class _FixtureRemoteClient implements RemoteRequestClient {
  GAttentionClearSnapshotData? snapshotData;
  GAttentionClearData? clearData;
  GAttentionDismissAllData? dismissAllData;
  GAttentionUndoData? undoData;
  GAttentionReconcileData? reconcileData;
  GAttentionRequestHistoryData? historyData;
  (String, String?, String?)? lastSnapshotVars;

  void reset() {
    snapshotData = null;
    clearData = null;
    dismissAllData = null;
    undoData = null;
    reconcileData = null;
    historyData = null;
    lastSnapshotVars = null;
  }

  @override
  Stream<OperationResponse<TData, TVars>> request<TData, TVars>(
    OperationRequest<TData, TVars> request, [
    Stream<OperationResponse<TData, TVars>> Function(
      OperationRequest<TData, TVars>,
    )?
    forward,
  ]) {
    Object? data;
    if (request is GAttentionClearSnapshotReq) {
      final vars = (request as GAttentionClearSnapshotReq).vars;
      lastSnapshotVars = (vars.kind, vars.beaconId, vars.receiptId);
      data = snapshotData;
    } else if (request is GAttentionClearReq) {
      data = clearData;
    } else if (request is GAttentionDismissAllReq) {
      data = dismissAllData;
    } else if (request is GAttentionUndoReq) {
      data = undoData;
    } else if (request is GAttentionReconcileReq) {
      data = reconcileData;
    } else if (request is GAttentionRequestHistoryReq) {
      data = historyData;
    } else {
      throw StateError('unexpected request: $request');
    }
    return Stream.value(
      OperationResponse<TData, TVars>(
        operationRequest: request,
        dataSource: DataSource.Link,
        data: data as TData,
      ),
    );
  }
}
