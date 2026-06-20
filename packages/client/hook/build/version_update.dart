// ignore_for_file: avoid_print //

import 'dart:io';
import 'dart:convert';
import 'package:pubspec_parse/pubspec_parse.dart';

/// Writes [version] (defaults to the pubspec version) into the web app entry
/// files in [webDir]: the PWA `manifest.json` `version` and the
/// `flutter_bootstrap.js?v=` cache-busting query in `index.html`.
///
/// Works on both the source `web/` dir (build hook) and the compiled
/// `build/web/` dir (post-build tool), so the deployed bootstrap query always
/// matches the service-worker cache version.
void versionUpdate({String webDir = 'web', String? version}) {
  final resolved = version ??
      Pubspec.parse(File('pubspec.yaml').readAsStringSync()).version.toString();
  print('Web build version: $resolved');

  _updateManifestVersion('$webDir/manifest.json', resolved);
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
  final updated =
      html.replaceFirst(pattern, 'flutter_bootstrap.js?v=$version');
  if (updated != html) {
    file.writeAsStringSync(updated, flush: true);
    print('Updated $path');
  }
}
