import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

import 'web_app_version_parser.dart';

/// Reads app semver from root `/version.json` (same-origin).
///
/// Avoids `package_info_plus` on web, which corrupts `/app-assets/` URLs when
/// resolving `AssetManager.baseUrl`.
Future<String> getWebAppVersion() async {
  try {
    final cacheBuster = DateTime.now().millisecondsSinceEpoch;
    final url = Uri.parse(
      '${web.window.location.origin}/version.json?cachebuster=$cacheBuster',
    );
    final response = await http.get(url);
    if (response.statusCode != 200) return '';
    return parseWebAppVersionFromJson(response.body) ?? '';
  } on Object {
    return '';
  }
}
