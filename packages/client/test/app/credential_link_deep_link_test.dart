import 'package:test/test.dart';
import 'package:tentura/app/router/credential_link_deep_link.dart';
import 'package:tentura/consts.dart';

void main() {
  group('transformCredentialLinkDeepLink', () {
    test('hash fragment OAuth return maps to credentials route', () {
      final out = transformCredentialLinkDeepLink(
        uri: Uri.parse(
          'https://app.example/#/settings/sign-in-methods?linked=google',
        ),
      );
      expect(out.path, kPathSignInMethods);
      expect(out.queryParameters[kQueryCredentialLinked], 'google');
    });

    test('path-based link is unchanged', () {
      final uri = Uri.parse('/settings/sign-in-methods?linked=email');
      expect(transformCredentialLinkDeepLink(uri: uri), uri);
    });

    test('unrelated URI is unchanged', () {
      final uri = Uri.parse('/home/network');
      expect(transformCredentialLinkDeepLink(uri: uri), uri);
    });
  });
}
