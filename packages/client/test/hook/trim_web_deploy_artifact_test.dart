import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../../hook/build/trim_web_deploy_artifact.dart' as hook;

void main() {
  test('trimWebDeployArtifact removes symbols and keeps JS fallback', () {
    final dir = Directory.systemTemp.createTempSync('tentura_trim_test');
    try {
      File('${dir.path}/main.dart.js').writeAsStringSync('js');
      File('${dir.path}/main.dart.wasm').writeAsStringSync('wasm');
      File('${dir.path}/flutter.js').writeAsStringSync('unused');
      File('${dir.path}/custom_lint.log').writeAsStringSync('log');
      Directory('${dir.path}/canvaskit/experimental_webparagraph')
          .createSync(recursive: true);
      File('${dir.path}/canvaskit/experimental_webparagraph/canvaskit.wasm')
          .writeAsStringSync('x');
      File('${dir.path}/canvaskit/canvaskit.wasm').writeAsStringSync('ck');
      File('${dir.path}/canvaskit/canvaskit.js.symbols')
          .writeAsStringSync('sym');

      final compatSource = File('../landing/browser_compatibility.js');
      if (!compatSource.existsSync()) {
        return;
      }

      hook.trimWebDeployArtifact(
        buildWebDir: dir.path,
        browserCompatibilitySource: '../landing/browser_compatibility.js',
      );

      expect(File('${dir.path}/main.dart.js').existsSync(), isTrue);
      expect(File('${dir.path}/canvaskit/canvaskit.wasm').existsSync(), isTrue);
      expect(
        Directory('${dir.path}/canvaskit/experimental_webparagraph').existsSync(),
        isFalse,
      );
      expect(File('${dir.path}/canvaskit/canvaskit.js.symbols').existsSync(), isFalse);
      expect(File('${dir.path}/flutter.js').existsSync(), isFalse);
      expect(File('${dir.path}/browser_compatibility.js').existsSync(), isTrue);
    } finally {
      dir.deleteSync(recursive: true);
    }
  });
}
