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

  group('extractEntityIdFromText', () {
    test('accepts a bare id of any shareable kind', () {
      expect(extractEntityIdFromText(' U9828d11a1555 '), 'U9828d11a1555');
      expect(extractEntityIdFromText('B65bdcbaa3a6e'), 'B65bdcbaa3a6e');
      expect(extractEntityIdFromText('I806d29daebbe-'), 'I806d29daebbe');
    });

    test('reads the id from a profile share link (scanned QR)', () {
      expect(
        extractEntityIdFromText(
          'https://dev.tentura.io/profile/view/U9828d11a1555',
        ),
        'U9828d11a1555',
      );
    });

    test('reads hash-routed request links and invite links', () {
      expect(
        extractEntityIdFromText(
          'https://dev.tentura.io/#/beacon/view/B65bdcbaa3a6e?tab=people',
        ),
        'B65bdcbaa3a6e',
      );
      expect(
        extractEntityIdFromText('https://dev.tentura.io/invite/I806d29daebbe'),
        'I806d29daebbe',
      );
    });

    test('still accepts legacy ?id= links', () {
      expect(
        extractEntityIdFromText(
          'https://dev.tentura.io/profile/view/U9828d11a1555?id=U9828d11a1555',
        ),
        'U9828d11a1555',
      );
      expect(
        extractEntityIdFromText('https://dev.tentura.io/x?id=U9828d11a1555'),
        'U9828d11a1555',
      );
    });

    test('rejects text without a whole id', () {
      expect(extractEntityIdFromText('hello'), isNull);
      expect(extractEntityIdFromText('U9828d11a15'), isNull);
      expect(
        extractEntityIdFromText(
          'https://dev.tentura.io/profile/view/U9828d11a1555ff',
        ),
        isNull,
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
