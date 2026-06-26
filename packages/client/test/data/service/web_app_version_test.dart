import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/data/service/web_app_version_parser.dart';

void main() {
  group('parseWebAppVersionFromJson', () {
    test('returns semver from valid version.json body', () {
      expect(
        parseWebAppVersionFromJson(
          '{"app_name":"Tentura","version":"4.0.0","build_number":"1"}',
        ),
        '4.0.0',
      );
    });

    test('returns null when version key is missing', () {
      expect(
        parseWebAppVersionFromJson('{"app_name":"Tentura","build_number":"1"}'),
        isNull,
      );
    });

    test('returns null when version is empty', () {
      expect(
        parseWebAppVersionFromJson(
          '{"app_name":"Tentura","version":"","build_number":"1"}',
        ),
        isNull,
      );
    });

    test('returns null for invalid JSON', () {
      expect(parseWebAppVersionFromJson('not-json'), isNull);
    });
  });
}
