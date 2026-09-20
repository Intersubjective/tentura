import 'package:ferry/ferry.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/data/repository/attention_repository.dart';
import 'package:tentura/data/service/remote_api_client/remote_request_client.dart';
import 'package:tentura/features/attention/data/gql/_g/attention_reconcile.data.gql.dart';
import 'package:tentura/features/attention/data/gql/_g/attention_reconcile.req.gql.dart';

void main() {
  final remote = _FixtureRemoteClient();
  final repository = AttentionRepository(remote);

  tearDown(remote.reset);

  test(
    'reconcile relays every §6 indicator, not just the three legacy totals',
    () async {
      // D15 step 6 — the client must be able to *replace* its cached
      // indicators with what came back. A document that asks for three of
      // seven fields cannot: the four §6 indicators would silently default to
      // false/0 and blank a lit dot the account still owes. The fixture
      // therefore carries values no default could produce.
      remote.reconcileData = _reconcileData(
        myDeskDot: true,
        myDeskCount: 4,
        forYouDot: true,
        forYouSweepEligible: true,
      );
      final result = await repository.reconcile();
      expect(result.createdObligationCount, 2);
      expect(result.settledObligationCount, 3);
      expect(result.unrepairableObligationCount, 1);
      expect(result.summary.activityUnreadTotal, 7);
      expect(result.summary.myWorkUnreadTotal, 5);
      expect(result.summary.needsYouTotal, 6);
      expect(
        result.summary.myDeskDot,
        isTrue,
        reason: 'a defaulted myDeskDot would blank a dot the account owes',
      );
      expect(
        result.summary.myDeskCount,
        4,
        reason: '§6 my desk.count is its own field, not needsYouTotal (6)',
      );
      expect(result.summary.forYouDot, isTrue);
      expect(result.summary.forYouSweepEligible, isTrue);
    },
  );

  test('reconcile propagates a network failure instead of faking success',
      () async {
    remote.reconcileError = StateError('offline');
    await expectLater(repository.reconcile(), throwsA(isA<StateError>()));
  });
}

GAttentionReconcileData _reconcileData({
  required bool myDeskDot,
  required int myDeskCount,
  required bool forYouDot,
  required bool forYouSweepEligible,
}) => GAttentionReconcileData.fromJson({
  '__typename': 'mutation_root',
  'attentionReconcile': {
    '__typename': 'AttentionReconcileResult',
    'createdObligationCount': 2,
    'settledObligationCount': 3,
    'unrepairableObligationCount': 1,
    'summary': {
      '__typename': 'AttentionSurfaceSummary',
      'activityUnreadTotal': 7,
      'myWorkUnreadTotal': 5,
      'needsYouTotal': 6,
      'myDeskDot': myDeskDot,
      'myDeskCount': myDeskCount,
      'forYouDot': forYouDot,
      'forYouSweepEligible': forYouSweepEligible,
    },
  },
})!;

final class _FixtureRemoteClient implements RemoteRequestClient {
  GAttentionReconcileData? reconcileData;
  Object? reconcileError;

  void reset() {
    reconcileData = null;
    reconcileError = null;
  }

  @override
  Stream<OperationResponse<TData, TVars>> request<TData, TVars>(
    OperationRequest<TData, TVars> request, [
    Stream<OperationResponse<TData, TVars>> Function(
      OperationRequest<TData, TVars>,
    )?
    forward,
  ]) {
    if (request is GAttentionReconcileReq) {
      if (reconcileError != null) return Stream.error(reconcileError!);
      return Stream.value(
        OperationResponse<TData, TVars>(
          operationRequest: request,
          dataSource: DataSource.Link,
          data: reconcileData as TData,
        ),
      );
    }
    throw UnsupportedError('Unexpected operation: $request');
  }
}
