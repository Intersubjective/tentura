# Per-test-file coverage from `flutter test` (local SDK patch, not committed to Flutter)

Stock Flutter merges every test file's coverage into one lcov. Overlap analysis needs
them separate. Apply to a throw-away Flutter checkout (3.44-ish):

1. `packages/flutter_tools/lib/src/test/watcher.dart` — add above `abstract class TestWatcher`:
   `final Expando<String> taTestPaths = Expando<String>('taTestPaths');`
2. `.../flutter_platform.dart` — just before `await watcher?.handleFinishedTest(testDevice);`:
   `taTestPaths[testDevice] = testPath;`
3. `.../coverage_collector.dart` — `import '../convert.dart';`, and in `collectCoverage`
   just before `_addHitmap(hitmap);`:
   ```dart
   final String? taDir = globals.platform.environment['TA_COV_DIR'];
   final String? taPath = taTestPaths[testDevice];
   if (taDir != null && taPath != null) {
     final Map<String, List<int>> out = <String, List<int>>{};
     hitmap.forEach((String file, coverage.HitMap hm) {
       final List<int> lines = <int>[
         for (final MapEntry<int, int> e in hm.lineHits.entries) if (e.value > 0) e.key,
       ]..sort();
       if (lines.isNotEmpty) out[file] = lines;
     });
     globals.fs.file(globals.fs.path.join(taDir, '${taPath.replaceAll('/', '__')}.json'))
         .writeAsStringSync(json.encode(out));
   }
   ```
4. `rm bin/cache/flutter_tools.snapshot bin/cache/flutter_tools.stamp` so the tool rebuilds.
