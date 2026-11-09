import 'package:test/test.dart';
import 'package:tentura/app/router/invite_deep_link.dart';
import 'package:tentura/consts.dart';

void main() {
  group('transformInviteDeepLink', () {
    test('authenticated maps /invite/Iabc to accept-invite', () {
      final out = transformInviteDeepLink(
        uri: Uri.parse('/invite/Iabc123'),
        isAuthenticated: true,
      );
      expect(out.path, '$kPathAcceptInvite/Iabc123');
      expect(out.queryParameters[kQueryIsDeepLink], 'true');
    });

    test('anonymous maps /invite/Iabc to sign-up', () {
      final out = transformInviteDeepLink(
        uri: Uri.parse('/invite/Iabc123'),
        isAuthenticated: false,
      );
      expect(out.path, '$kPathSignUp/Iabc123');
      expect(out.queryParameters[kQueryIsDeepLink], 'true');
    });

    test(
      'keeps trailing dash in invite id for accept-invite validation (#1124)',
      () {
        final out = transformInviteDeepLink(
          uri: Uri.parse('/invite/IQAFX0000000-'),
          isAuthenticated: true,
        );
        expect(out.path, '$kPathAcceptInvite/IQAFX0000000-');
        expect(out.queryParameters[kQueryIsDeepLink], 'true');
      },
    );

    test('keeps trailing dash on signup deep link (#1124)', () {
      final out = transformInviteDeepLink(
        uri: Uri.parse('/invite/I806d29daebbe-'),
        isAuthenticated: false,
      );
      expect(out.path, '$kPathSignUp/I806d29daebbe-');
    });

    test('non-invite path is unchanged', () {
      final uri = Uri.parse('/home/network');
      expect(
        transformInviteDeepLink(uri: uri, isAuthenticated: true),
        uri,
      );
    });

    test(
      'malformed invite id routes to accept-invite when signed in (#1124)',
      () {
        final out = transformInviteDeepLink(
          uri: Uri.parse('/invite/BADCODE123'),
          isAuthenticated: true,
        );
        expect(out.path, '$kPathAcceptInvite/BADCODE123');
        expect(out.queryParameters[kQueryIsDeepLink], 'true');
      },
    );

    test('malformed invite id routes to sign-up when signed out (#1124)', () {
      final out = transformInviteDeepLink(
        uri: Uri.parse('/invite/BADCODE123'),
        isAuthenticated: false,
      );
      expect(out.path, '$kPathSignUp/BADCODE123');
      expect(out.queryParameters[kQueryIsDeepLink], 'true');
    });

    test('invite segment without I prefix still routes (#1124)', () {
      final out = transformInviteDeepLink(
        uri: Uri.parse('/invite/abc123'),
        isAuthenticated: true,
      );
      expect(out.path, '$kPathAcceptInvite/abc123');
    });

    test('decodes percent-encoded invite id', () {
      final out = transformInviteDeepLink(
        uri: Uri.parse('/invite/I%2Fabc'),
        isAuthenticated: false,
      );
      expect(out.path, '$kPathSignUp/I/abc');
    });
  });
}
