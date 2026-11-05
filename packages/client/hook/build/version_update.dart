// ignore_for_file: avoid_print //

import 'dart:io';
import 'dart:convert';
import 'package:pubspec_parse/pubspec_parse.dart';

/// Writes [version] (defaults to the pubspec version) into the built web entry
/// files in [webDir]: the `flutter_bootstrap.js?v=` cache-busting query in
/// `index.html`, and — when [includeManifest] is set — the PWA
/// `manifest.json` `version`.
///
/// Called by the post-build tool after compilation so the deployed bootstrap
/// query matches the service-worker cache version. Source `web/` files keep
/// their release-independent values.
void versionUpdate({
  String webDir = 'build/web',
  String? version,
  bool includeManifest = true,
}) {
  final resolved =
      version ??
      Pubspec.parse(File('pubspec.yaml').readAsStringSync()).version.toString();
  print('Web build version: $resolved');

  if (includeManifest) {
    _updateManifestVersion('$webDir/manifest.json', resolved);
  }
  _updateIndexBootstrap('$webDir/index.html', resolved);
}

void _updateManifestVersion(String path, String version) {
  final file = File(path);
  if (!file.existsSync()) return;
  final manifest = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  if (manifest['version'] == version) return;
  manifest['version'] = version;
  file.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(manifest),
    flush: true,
  );
  print('Updated $path');
}

// Surgical replace of the bootstrap query only — avoids reserializing the
// final build/web/index.html artifact (which would normalize formatting).
void _updateIndexBootstrap(String path, String version) {
  final file = File(path);
  if (!file.existsSync()) return;
  final html = file.readAsStringSync();
  final pattern = RegExp(r'''flutter_bootstrap\.js(\?v=[^"']*)?''');
  if (!pattern.hasMatch(html)) return;
  final updated = html.replaceFirst(pattern, 'flutter_bootstrap.js?v=$version');
  if (updated != html) {
    file.writeAsStringSync(updated, flush: true);
    print('Updated $path');
  }
}
