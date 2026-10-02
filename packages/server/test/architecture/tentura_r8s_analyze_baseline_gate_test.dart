// tentura-r8s: plain `dart analyze` / `flutter analyze` need a ratcheting
// baseline (like scripts/custom-lint-baseline.txt) instead of failing on debt.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _packages = <String, String>{
  'packages/client': 'flutter',
  'packages/server': 'dart',
};

const _scopedKey = 'packages/client:lib/features/beacon_view';
const _scopedPath = 'lib/features/beacon_view';

final _repoRoot = Directory('../..').absolute;
final _script = File('${_repoRoot.path}/scripts/check-analyze-baseline.sh');
final _baseline = File('${_repoRoot.path}/scripts/analyze-baseline.txt');

List<List<String>> _rows(String text) => text
    .split('\n')
    .where((l) => l.trim().isNotEmpty && !l.trimLeft().startsWith('#'))
    .map((l) => l.trim().split(RegExp(r'\s+')))
    .toList();

/// Temp "repo" holding a copy of the gate script, a given baseline file and
/// fake `dart` / `flutter` binaries that print analyzer-shaped output.
class _Fixture {
  _Fixture(String baselineText, {bool generated = true}) {
    root = Directory.systemTemp.createTempSync('r8s_gate_');
    Directory(p.join(root.path, 'scripts')).createSync();
    _script.copySync(p.join(root.path, 'scripts', 'check-analyze-baseline.sh'));
    File(p.join(root.path, 'scripts', 'analyze-baseline.txt'))
        .writeAsStringSync(baselineText);
    for (final pkg in _packages.keys) {
      Directory(p.join(root.path, pkg)).createSync(recursive: true);
    }
    if (generated) {
      for (final f in [
        'packages/client/lib/ui/l10n/l10n.dart',
        'packages/client/lib/app/router/root_router.gr.dart',
        'packages/server/lib/domain/entity/jwt_entity.freezed.dart',
        'packages/server/lib/data/database/tentura_db.g.dart',
      ]) {
        File(p.join(root.path, f))
          ..createSync(recursive: true)
          ..writeAsStringSync('// generated\n');
      }
    }
    bin = Directory(p.join(root.path, 'bin'))..createSync();
    for (final tool in {'dart', 'flutter'}) {
      final f = File(p.join(bin.path, tool))
        ..writeAsStringSync(_fakeTool(tool));
      Process.runSync('chmod', ['+x', f.path]);
    }
  }

  late final Directory root;
  late final Directory bin;

  File get invocations => File(p.join(root.path, 'invocations.log'));

  String _fakeTool(String tool) => '''
#!/usr/bin/env bash
echo "$tool \$PWD \$*" >> "${root.path}/invocations.log"
if [[ "\${1:-}" != "analyze" ]]; then exit 0; fi
i=0
echo "Analyzing project..."
for ((n=0; n<\${FAKE_ERRORS:-0}; n++)); do
  echo "  error • Fake error \$n • lib/e\$n.dart:1:1 • fake_error"; i=\$((i+1))
done
for ((n=0; n<\${FAKE_WARNINGS:-0}; n++)); do
  echo "  warning • Fake warning \$n • lib/w\$n.dart:1:1 • fake_warning"; i=\$((i+1))
done
for ((n=0; n<\${FAKE_INFOS:-0}; n++)); do
  echo "  info • Fake info \$n • lib/i\$n.dart:1:1 • fake_info"; i=\$((i+1))
done
if [[ \$i -eq 0 ]]; then echo "No issues found!"; exit 0; fi
echo "\$i issues found."
exit 1
''';

  ProcessResult run(
    String pkg, {
    int errors = 0,
    int warnings = 0,
    int infos = 0,
    String? scope,
  }) =>
      Process.runSync(
        'bash',
        [
          p.join(root.path, 'scripts', 'check-analyze-baseline.sh'),
          pkg,
          if (scope != null) scope,
        ],
        workingDirectory: root.path,
        environment: {
          'PATH': '${bin.path}:${Platform.environment['PATH']}',
          'FAKE_ERRORS': '$errors',
          'FAKE_WARNINGS': '$warnings',
          'FAKE_INFOS': '$infos',
        },
      );

