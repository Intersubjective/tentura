// tentura-7qx: client bead gates must use scoped flutter analyze, not bare
// package-wide `flutter analyze .` (which treats ambient pre-existing
// info/warning debt as fatal).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/client_flutter_analyze_gate_harness.dart';

/// Only skip when this file is invoked from a nested bead acceptance suite,
/// not on the CI client shard (contrast tentura-5zq server gate).
Object get _skipIn7qxNestedSuite {
  if (Platform.environment['TENTURA_7QX_NESTED_SUITE'] == 'true') {
    return 'do not nest contract flutter analyze gates inside nested suites';
  }
  return false;
}

void main() {
  group('tentura-7qx client flutter analyze gate', () {
    test(
      'client-bead-flutter-analyze-gate contract exists and forbids bare package-wide bead gates',
      () {
        final file = clientBeadFlutterAnalyzeContractFile();
        expect(
          file.existsSync(),
          isTrue,
          reason:
              'tentura-7qx fix: add $k7qxClientBeadFlutterAnalyzeContractRelative '
              'so single beads use scoped flutter analyze instead of bare '
              'package-wide `flutter analyze .` (fatal infos on ambient debt)',
        );
        final contract = loadClientBeadFlutterAnalyzeContract();
        expect(contract['schemaVersion'], 1);
        expect(
          contract['forbidBarePackageWideFlutterAnalyzeAsSingleBeadGate'],
          isTrue,
        );
        final whenNeeded = Map<String, dynamic>.from(
          contract['packageWideFlutterAnalyzeWhenNeeded'] as Map,
        );
        final args = (whenNeeded['args'] as List).cast<String>();
        expect(args, contains('--no-fatal-infos'));
        expect(args, contains('--no-fatal-warnings'));

        final targets =
            (contract['beadScopedFlutterAnalyzeTargets'] as List).cast<String>();
        expect(targets, isNotEmpty);
        expect(targets, isNot(contains('.')));
        expect(
          targets,
          isNot(contains('packages/client')),
          reason: 'scoped targets must name concrete paths, not the package root',
        );
        final repo = repoRootFromClientPackage();
        for (final path in targets) {
          expect(
            path.startsWith('packages/client/'),
            isTrue,
            reason: 'scoped target must live under packages/client: $path',
          );
          expect(
            File('${repo.path}/$path').existsSync(),
            isTrue,
            reason: 'scoped target must exist: $path',
          );
        }

        final contractTests =
            (contract['contractTests'] as List?)?.cast<String>() ?? const [];
        expect(
          contractTests,
          contains(
            'packages/client/test/architecture/'
            'tentura_7qx_client_flutter_analyze_gate_test.dart',
          ),
        );
      },
    );

    test(
      'contract bead gate runs flutter analyze on scoped targets and exits 0',
      () {
        final contract = loadClientBeadFlutterAnalyzeContract();
        final outcome = runBeadScopedFlutterAnalyzeFromContract(contract);
        expect(
          outcome.stdout,
          contains('Analyzing'),
          reason:
              'bead gate must invoke flutter analyze subprocess, not a no-op script',
        );
        expect(
          outcome.exitCode,
          0,
          reason:
              'acceptance: scoped analyze of changed paths listed in the '
              'contract must report no issues\n'
              'stdout:\n${outcome.stdout}\n'
              'stderr:\n${outcome.stderr}',
        );
        expect(
          outcome.stdout,
          contains('No issues found!'),
          reason: 'scoped flutter analyze success banner',
        );
      },
      timeout: const Timeout(Duration(minutes: 12)),
      skip: _skipIn7qxNestedSuite,
    );

    test(
      'contract documents that package-wide analyze may use non-fatal info/warning flags when errors are zero',
      () {
        final contract = loadClientBeadFlutterAnalyzeContract();
        final summary = summarizeDartAnalyzeJsonDot();
        if (summary.errorCount != 0) {
          return;
        }
        final bare = summarizeBareFlutterAnalyzeDot();
        final withFlags = runFlutterAnalyzeWithPackageWidePrFlagsFromContract(
          contract,
        );
        if (bare.infoCount > 0 || bare.warningCount > 0) {
          expect(
            bare.exitCode,
            isNot(0),
            reason:
                'bare package-wide flutter analyze treats infos/warnings as '
                'fatal by default (${bare.issuesFoundLine})',
          );
          expect(
            withFlags.exitCode,
            0,
            reason:
                'packageWideFlutterAnalyzeWhenNeeded must not treat infos or '
                'warnings as fatal when the package has zero analyzer errors\n'
                '${withFlags.stdout}\n${withFlags.stderr}',
          );
        }
      },
      timeout: const Timeout(Duration(minutes: 12)),
      skip: _skipIn7qxNestedSuite,
    );
  });
}
