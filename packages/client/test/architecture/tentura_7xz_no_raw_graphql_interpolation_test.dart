// tentura-7xz: no_raw_graphql_in_dart must flag interpolated GraphQL documents.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/client_dart_analyze_harness.dart';
import '../support/tentura_7xz_e2e_graphql_harness.dart';

const _e2eHelpersRelative = 'integration_test/support/e2e_test_helpers.dart';

const _interpolationProbeRelative =
    'integration_test/support/tentura_7xz_interpolation_lint_probe.dart';

const _noRawGraphqlCode = 'no_raw_graphql_in_dart';

int countNoRawGraphqlDiagnosticsOnRelativePath(String relativePath) {
  final client = clientPackageRoot();
  final absolute = File('${client.path}/$relativePath').absolute.path;
  return runDartAnalyzeJsonOnRelativePaths([relativePath])
      .where((d) => d['code'] == _noRawGraphqlCode)
      .where((d) {
        final location = d['location'] as Map?;
        final file = location?['file'] as String?;
        return clientAnalyzePathsEqual(file ?? '', absolute);
      })
      .length;
}

void main() {
  group('tentura-7xz no_raw_graphql interpolated documents', () {
    test('violations detector covers quoted and formatted call shapes', () {
      const samples = <String>[
        "_postGraphQl('mutation { foo(id: \"\$id\") }');",
        '_postGraphQl("mutation { foo(id: \$id) }");',
        "_postGraphQl(\n  '  mutation { foo(id: \"\$id\") }',\n);",
        "_postGraphQl('mutation { foo(id: \"'\n    '\$id'\n    '\") }');",
      ];
      for (final sample in samples) {
        expect(
          countPostGraphQlRawInterpolatedGraphqlCallSites(sample),
          1,
          reason: 'expected one violation in: $sample',
        );
      }
      expect(
        countPostGraphQlRawInterpolatedGraphqlCallSites(
          'Future<Map<String, dynamic>> _postGraphQl(String query) async {}',
        ),
        0,
        reason: 'must not treat the transport helper signature as a call site',
      );
    });

    test(
      'e2e_test_helpers has no raw interpolated GraphQL on _postGraphQl calls',
      () {
        final client = clientPackageRoot();
        final source = File('${client.path}/$_e2eHelpersRelative')
            .readAsStringSync();
        final sites = countPostGraphQlRawInterpolatedGraphqlCallSites(source);
        expect(
          sites,
          0,
          reason:
              'e2e helpers must use generated *Req operations, not raw '
              'interpolated GraphQL passed to _postGraphQl (found $sites)',
        );
      },
    );

    test(
      'dart analyze on e2e_test_helpers matches the no-raw-interpolation contract',
      () {
        final client = clientPackageRoot();
        final source = File('${client.path}/$_e2eHelpersRelative')
            .readAsStringSync();
        final semanticSites =
            countPostGraphQlRawInterpolatedGraphqlCallSites(source);
        final lintHits =
            countNoRawGraphqlDiagnosticsOnRelativePath(_e2eHelpersRelative);

        if (semanticSites > 0) {
          expect(
            lintHits,
            greaterThanOrEqualTo(semanticSites),
            reason:
                'while e2e_test_helpers still embeds raw interpolated GraphQL, '
                'dart analyze must report no_raw_graphql_in_dart for every '
                'call site (semantic=$semanticSites, lint=$lintHits)',
          );
        } else {
          expect(
            lintHits,
            0,
            reason:
                'once e2e_test_helpers is migrated, dart analyze must report '
                'zero no_raw_graphql_in_dart on that file (found $lintHits)',
          );
        }

        expect(
          semanticSites,
          0,
          reason:
              'e2e_test_helpers must not contain raw interpolated GraphQL '
              'documents (found $semanticSites)',
        );
      },
    );

    test(
      'dart analyze flags interpolated GraphQL on the lint probe fixture',
      () {
        final diagnostics = runDartAnalyzeJsonOnRelativePaths(
          const [_interpolationProbeRelative],
        );
        final hits = diagnostics
            .where((d) => d['code'] == _noRawGraphqlCode)
            .toList(growable: false);
        expect(
          hits,
          isNotEmpty,
          reason:
              'no_raw_graphql_in_dart must report on StringInterpolation '
              'GraphQL documents (probe: $_interpolationProbeRelative)',
        );
      },
    );
  });
}
