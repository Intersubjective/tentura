import 'dart:io';

/// Removes dead-weight files from [buildWebDir] after `flutter build web --wasm`.
///
/// Keeps dual-path fallback assets (dart2js + CanvasKit + skwasm). Run before
/// [generateWasmPreloadArtifacts].
TrimWebDeployResult trimWebDeployArtifact({
  String buildWebDir = 'build/web',
  String browserCompatibilitySource = '../landing/browser_compatibility.js',
}) {
  final webDir = Directory(buildWebDir);
  if (!webDir.existsSync()) {
    stdout.writeln('trim_web_deploy: skip — $buildWebDir missing');
    return const TrimWebDeployResult(deletedPaths: [], bytesRemoved: 0);
  }

  final deleted = <String>[];
  var bytesRemoved = 0;

  void deletePath(String rel) {
    final entity = File('${webDir.path}/$rel');
    if (!entity.existsSync()) {
      final dir = Directory('${webDir.path}/$rel');
      if (!dir.existsSync()) return;
      bytesRemoved += _deleteDirectory(dir, deleted);
      return;
    }
    bytesRemoved += entity.lengthSync();
    entity.deleteSync();
    deleted.add(rel);
  }

  deletePath('canvaskit/experimental_webparagraph');
  deletePath('flutter.js');
  deletePath('flutter.js.map');
  deletePath('flutter_service_worker.js');
  deletePath('custom_lint.log');

  final canvaskitDir = Directory('${webDir.path}/canvaskit');
  if (canvaskitDir.existsSync()) {
    for (final entity in canvaskitDir.listSync(recursive: true)) {
      if (entity is! File) continue;
      if (!entity.path.endsWith('.js.symbols')) continue;
      bytesRemoved += entity.lengthSync();
      final rel = entity.path.substring(webDir.path.length + 1);
      entity.deleteSync();
      deleted.add(rel);
    }
  }

  _copyBrowserCompatibility(
    webDir: webDir,
    sourceRelative: browserCompatibilitySource,
    deleted: deleted,
  );

  stdout.writeln(
    'trim_web_deploy: removed ${deleted.length} paths '
    '(${(bytesRemoved / 1024 / 1024).toStringAsFixed(2)} MB)',
  );
  return TrimWebDeployResult(deletedPaths: deleted, bytesRemoved: bytesRemoved);
}

int _deleteDirectory(Directory dir, List<String> deleted) {
  var bytes = 0;
  if (dir.existsSync()) {
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is File) bytes += entity.lengthSync();
    }
    final rel = dir.path.split(Platform.pathSeparator).last;
    deleted.add('canvaskit/$rel/');
    dir.deleteSync(recursive: true);
  }
  return bytes;
}

void _copyBrowserCompatibility({
  required Directory webDir,
  required String sourceRelative,
  required List<String> deleted,
}) {
  final source = File(sourceRelative);
  if (!source.existsSync()) {
    stdout.writeln(
      'trim_web_deploy: skip browser_compatibility copy — '
      '${source.path} missing',
    );
    return;
  }
  final dest = File('${webDir.path}/browser_compatibility.js');
  source.copySync(dest.path);
  deleted.add('browser_compatibility.js (copied)');
}

class TrimWebDeployResult {
  const TrimWebDeployResult({
    required this.deletedPaths,
    required this.bytesRemoved,
  });

  final List<String> deletedPaths;
  final int bytesRemoved;
}
