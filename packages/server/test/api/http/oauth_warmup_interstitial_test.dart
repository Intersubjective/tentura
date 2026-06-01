import 'package:test/test.dart';

import 'package:tentura_server/api/http/oauth_warmup_interstitial_page.dart';

void main() {
  test('renderOAuthWarmupInterstitial embeds redirect and asset URLs', () {
    final html = renderOAuthWarmupInterstitial(
      redirectUri: 'https://accounts.google.com/o/oauth2/v2/auth',
    );
    expect(html, contains('tentura-app-cache-sw.js'));
    expect(html, contains('wasm-preload-manifest.json'));
    expect(html, contains('https://accounts.google.com/o/oauth2/v2/auth'));
    expect(html, contains('caches.open'));
  });
}