  void dispose() => root.deleteSync(recursive: true);
}

const _goodBaseline =
    'packages/client 5\npackages/server 5\n$_scopedKey 2\n';

void main() {
  group('tentura-r8s analyze baseline gate', () {
    test('script exists and is executable', () {
      expect(_script.existsSync(), isTrue, reason: 'add ${_script.path}');
      expect(_script.statSync().modeString(), contains('x'));
    });

    test('baseline has exactly one nonnegative integer row per package', () {
      expect(_baseline.existsSync(), isTrue, reason: 'add ${_baseline.path}');
      final rows = _rows(_baseline.readAsStringSync());
      expect(
        rows.map((r) => r.first).toList()..sort(),
        [..._packages.keys, _scopedKey]..sort(),
        reason: 'one row per package plus the beacon_view scope, '
            'no duplicates or extras',
      );
      for (final r in rows) {
        expect(r, hasLength(2), reason: 'row "${r.join(' ')}"');
        expect(RegExp(r'^\d+$').hasMatch(r[1]), isTrue,
            reason: '${r[0]} count must be a nonnegative integer');
      }
    });

    for (final entry in _packages.entries) {
      final pkg = entry.key;
      final tool = entry.value;

      group(pkg, () {
        late _Fixture fx;
        setUp(() => fx = _Fixture(_goodBaseline));
        tearDown(() => fx.dispose());

        test('count at baseline passes despite non-zero analyzer exit', () {
          final r = fx.run(pkg, infos: 3, warnings: 2);
          expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
        });

        test('count below baseline passes', () {
          final r = fx.run(pkg, infos: 1);
          expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
          final clean = fx.run(pkg);
          expect(clean.exitCode, 0, reason: '${clean.stdout}\n${clean.stderr}');
        });

        test('count above baseline (infos) fails', () {
          final r = fx.run(pkg, infos: 6);
          expect(r.exitCode, 1, reason: '${r.stdout}\n${r.stderr}');
        });

        test('warning increase above baseline fails', () {
          final r = fx.run(pkg, infos: 4, warnings: 2);
          expect(r.exitCode, 1, reason: '${r.stdout}\n${r.stderr}');
        });

        test('any analyzer error fails even when total is below baseline', () {
          final r = fx.run(pkg, errors: 1);
          expect(r.exitCode, 1, reason: '${r.stdout}\n${r.stderr}');
        });

        test('uses $tool analyze at the package root', () {
          fx.run(pkg, infos: 1);
          final log = fx.invocations.readAsLinesSync();
          expect(log, isNotEmpty, reason: 'analyzer was never invoked');
          final line = log.firstWhere((l) => l.contains(' analyze'),
              orElse: () => '');
          expect(line, startsWith('$tool '));
          expect(line, contains(p.join(fx.root.path, pkg)));
          final args = line.split(' ').skip(2).toList();
          expect(args.first, 'analyze');
          expect(
            args.skip(1).where((a) => !a.startsWith('-')).toSet().difference({'.'}),
            isEmpty,
            reason: 'package-level run must target the package root only '
                '(flags allowed): plugin diagnostics only surface there',
          );
        });
      });
    }

    group('scoped path (flutter analyze lib/features/beacon_view)', () {
      late _Fixture fx;
      setUp(() => fx = _Fixture(_goodBaseline));
      tearDown(() => fx.dispose());

      test('uses its own baseline, not the package total', () {
        // package baseline is 5, scoped baseline is 2.
        expect(fx.run('packages/client', infos: 3).exitCode, 0);
        final over = fx.run('packages/client', infos: 3, scope: _scopedPath);
        expect(over.exitCode, 1, reason: '${over.stdout}\n${over.stderr}');
        final ok = fx.run('packages/client', infos: 2, scope: _scopedPath);
        expect(ok.exitCode, 0, reason: '${ok.stdout}\n${ok.stderr}');
        final err = fx.run('packages/client', errors: 1, scope: _scopedPath);
        expect(err.exitCode, 1, reason: '${err.stdout}\n${err.stderr}');
      });

      test('analyzes only the scoped path with flutter', () {
        fx.run('packages/client', infos: 1, scope: _scopedPath);
        final line = fx.invocations
            .readAsLinesSync()
            .firstWhere((l) => l.contains(' analyze'), orElse: () => '');
        expect(line, startsWith('flutter '));
        expect(line, contains(_scopedPath));
      });

      test('scope without a baseline row exits 2', () {
        final r = fx.run('packages/client', scope: 'lib/features/other');
        expect(r.exitCode, 2, reason: '${r.stdout}\n${r.stderr}');
        expect(r.stderr.toString(), contains('baseline'));
      });
    });

    group('codegen bootstrap (mirrors check-custom-lints.sh)', () {
      test('client: missing generated outputs run gen-l10n + build_runner '
          'before analyze', () {
        final fx = _Fixture(_goodBaseline, generated: false);
        addTearDown(fx.dispose);
        fx.run('packages/client', infos: 1);
        final log = fx.invocations.readAsLinesSync();
        final l10n = log.indexWhere((l) => l.contains('gen-l10n'));
        final br = log.indexWhere((l) => l.contains('build_runner'));
        final an = log.indexWhere((l) => l.contains(' analyze'));
        expect(l10n, greaterThanOrEqualTo(0), reason: log.join('\n'));
        expect(br, greaterThanOrEqualTo(0), reason: log.join('\n'));
        expect(an, greaterThan(l10n));
        expect(an, greaterThan(br));
      });

      test('server: missing generated outputs run build_runner first', () {
        final fx = _Fixture(_goodBaseline, generated: false);
        addTearDown(fx.dispose);
        fx.run('packages/server', infos: 1);
        final log = fx.invocations.readAsLinesSync();
        final br = log.indexWhere((l) => l.contains('build_runner'));
        final an = log.indexWhere((l) => l.contains(' analyze'));
        expect(br, greaterThanOrEqualTo(0), reason: log.join('\n'));
        expect(an, greaterThan(br));
      });

      test('no bootstrap when outputs already exist', () {
        final fx = _Fixture(_goodBaseline);
        addTearDown(fx.dispose);
        fx.run('packages/client', infos: 1);
        fx.run('packages/server', infos: 1);
        final log = fx.invocations.readAsStringSync();
        expect(log, isNot(contains('build_runner')));
        expect(log, isNot(contains('gen-l10n')));
      });
    });

    group('baseline file validation', () {
      for (final bad in {
        'duplicate row': 'packages/client 5\npackages/client 6\npackages/server 5\n',
        'negative count': 'packages/client -1\npackages/server 5\n',
        'non-integer count': 'packages/client many\npackages/server 5\n',
        'duplicate scoped row':
            '$_goodBaseline$_scopedKey 3\n',
        'negative scoped count':
            'packages/client 5\npackages/server 5\n$_scopedKey -2\n',
        'missing package row': 'packages/server 5\n',
      }.entries) {
        test('rejects ${bad.key} with exit 2', () {
          final fx = _Fixture(bad.value);
          addTearDown(fx.dispose);
          final r = fx.run('packages/client', infos: 1);
          expect(r.exitCode, 2, reason: '${r.stdout}\n${r.stderr}');
          expect(r.stderr.toString(), contains('baseline'));
        });
      }

      test('unknown package exits 2', () {
        final fx = _Fixture(_goodBaseline);
        addTearDown(fx.dispose);
        final r = fx.run('packages/does_not_exist');
        expect(r.exitCode, 2, reason: '${r.stdout}\n${r.stderr}');
        expect(r.stderr.toString(), contains('baseline'));
      });
    });

    group('CI wiring', () {
      for (final wf in ['pipeline.yml', 'pipeline-prod.yml']) {
        for (final pkg in _packages.keys) {
          test('$wf runs check-analyze-baseline.sh $pkg', () {
            final lines = File('${_repoRoot.path}/.github/workflows/$wf')
                .readAsLinesSync();
            final active = lines.where((l) {
              final t = l.trimLeft();
              if (t.startsWith('#')) return false;
              final cmd = t.indexOf('check-analyze-baseline.sh $pkg');
              if (cmd < 0) return false;
              final hash = t.indexOf(' #');
              return hash < 0 || hash > cmd;
            });
            expect(active, isNotEmpty,
                reason: 'no uncommented step runs the gate for $pkg');
          });
        }
      }
    });
  });
}
