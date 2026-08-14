import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/domain/attention/destination_map.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';

void main() {
  AttentionReceipt receipt({
    required String destinationKind,
    required String targetEntityId,
    String? beaconId,
    String actionUrl = '/beacon/view/Bfallback',
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
    presentationPayloadJson: '{}',
    beaconId: beaconId,
    destinationKind: destinationKind,
    targetEntityId: targetEntityId,
  );

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

  test('directed room message keeps message only for host canonicalization', () {
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
  });

  test('received reviews destination uses beacon id path', () {
    final uri = attentionDestination(
      receipt(
        destinationKind: 'received_reviews',
        targetEntityId: 'B1',
        beaconId: 'B1',
        actionUrl: '/beacon/reviews-received/Bfallback',
      ),
    );

    expect(uri.path, '$kPathReceivedReviews/B1');
  });

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
