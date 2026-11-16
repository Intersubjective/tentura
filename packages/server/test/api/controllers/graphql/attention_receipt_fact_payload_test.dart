import 'dart:convert';

import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/query/query_attention.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/entity/notification_category.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/entity/notification_priority.dart';

/// The attention feed serves only the payload keys it knows. The facts a
/// notice needs (new deadline, previous status, related Request, stale
/// reason, expiry, backup flag, plan-step offset, closure epoch/result) must
/// survive the feed mapper with their stored JSON types.
void main() {
  Map<String, Object?> served(Map<String, Object?> stored) {
    final mapped = QueryAttention.mapReceiptForTesting(_receipt(stored));
    return jsonDecode(mapped['presentationPayloadJson']! as String)
        as Map<String, Object?>;
  }

  group('attention feed payload facts', () {
    test('a deadline notice keeps its new deadline', () {
      const stored = <String, Object?>{
        'eventType': 'deadlineChanged',
        'newEndAt': '2026-11-21T15:00:00.000Z',
      };
      expect(served(stored), stored);
    });

    test('a status notice keeps the previous status', () {
      const stored = <String, Object?>{
        'eventType': 'requestStatusChanged',
        'toStatus': 'cancelled',
        'fromStatus': 'open',
      };
      expect(served(stored), stored);
    });

    test('a hierarchy notice keeps the related Request and direction', () {
      const stored = <String, Object?>{
        'eventType': 'beaconHierarchyStatusChanged',
        'relatedBeaconId': 'Brelated00001',
        'direction': 'child',
      };
      expect(served(stored), stored);
    });

    test('a stale reminder keeps why it is stale and when it was due', () {
      const stored = <String, Object?>{
        'eventType': 'requestStale',
        'staleReason': 'deadlinePassed',
        'endAt': '2026-11-14T09:30:00.000Z',
      };
      expect(served(stored), stored);
    });

    test('a Post expiry warning keeps when the Post expires', () {
      const stored = <String, Object?>{
        'eventType': 'postExpiringSoon',
        'expiresAt': '2026-11-16T15:00:00.000Z',
      };
      expect(served(stored), stored);
    });

    test('integer facts stay integers', () {
      const stored = <String, Object?>{
        'eventType': 'requestStale',
        'quietDays': 20,
        'relativeMinutes': 15,
      };

      final payload = served(stored);

      expect(payload['quietDays'], 20);
      expect(payload['relativeMinutes'], 15);
    });

    test('the backup-offer flag stays a bool', () {
      final payload = served(const {
        'eventType': 'helpOfferSubmitted',
        'isBackupOffer': true,
      });

      expect(payload['isBackupOffer'], true);
    });

    test('closure receipts keep epoch, outcome, band and draft flag', () {
      const stored = <String, Object?>{
        'eventType': 'closureFinalized',
        'epoch': 3,
        'outcome': 2,
        'band': 1,
        'draftFlag': 1,
      };

      expect(served(stored), stored);
    });

    test('the allow-list validator accepts every fact with its stored type', () {
      expect(
        () => QueryAttention.validateAttentionPresentationPayload(const {
          'eventType': 'requestStale',
          'newEndAt': '2026-11-21T15:00:00.000Z',
          'fromStatus': 'open',
          'relatedBeaconId': 'Brelated00001',
          'direction': 'ancestor',
          'staleReason': 'quiet',
          'quietDays': 20,
          'endAt': '2026-11-14T09:30:00.000Z',
          'expiresAt': '2026-11-16T15:00:00.000Z',
          'isBackupOffer': false,
          'relativeMinutes': 45,
          'epoch': 3,
          'outcome': 2,
          'band': 1,
          'draftFlag': 0,
        }),
        returnsNormally,
      );
    });

    for (final wrong in <(String, Object)>[
      ('quietDays', '20'),
      ('relativeMinutes', '15'),
      ('isBackupOffer', 'true'),
      ('epoch', '3'),
      ('newEndAt', 20),
      ('staleReason', true),
    ]) {
      test('${wrong.$1} with the wrong JSON type is refused', () {
        expect(
          () => QueryAttention.validateAttentionPresentationPayload({
            'eventType': 'requestStale',
            wrong.$1: wrong.$2,
          }),
          throwsStateError,
        );
      });
    }
  });
}

AttentionReceipt _receipt(Map<String, Object?> payload) => AttentionReceipt(
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
  presentationPayload: payload,
  surface: AttentionSurface.activity,
  beaconId: 'beacon-1',
);
