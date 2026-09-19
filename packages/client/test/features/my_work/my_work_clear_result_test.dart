import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/attention/entity/attention_clear.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/entity/my_work_beacon_attention.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/features/my_work/domain/derive_my_work_card_attention.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_cubit.dart';

import 'my_work_test_support.dart';

/// R6 — My Desk's × threw the server's answer away.
///
/// The cubit removed the preview locally, sent the command, and refreshed
/// only if the call *threw*. A `skipped` and a `denied` answer were therefore
/// indistinguishable from success: the row stayed gone and the card went
/// dark over attention the server was still counting.
void main() {
  AttentionReceipt receipt({required String id, required String beaconId}) =>
      AttentionReceipt(
        id: id,
        category: 'asksOfMe',
        kind: 'needsMe',
        priority: 'normal',
        title: id,
        body: 'Body',
        actionUrl: '/#/',
        createdAt: DateTime.utc(2026),
        collapsedCount: 1,
        presentationPayloadJson: '{}',
        beaconId: beaconId,
        surface: AttentionSurface.myWork,
      );

  Future<MyWorkCubit> boot(StubAttentionRepository attentionRepo) async {
    final repo = FakeMyWorkRepository()
      ..initResult = (
        authoredNonArchived: [Beacon.empty.copyWith(id: 'b1')],
        helpOfferedNonArchived: const [],
        obligationBeacons: const [],
        archivedCountHint: 0,
      );
    final cubit = MyWorkCubit(
      userId: 'user-1',
      myWorkCase: buildTestMyWorkCase(
        repo: repo,
        attentionRepository: attentionRepo,
      ),
    );
    await cubit.stream.firstWhere((s) => s.attentionLoaded);
    return cubit;
  }

  test('a denied clear puts the row back', () async {
    final optional = receipt(id: 'r-opt', beaconId: 'b1');
    final attentionRepo = StubAttentionRepository()
      ..myWorkAttentionResult = [
        MyWorkBeaconAttention(
          beaconId: 'b1',
          unseenCount: 1,
          latestUnseen: optional,
        ),
      ]
      ..clearResultBuilder = (operationId, _) => AttentionClearResult(
        operationId: operationId,
        status: AttentionOperationStatus.denied,
        deniedReceiptIds: const ['r-opt'],
      );
    final cubit = await boot(attentionRepo);

    await cubit.clearOptionalEvent('b1', 'r-opt');

    final entry = cubit.state.attentionByBeacon['b1']!;
    expect(
      entry.latestUnseen?.id,
      'r-opt',
      reason: 'the server refused; removal is reversible',
    );
    expect(entry.unseenCount, 1);

    await cubit.close();
  });

  test('a skipped clear is not a slow success', () async {
    final optional = receipt(id: 'r-opt', beaconId: 'b1');
    final attentionRepo = StubAttentionRepository()
      ..myWorkAttentionResult = [
        MyWorkBeaconAttention(
          beaconId: 'b1',
          unseenCount: 1,
          latestUnseen: optional,
        ),
      ]
      ..clearResultBuilder = (operationId, _) => AttentionClearResult(
        operationId: operationId,
        status: AttentionOperationStatus.partial,
        skippedReceiptIds: const ['r-opt'],
      );
    final cubit = await boot(attentionRepo);

    await cubit.clearOptionalEvent('b1', 'r-opt');

    expect(cubit.state.attentionByBeacon['b1']!.latestUnseen?.id, 'r-opt');
    expect(cubit.state.attentionByBeacon['b1']!.unseenCount, 1);

    await cubit.close();
  });

  test(
    'an applied clear adopts the server projection, next preview included',
    () async {
      final first = receipt(id: 'r-1', beaconId: 'b1');
      final second = receipt(id: 'r-2', beaconId: 'b1');
      final attentionRepo = StubAttentionRepository()
        ..myWorkAttentionResult = [
          MyWorkBeaconAttention(
            beaconId: 'b1',
            unseenCount: 3,
            latestUnseen: first,
          ),
        ];
      final cubit = await boot(attentionRepo);

      // What the server will say once `r-1` is cleared: two left, and the
      // next one to preview is `r-2`. The client cannot derive this — it
      // holds one preview, not the list — which is why it has to re-read.
      attentionRepo.myWorkAttentionAfterClear = [
        MyWorkBeaconAttention(
          beaconId: 'b1',
          unseenCount: 2,
          latestUnseen: second,
        ),
      ];

      await cubit.clearOptionalEvent('b1', 'r-1');

      final entry = cubit.state.attentionByBeacon['b1']!;
      expect(entry.latestUnseen?.id, 'r-2');
      expect(entry.unseenCount, 2);

      final view = myWorkCardAttentionView(
        beaconId: 'b1',
        attention: entry,
        viewerArchived: false,
      );
      expect(
        view.optionalTotal,
        2,
        reason: 'a card with two uncleared events left has a row to render '
            'and a number beside it',
      );

      await cubit.close();
    },
  );

  test('a failed clear restores the row before it rethrows', () async {
    final optional = receipt(id: 'r-opt', beaconId: 'b1');
    final attentionRepo = StubAttentionRepository()
      ..myWorkAttentionResult = [
        MyWorkBeaconAttention(
          beaconId: 'b1',
          unseenCount: 1,
          latestUnseen: optional,
        ),
      ]
      ..clearError = StateError('offline');
    final cubit = await boot(attentionRepo);

    await expectLater(
      cubit.clearOptionalEvent('b1', 'r-opt'),
      throwsStateError,
    );
    expect(cubit.state.attentionByBeacon['b1']!.latestUnseen?.id, 'r-opt');

    await cubit.close();
  });
}
