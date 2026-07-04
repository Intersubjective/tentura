import 'package:test/test.dart';

import 'package:tentura_server/data/service/fcm_service.dart';
import 'package:tentura_server/domain/entity/fcm_message_entity.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/entity/notification_priority.dart';

void main() {
  group(
    'buildFcmMessagePayload '
    '(regression: consistent explicit display across browsers — see '
    'docs/qa-push-testing.md "Data-only push payloads")',
    () {
      test('never includes a top-level notification field', () {
        final payload = buildFcmMessagePayload(
          fcmToken: 'tok-1',
          message: const FcmNotificationEntity(title: 'Hi', body: 'There'),
        );

        final message = payload['message']! as Map<String, Object?>;
        expect(message.containsKey('notification'), isFalse);
      });

      test('sends title/body/link/kind/priority/beaconId/item as data '
          'strings', () {
        final payload = buildFcmMessagePayload(
          fcmToken: 'tok-1',
          message: const FcmNotificationEntity(
            title: 'Hi',
            body: 'There',
            imageUrl: 'https://example.com/x.png',
            actionUrl: '/shared/view?id=B1&dest=room',
            beaconId: 'B1',
            coordinationItemId: 'I1',
            kind: NotificationKind.needsMe,
            priority: NotificationPriority.high,
          ),
        );

        final message = payload['message']! as Map<String, Object?>;
        expect(message['data'], {
          'title': 'Hi',
          'body': 'There',
          'image': 'https://example.com/x.png',
          'link': '/shared/view?id=B1&dest=room',
          'kind': NotificationKind.needsMe.name,
          'priority': NotificationPriority.high.name,
          'beaconId': 'B1',
          'item': 'I1',
        });
      });

      test('omits optional data fields entirely when absent, rather than '
          'sending null', () {
        final payload = buildFcmMessagePayload(
          fcmToken: 'tok-1',
          message: const FcmNotificationEntity(title: 'Hi', body: 'There'),
        );

        final message = payload['message']! as Map<String, Object?>;
        expect(message['data'], {'title': 'Hi', 'body': 'There'});
      });
    },
  );

  group('extractFcmErrorCode', () {
    test('reads errorCode from a THIRD_PARTY_AUTH_ERROR body', () {
      const body = '''
{
  "error": {
    "code": 401,
    "message": "Third party auth error.",
    "status": "UNAUTHENTICATED",
    "details": [
      {
        "@type": "type.googleapis.com/google.firebase.fcm.v1.FcmError",
        "errorCode": "THIRD_PARTY_AUTH_ERROR"
      }
    ]
  }
}
''';

      expect(extractFcmErrorCode(body), 'THIRD_PARTY_AUTH_ERROR');
    });

    test('returns null for a 401 with no FcmError detail (bad access token)', () {
      const body = '''
{
  "error": {
    "code": 401,
    "message": "Request had invalid authentication credentials.",
    "status": "UNAUTHENTICATED"
  }
}
''';

      expect(extractFcmErrorCode(body), isNull);
    });

    test('returns null for a detail list without an FcmError entry', () {
      const body = '''
{
  "error": {
    "code": 400,
    "message": "Bad request",
    "details": [
      {"@type": "type.googleapis.com/google.rpc.BadRequest"}
    ]
  }
}
''';

      expect(extractFcmErrorCode(body), isNull);
    });

    test('returns null for non-JSON or malformed bodies without throwing', () {
      expect(extractFcmErrorCode('not json'), isNull);
      expect(extractFcmErrorCode(''), isNull);
      expect(extractFcmErrorCode('{"error": "not a map"}'), isNull);
    });
  });
}
