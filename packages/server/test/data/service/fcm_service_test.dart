import 'package:test/test.dart';

import 'package:tentura_server/data/service/fcm_service.dart';

void main() {
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
