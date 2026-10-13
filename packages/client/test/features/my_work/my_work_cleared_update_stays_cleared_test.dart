import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/entity/my_work_beacon_attention.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_cubit.dart';

import '../../support/test_realtime_sync.dart';
import 'my_work_slow_desk_read_support.dart';
import 'my_work_test_support.dart';

void main() {
  AttentionReceipt receipt({required String id, required String beaconId}) =>
      AttentionReceipt(
        id: id,
        category: 'coordination',
        kind: 'update',
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

  late TestRealtimeSyncPort sync;
  late RealtimeSyncCase realtime;
  late SlowDeskReadAttentionRepository attentionRepo;
  late MyWorkCubit cubit;

  setUp(() async {
    final harness = buildTestRealtimeSync();
    sync = harness.port;
    realtime = harness.case_;
    attentionRepo = SlowDeskReadAttentionRepository()
      ..myWorkAttentionResult = [
        MyWorkBeaconAttention(
          beaconId: 'bA',
          unseenCount: 1,
          latestUnseen: receipt(id: 'r-a', beaconId: 'bA'),
        ),
        MyWorkBeaconAttention(
          beaconId: 'bB',
          unseenCount: 1,
          latestUnseen: receipt(id: 'r-b', beaconId: 'bB'),
        ),
      ];
    final repo = FakeMyWorkRepository()
      ..initResult = (
        authoredNonArchived: [
          Beacon.empty.copyWith(id: 'bA'),
          Beacon.empty.copyWith(id: 'bB'),
        ],
        helpOfferedNonArchived: const [],
        obligationBeacons: const [],
        archivedCountHint: 0,
      );
    cubit = MyWorkCubit(
      userId: 'user-1',
      myWorkCase: buildTestMyWorkCase(
        repo: repo,
        attentionRepository: attentionRepo,
        realtimeSyncCase: realtime,
      ),
      realtimeSyncCase: realtime,
    );
    await cubit.stream.firstWhere((s) => s.attentionLoaded);
  });

  tearDown(() async {
    await cubit.close();
    await sync.dispose();
  });

  group('a cleared optional update', () {
    test(
      'is not restored by a desk-wide read that started before the clear',
      () async {
        await cubit.clearOptionalEvent('bA', 'r-a');

        // The server's change notification for that first clear makes the desk
        // re-read everything; the answer to that read is slow.
        attentionRepo.holdNextRead();
        sync.emitChange(
          const RealtimeEntityChange(
            kind: RealtimeEntityKind.notification,
            aggregateId: 'r-a',
            operation: RealtimeOperation.update,
            source: RealtimeChangeSource.serverInvalidation,
          ),
        );
        await attentionRepo.readIsHeld;

        await cubit.clearOptionalEvent('bB', 'r-b');
        attentionRepo.releaseHeldRead();
        await pumpEventQueue();

        expect(attentionRepo.clearCalls, hasLength(2));
        expect(
          cubit.state.attentionByBeacon['bB']?.latestUnseen,
          isNull,
          reason:
              'the older read must not bring back a row the user cleared '
              'and the server confirmed',
        );
      },
    );
  });
}
