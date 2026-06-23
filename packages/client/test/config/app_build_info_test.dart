import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/config/app_build_info.dart';
import 'package:tentura/config/build_id.dart';

void main() {
  group('sanitizeBuildId', () {
    test('returns empty for blank input', () {
      expect(sanitizeBuildId(''), '');
      expect(sanitizeBuildId('   '), '');
    });

    test('strips non-alphanumeric characters', () {
      expect(sanitizeBuildId('feat/x-9'), 'featx9');
    });

    test('truncates to 12 characters', () {
      expect(
        sanitizeBuildId('abcdef1234567890'),
        'abcdef123456',
      );
    });
  });

  group('AppBuildInfo.formatVisibleVersionLabel', () {
    test('returns semver only when metadata is empty', () {
      expect(
        AppBuildInfo.formatVisibleVersionLabel(
          '2.4.0',
          gitShaOverride: '',
          buildDateOverride: '',
        ),
        '2.4.0',
      );
    });

    test('appends shortened git SHA', () {
      expect(
        AppBuildInfo.formatVisibleVersionLabel(
          '2.4.0',
          gitShaOverride: 'abcdef1234567890',
          buildDateOverride: '',
        ),
        '2.4.0 · abcdef123456',
      );
    });

    test('appends git SHA and build date', () {
      expect(
        AppBuildInfo.formatVisibleVersionLabel(
          '2.4.0',
          gitShaOverride: 'abcdef1234567890',
          buildDateOverride: '2026-06-23',
        ),
        '2.4.0 · abcdef123456 · 2026-06-23',
      );
    });
  });
}
