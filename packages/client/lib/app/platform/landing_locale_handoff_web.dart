import 'package:web/web.dart' as web;

import 'package:tentura/consts.dart';

import 'landing_locale_handoff_logic.dart';

/// Reads `?lang=en|ru` from the top-level query (not the hash route).
String? readLandingLangQueryParam() {
  final lang = Uri.base.queryParameters[kLandingLangQueryParam];
  return normalizeLandingLangQuery(lang);
}

/// Drops `lang` from the address bar after the app has read it (#875).
void stripLandingLangQueryParam() {
  if (kQaIntegrationTestMode) {
    return;
  }
  final loc = web.window.location;
  final uri = Uri.parse(loc.href);
  if (!uri.queryParameters.containsKey(kLandingLangQueryParam)) {
    return;
  }
  final query = Map<String, String>.from(uri.queryParameters)
    ..remove(kLandingLangQueryParam);
  final queryPart = query.isEmpty
      ? ''
      : '?${Uri(queryParameters: query).query}';
  final fragment = uri.fragment.isEmpty ? '' : '#${uri.fragment}';
  web.window.history.replaceState(null, '', '${uri.path}$queryPart$fragment');
}
