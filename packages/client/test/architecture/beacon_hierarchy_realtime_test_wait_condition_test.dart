import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// tentura-44n: `beacon_hierarchy_realtime_test` "matching hierarchy hint
/// silently refreshes children" flakes under CPU load.
///
/// The cubit fetches capabilities first and children several microtask hops
/// later. The test waited on `capabilitiesCalls >= 2` and then asserted
/// `childrenCalls` immediately; when the debounce timer and the 10 ms poll
/// timer are due in the same batch, the poll continuation can run between
/// those hops and observe capabilities refreshed but children not yet.
///
/// Behavioral guard: run the target test against a copy whose recording port
/// fetches children slowly (the interleaving the load flake produces, made
/// deterministic). The test passes only if it really waits for the post-hint
/// children fetch, however that wait is spelled.
void main() {
  const testDir = 'test/features/beacon_threads';
  const testPath = '$testDir/beacon_hierarchy_realtime_test.dart';
  const probePath =
      '$testDir/beacon_hierarchy_realtime_slow_children_probe.dart';
  const testName = 'matching hierarchy hint silently refreshes children';
  const childrenAssertion =
      'expect(port.childrenCalls, greaterThan(initialChildrenCalls))';
  const countAnchor = '    childrenCalls++;\n';
  const slowCountAnchor =
      '    await Future<void>.delayed(const Duration(milliseconds: 80));\n'
      '    childrenCalls++;\n';

  tearDown(() {
    final probe = File(probePath);
    if (probe.existsSync()) probe.deleteSync();
  });

  test('children assertion of the hint test is kept', () {
    expect(
      File(testPath).readAsStringSync(),
      contains(childrenAssertion),
      reason: 'the post-hint children assertion must not be weakened',
    );
  });

  test('hint test waits for the post-hint children fetch (slow children)', () {
    final source = File(testPath).readAsStringSync();
    expect(source, contains(countAnchor), reason: 'probe anchor moved');
    File(probePath).writeAsStringSync(
      source.replaceFirst(countAnchor, slowCountAnchor),
    );

    final result = Process.runSync(
      'flutter',
      ['test', probePath, '--plain-name', testName],
    );
    expect(
      result.exitCode,
      0,
      reason:
          '"$testName" fails when children are fetched slowly after the '
          'capabilities fetch: it must wait for the refreshed children, not '
          'only for capabilitiesCalls.\n${result.stdout}\n${result.stderr}',
    );
  }, timeout: const Timeout(Duration(minutes: 3)));
}
