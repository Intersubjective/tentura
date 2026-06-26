import 'dart:convert';

/// Parses the semver from a Flutter web `version.json` build artifact.
String? parseWebAppVersionFromJson(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) return null;
    final version = decoded['version'];
    if (version is! String || version.isEmpty) return null;
    return version;
  } on Object {
    return null;
  }
}
