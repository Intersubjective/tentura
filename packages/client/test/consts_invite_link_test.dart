import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/consts.dart';

void main() {
  group('resolveInviteLinkHost', () {
    test('uses explicit host when set', () {
      expect(
        resolveInviteLinkHost(
          inviteLinkHost: 'https://dev.tentura.io',
          serverName: 'https://app.dev.tentura.io',
        ),
        'https://dev.tentura.io',
      );
    });

    test('empty invite host derives landing from app subdomain', () {
      expect(
        resolveInviteLinkHost(
          inviteLinkHost: '',
          serverName: 'https://app.dev.tentura.io',
        ),
        'https://dev.tentura.io',
      );
    });

    test('empty invite host keeps localhost server name', () {
      expect(
        resolveInviteLinkHost(
          inviteLinkHost: '',
          serverName: 'http://localhost:2080',
        ),
        'http://localhost:2080',
      );
    });
  });
}
