// tentura-olc landing gate acceptance (trial merge tentura-21x)
// tentura-0cl.1 — olc AGENTS.md fixture sync after alloy memory-embed maintenance

import 'dart:io';

import 'package:test/test.dart';

const _agentsOlcLandingFixture =
    '../../test/fixtures/agents_alloy_memory_olc_landing_tail.txt';

const _beginMarker = '<!-- alloy:memory:begin -->';
const _endMarker = '<!-- alloy:memory:end -->';

File _repoFile(String relativePath) {
  for (final prefix in const ['../../', '']) {
    final candidate = File('$prefix$relativePath');
    if (candidate.existsSync()) {
      return candidate.absolute;
    }
  }
  throw StateError('Repo file not found: $relativePath');
}

String _managedMemoryBlock(String text) {
  final start = text.indexOf(_beginMarker);
  final end = text.indexOf(_endMarker);
  expect(start, greaterThanOrEqualTo(0), reason: 'missing $_beginMarker');
  expect(end, greaterThan(start), reason: 'missing $_endMarker');
  return text.substring(start, end + _endMarker.length);
}

void main() {
  group('tentura-0cl olc AGENTS.md fixture (memory-embed maintenance)', () {
    test(
      'olc landing fixture managed memory matches AGENTS.md managed memory',
      () {
        final fixturePath = _repoFile(_agentsOlcLandingFixture);
        expect(
          fixturePath.existsSync(),
          isTrue,
          reason: 'missing $_agentsOlcLandingFixture',
        );
        final agentsManaged = _managedMemoryBlock(
          _repoFile('AGENTS.md').readAsStringSync(),
        );
        final fixtureManaged = _managedMemoryBlock(
          fixturePath.readAsStringSync(),
        );
        expect(
          fixtureManaged,
          equals(agentsManaged),
          reason:
              'sync managed memory in '
              'test/fixtures/agents_alloy_memory_olc_landing_tail.txt '
              'with AGENTS.md after alloy memory-embed maintenance '
              '(full tail parity remains tentura_olc_landing_check_test)',
        );
      },
    );
  });
}
