import 'package:graphql_schema2/graphql_schema2.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/custom_types.dart';
import 'package:tentura_server/api/controllers/graphql/query/query_attention.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/entity/notification_category.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/entity/notification_priority.dart';

/// The Post fields of an attention receipt (beacon kind, root excerpt, root
/// image) must reach the wire: a field the SDL does not declare or the mapper
/// does not copy never gets to the client.
void main() {
  group('AttentionReceipt GraphQL type', () {
    test(
      'declares the beacon kind as an Int and the root fields as strings',
      () {
        final fields = {
          for (final field in gqlTypeAttentionReceipt.fields) field.name: field,
        };

        expect(fields['beaconKind']?.type, same(graphQLInt));
        expect(fields['postRootExcerpt']?.type, same(graphQLString));
        expect(fields['postRootImageId']?.type, same(graphQLString));
      },
    );
  });

  group('AttentionReceipt GraphQL mapping', () {
    test('a Post receipt maps kind 1, the root excerpt and the image id', () {
      final mapped = QueryAttention.mapReceiptForTesting(
        _receipt(
          beaconKind: BeaconKind.post,
          postRootExcerpt: 'Heads up, the bridge is closed',
          postRootImageId: '11111111-1111-4111-8111-111111111111',
        ),
      );

      expect(mapped['beaconKind'], 1);
      expect(mapped['postRootExcerpt'], 'Heads up, the bridge is closed');
      expect(mapped['postRootImageId'], '11111111-1111-4111-8111-111111111111');
    });

    test('a Request receipt maps kind 0 and null root fields', () {
      final mapped = QueryAttention.mapReceiptForTesting(
        _receipt(beaconKind: BeaconKind.request),
      );

      expect(mapped['beaconKind'], 0);
      expect(mapped['postRootExcerpt'], isNull);
      expect(mapped['postRootImageId'], isNull);
    });
  });
}

AttentionReceipt _receipt({
  required BeaconKind beaconKind,
  String? postRootExcerpt,
  String? postRootImageId,
}) => AttentionReceipt(
  id: 'receipt-1',
  accountId: 'account-1',
  category: NotificationCategory.coordination,
  kind: NotificationKind.commitmentAccepted,
  priority: NotificationPriority.normal,
  title: 'Title',
  body: 'Body',
  actionUrl: '/#/beacon/beacon-1',
  createdAt: DateTime.utc(2026, 8, 4),
  collapsedCount: 1,
  suppressionClass: AttentionSuppressionClass.standard,
  accessPolicy: AttentionAccessPolicy.beaconContent,
  presentationPayload: const {'eventType': 'commitmentAccepted'},
  surface: AttentionSurface.activity,
  beaconId: 'beacon-1',
  beaconKind: beaconKind,
  postRootExcerpt: postRootExcerpt,
  postRootImageId: postRootImageId,
);
