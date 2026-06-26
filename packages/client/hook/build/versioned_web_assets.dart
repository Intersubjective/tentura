import 'dart:convert';
import 'dart:io';

/// Moves cacheable Flutter web build outputs under `/app-assets/<version>/`
/// and rewrites root entry files to load runtime/assets from that immutable
/// prefix.
void applyVersionedWebAssets({
  required String version,
  String buildWebDir = 'build/web',
}) {
  final webDir = Directory(buildWebDir);
  if (!webDir.existsSync()) {
    stdout.writeln('versioned_web_assets: skip — $buildWebDir missing');
    return;
  }

  final assetPrefix = '/app-assets/$version/';
  final appAssetsDir = Directory('${webDir.path}/app-assets');
  if (appAssetsDir.existsSync()) {
    appAssetsDir.deleteSync(recursive: true);
  }
  final versionDir = Directory('${appAssetsDir.path}/$version')
    ..createSync(recursive: true);

  final rootEntries = webDir.listSync(followLinks: false).toList();
  for (final entity in rootEntries) {
    final name = _basename(entity.path);
    if (_isRootControlPath(name)) continue;
    _moveIntoVersionDir(entity, versionDir);
  }

  _rewriteBootstrap(
    File('${webDir.path}/flutter_bootstrap.js'),
    assetPrefix: assetPrefix,
  );
  _rewriteIndexHtml(
    File('${webDir.path}/index.html'),
    assetPrefix: assetPrefix,
  );
  _rewriteManifestIcons(
    File('${webDir.path}/manifest.json'),
    assetPrefix: assetPrefix,
  );

  stdout.writeln('versioned_web_assets: wrote $assetPrefix');
}

bool _isRootControlPath(String name) {
  if (name.startsWith('.')) return true;
  return const {
    'app-assets',
    'firebase-messaging-sw.js',
    'flutter_bootstrap.js',
    'index.html',
    'manifest.json',
    'tentura-app-cache-sw.js',
    'version.json',
    'wasm-preload-manifest.json',
  }.contains(name);
}

void _moveIntoVersionDir(FileSystemEntity entity, Directory versionDir) {
  final name = _basename(entity.path);
  final dest = '${versionDir.path}/$name';
  entity.renameSync(dest);
}

void _rewriteBootstrap(File file, {required String assetPrefix}) {
  if (!file.existsSync()) return;
  final source = file.readAsStringSync();
  final config = jsonEncode({
    'entrypointBaseUrl': assetPrefix,
    'canvasKitBaseUrl': '${assetPrefix}canvaskit/',
    'assetBase': '${assetPrefix}assets/',
  });
  final updated = source.replaceFirst(
    RegExp(r'_flutter\.loader\.load\(\);'),
    '_flutter.loader.load({config:$config});',
  );
  if (updated != source) {
    file.writeAsStringSync(updated, flush: true);
  }
}

void _rewriteIndexHtml(File file, {required String assetPrefix}) {
  if (!file.existsSync()) return;
  var html = file.readAsStringSync();
  html = html
      .replaceAll('href="icons/', 'href="${assetPrefix}icons/')
      .replaceAll('href="favicon.png"', 'href="${assetPrefix}favicon.png"')
      .replaceAll('srcset="splash/', 'srcset="${assetPrefix}splash/')
      .replaceAll(', splash/', ', ${assetPrefix}splash/')
      .replaceAll('src="splash/', 'src="${assetPrefix}splash/');
  file.writeAsStringSync(html, flush: true);
}

void _rewriteManifestIcons(File file, {required String assetPrefix}) {
  if (!file.existsSync()) return;
  final decoded = jsonDecode(file.readAsStringSync());
  if (decoded is! Map<String, dynamic>) return;
  final icons = decoded['icons'];
  if (icons is List) {
    for (final icon in icons) {
      if (icon is Map && icon['src'] is String) {
        final src = icon['src'] as String;
        if (!src.startsWith('/') && !src.startsWith('http')) {
          icon['src'] = '$assetPrefix$src';
        }
      }
    }
  }
  file.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(decoded),
    flush: true,
  );
}

String _basename(String path) {
  final normalized = path.replaceAll(r'\', '/');
  final index = normalized.lastIndexOf('/');
  return index == -1 ? normalized : normalized.substring(index + 1);
}
