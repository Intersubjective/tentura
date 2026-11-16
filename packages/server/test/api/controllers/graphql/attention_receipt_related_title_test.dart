import 'package:graphql_schema2/graphql_schema2.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/custom_types.dart';
import 'package:tentura_server/api/controllers/graphql/query/query_attention.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/entity/notification_category.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/entity/notification_priority.dart';

/// The related Request's title (access-gated upstream) is declared on the
/// AttentionReceipt type and served on top-level rows and inside the grouped
/// row's event previews.
void main() {
  group('AttentionReceipt GraphQL type', () {
    test('declares the related Request title as a nullable string', () {
      final fields = {
        for (final field in gqlTypeAttentionReceipt.fields) field.name: field,
      };

      expect(fields['relatedBeaconTitle']?.type, same(graphQLString));
    });
  });

  group('attention feed related Request title', () {
    // The values themselves come from the repository; the pg suite drives them
    // through this mapper. Here: the key is always on the wire.
    test('a receipt without one serves an explicit null', () {
      final mapped = QueryAttention.mapReceiptForTesting(_receipt());

      expect(mapped, containsPair('relatedBeaconTitle', null));
    });

    test('event previews carry the key too', () {
      final mapped = QueryAttention.mapReceiptForTesting(
        _receipt(eventsPreview: [_receipt()]),
      );

      final preview = (mapped['eventsPreview']! as List).single as Map;
      expect(preview, containsPair('relatedBeaconTitle', null));
    });
  });
}

AttentionReceipt _receipt({
  List<AttentionReceipt> eventsPreview = const [],
}) => AttentionReceipt(
  id: 'receipt-1',
  accountId: 'account-1',
  category: NotificationCategory.coordination,
  kind: NotificationKind.commitmentAccepted,
  priority: NotificationPriority.normal,
  title: 'Title',
  body: 'Body',
  actionUrl: '/#/beacon/beacon-1',
  createdAt: DateTime.utc(2026, 11, 16),
  collapsedCount: 1,
  suppressionClass: AttentionSuppressionClass.standard,
  accessPolicy: AttentionAccessPolicy.beaconContent,
  presentationPayload: const {},
  surface: AttentionSurface.activity,
  beaconId: 'beacon-1',
  eventsPreview: eventsPreview,
);
