import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../hook/build/wasm_preload_artifacts.dart';
import '../../hook/build/web_build_version.dart';

void main() {
  test(
    'ships a versioned bootstrap and public copy in English and Russian',
    () async {
      final output = await Directory.systemTemp.createTemp('web_release_');
      addTearDown(() => output.delete(recursive: true));
      final sourceIndex = File('web/index.html');
      final sourceManifest = File('web/manifest.json');
      final builtIndex = await sourceIndex.copy('${output.path}/index.html');
      await sourceManifest.copy('${output.path}/manifest.json');
      await File('${output.path}/main.dart.wasm').create();

      generateWasmPreloadArtifacts(
        buildWebDir: output.path,
        version: resolveWebBuildVersion(buildId: ''),
      );

      final bootstrapQuery = RegExp(r'''flutter_bootstrap\.js\?v=([^"']+)''');
      final sourceVersion = bootstrapQuery
          .firstMatch(await sourceIndex.readAsString())
          ?.group(1);
      final deployedVersion = bootstrapQuery
          .firstMatch(await builtIndex.readAsString())
          ?.group(1);
      final manifest =
          jsonDecode(await sourceManifest.readAsString())
              as Map<String, dynamic>;

      expect(sourceVersion, '0.0.0-dev');
      expect(manifest, isNot(contains('version')));

      final internalTerm = RegExp('phantom|фантом', caseSensitive: false);
      for (final locale in ['en', 'ru']) {
        final path = 'l10n/app_$locale.arb';
        final catalog =
            jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
        final messages = catalog.entries
            .where(
              (entry) => !entry.key.startsWith('@') && entry.value is String,
            )
            .toList();
        expect(messages, isNotEmpty, reason: '$path must contain translations');
        final offendingKeys = [
          for (final message in messages)
            if (internalTerm.hasMatch(message.value as String)) message.key,
        ];
        expect(
          offendingKeys,
          isEmpty,
          reason: '$path exposes internal terminology',
        );
      }

      expect(deployedVersion, '7.64.0');
    },
  );
}
