import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/domain/attention/destination_map.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';

void main() {
  AttentionReceipt receipt({
    required String destinationKind,
    required String targetEntityId,
    String? beaconId,
    String? presentationKey,
    String actionUrl = '/beacon/view/Bfallback',
    String presentationPayloadJson = '{}',
    String? coordinationItemId,
  }) => AttentionReceipt(
    id: 'N1',
    category: 'coordination',
    kind: 'roomMessagePosted',
    priority: 'standard',
    title: 'Title',
    body: 'Body',
    actionUrl: actionUrl,
    createdAt: DateTime.utc(2026),
    collapsedCount: 1,
    presentationKey: presentationKey,
    presentationPayloadJson: presentationPayloadJson,
    coordinationItemId: coordinationItemId,
    surface: AttentionSurface.activity,
    beaconId: beaconId,
    destinationKind: destinationKind,
    targetEntityId: targetEntityId,
  );

  test('plan events open the Plan tab on their step (#220)', () {
    final uri = attentionDestination(
      receipt(
        destinationKind: 'beacon',
        targetEntityId: 'B1',
        beaconId: 'B1',
        presentationKey: 'plan_step_due',
        presentationPayloadJson: '{"eventType":"planStepDue"}',
        coordinationItemId: 'PS1',
      ),
    );
    expect(uri.path, '$kPathBeaconView/B1');
    expect(uri.queryParameters[kQueryBeaconViewTab], kBeaconViewTabPlan);
    expect(uri.queryParameters[kQueryPlanStepId], 'PS1');
  });

  test('a plan event without a step opens the Plan tab only', () {
    final uri = attentionDestination(
      receipt(
        destinationKind: 'beacon',
        targetEntityId: 'B1',
        beaconId: 'B1',
        presentationKey: 'plan_edited',
      ),
    );
    expect(uri.queryParameters[kQueryBeaconViewTab], kBeaconViewTabPlan);
    expect(uri.queryParameters.containsKey(kQueryPlanStepId), isFalse);
  });

  test('other beacon events still open the Request as before', () {
    final uri = attentionDestination(
      receipt(
        destinationKind: 'beacon',
        targetEntityId: 'B1',
        presentationKey: 'request_status_changed',
      ),
    );
    expect(uri.toString(), '$kPathBeaconView/B1');
  });

  test('beacon_room opens General on threads tab', () {
    final uri = attentionDestination(
      receipt(
        destinationKind: 'beacon_room',
        targetEntityId: 'ignored',
        beaconId: 'B1',
      ),
    );

    expect(uri.path, '$kPathBeaconView/B1');
    expect(uri.queryParameters[kQueryBeaconViewTab], kBeaconViewTabThreads);
    expect(
      uri.queryParameters[kQueryThreadId],
      RequestThread.generalId,
    );
  });

  test(
    'directed room message keeps message only for host canonicalization',
    () {
      final uri = attentionDestination(
        receipt(
          destinationKind: 'beacon_room_message',
          targetEntityId: 'M1',
          beaconId: 'B1',
        ),
      );

      expect(uri.path, '$kPathBeaconView/B1');
      expect(uri.queryParameters[kQueryBeaconViewTab], kBeaconViewTabThreads);
      expect(uri.queryParameters[kQueryMessageId], 'M1');
      expect(uri.queryParameters.containsKey(kQueryThreadId), isFalse);
    },
  );

  test('unknown destination retains the server action url', () {
    expect(
      attentionDestination(
        receipt(
          destinationKind: 'future_kind',
          targetEntityId: 'T1',
          actionUrl: '/profile/view/U1',
        ),
      ).toString(),
      '/profile/view/U1',
    );
  });
}
