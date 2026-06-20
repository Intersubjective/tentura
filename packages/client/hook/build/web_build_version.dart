import 'dart:io';

import 'package:pubspec_parse/pubspec_parse.dart';

/// Single source of truth for the web cache-busting build version.
///
/// Combines the pubspec semantic version with a per-deploy build id so every
/// deploy produces a unique service-worker cache name and bootstrap query,
/// guaranteeing returning clients pick up new assets on a normal refresh
/// instead of being served stale `main.dart.wasm` from the cache-first SW.
///
/// The build id comes from [buildId] or the `WEB_BUILD_ID` env var (CI passes
/// the commit SHA). When unset (local builds) the bare pubspec version is used.
String resolveWebBuildVersion({String? buildId, String pubspecPath = 'pubspec.yaml'}) {
  final pubspecVersion =
      Pubspec.parse(File(pubspecPath).readAsStringSync()).version.toString();
  final rawId = buildId ?? Platform.environment['WEB_BUILD_ID'] ?? '';
  final safeId = rawId.replaceAll(RegExp('[^A-Za-z0-9]'), '');
  if (safeId.isEmpty) return pubspecVersion;
  final shortId = safeId.length > 12 ? safeId.substring(0, 12) : safeId;
  return '$pubspecVersion-$shortId';
}
