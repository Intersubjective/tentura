import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/invitation/domain/invite_code.dart';

void main() {
  group('normalizeInviteCode', () {
    test('strips trailing dash', () {
      expect(normalizeInviteCode('I806d29daebbe-'), 'I806d29daebbe');
    });

    test('strips multiple trailing dashes', () {
      expect(normalizeInviteCode('Iabc--'), 'Iabc');
    });

    test('trims whitespace', () {
      expect(normalizeInviteCode('  Iabc123  '), 'Iabc123');
    });
  });

  group('extractInviteCodeFromText', () {
    test('accepts raw code with trailing dash', () {
      expect(
        extractInviteCodeFromText('I806d29daebbe-', prefix: 'I'),
        'I806d29daebbe',
      );
    });

    test('accepts full invite URL with trailing dash in path', () {
      expect(
        extractInviteCodeFromText(
          'https://dev.tentura.io/invite/I806d29daebbe-',
          prefix: 'I',
        ),
        'I806d29daebbe',
      );
    });

    test('rejects non-invite text', () {
      expect(extractInviteCodeFromText('not-an-invite', prefix: 'I'), isNull);
    });

    test('extracts code from full URL without prefix', () {
      expect(
        extractInviteCodeFromText(
          'https://dev.tentura.io/invite/I806d29daebbe',
        ),
        'I806d29daebbe',
      );
    });

    test('does not treat URL substring as direct code', () {
      expect(
        isValidInviteCode('https://dev.tentura.io/invite/I806d29daebbe'),
        isFalse,
      );
    });
  });

  group('inviteCodeHadTrailingDash', () {
    test('detects trailing dash', () {
      expect(inviteCodeHadTrailingDash('I806d29daebbe-'), isTrue);
    });

    test('ignores normalized code', () {
      expect(inviteCodeHadTrailingDash('I806d29daebbe'), isFalse);
    });
  });
}
