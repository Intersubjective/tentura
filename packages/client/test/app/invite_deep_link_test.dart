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

    test('non-invite path is unchanged', () {
      final uri = Uri.parse('/home/network');
      expect(
        transformInviteDeepLink(uri: uri, isAuthenticated: true),
        uri,
      );
    });

    test('invite id not starting with I is unchanged', () {
      final uri = Uri.parse('/invite/abc123');
      expect(
        transformInviteDeepLink(uri: uri, isAuthenticated: true),
        uri,
      );
    });

    test('decodes percent-encoded invite id', () {
      final out = transformInviteDeepLink(
        uri: Uri.parse('/invite/I%2Fabc'),
        isAuthenticated: false,
      );
      expect(out.path, '$kPathSignUp/I/abc');
    });
  });

  group('transformSharedViewInviteDeepLink', () {
    test('authenticated maps shared view invite to accept-invite', () {
      final out = transformSharedViewInviteDeepLink(
        uri: Uri.parse('/shared/view?id=Iabc'),
        id: 'Iabc',
        isAuthenticated: true,
      );
      expect(out.path, '$kPathAcceptInvite/Iabc');
    });

    test('anonymous maps shared view invite to sign-up', () {
      final out = transformSharedViewInviteDeepLink(
        uri: Uri.parse('/shared/view?id=Iabc'),
        id: 'Iabc',
        isAuthenticated: false,
      );
      expect(out.path, '$kPathSignUp/Iabc');
    });
  });
}
