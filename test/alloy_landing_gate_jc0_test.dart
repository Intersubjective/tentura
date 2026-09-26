import 'dart:io';

import 'package:test/test.dart';

// tentura-jc0 landing gate acceptance (trial merge tentura-ptl)

/// Same paths as bead tentura-jc0 acceptance (`dart test test/` on alloy/tentura-ptl).
const kJc0AcceptanceTestPaths = [
  'test/alloy_memory_review_proposals_ptl_test.dart',
  'test/alloy_landing_gate_jc0_test.dart',
];

const _jc0LandingGateMarker = 'tentura-jc0 landing gate acceptance';
const _ptlTrialMergeMarker = 'trial merge tentura-ptl';

const _beginMarker = '<!-- alloy:memory:begin -->';
const _endMarker = '<!-- alloy:memory:end -->';
const _ptlReviewBegin = '<!-- alloy:memory-review:ptl:begin -->';
const _ptlReviewEnd = '<!-- alloy:memory-review:ptl:end -->';

const _layoutProposalKey =
    'tentura-layout-pub-workspace-packages-client-flutter-run';
const _wrappedTestsProposalKey =
    'tentura-tests-always-wrap-flutter-test-dart-test';

const _pendingProposalHeadings = [
  '### $_layoutProposalKey',
  '### $_wrappedTestsProposalKey',
];

const _jc0LandingFixture =
    'test/fixtures/agents_alloy_memory_jc0_landing_tail.txt';

File _repoFile(String relativePath) => File(relativePath);

String _managedMemoryBlock(String agentsText) {
  final start = agentsText.indexOf(_beginMarker);
  final end = agentsText.indexOf(_endMarker);
  expect(start, greaterThanOrEqualTo(0), reason: 'missing $_beginMarker');
  expect(end, greaterThan(start), reason: 'missing $_endMarker');
  return agentsText.substring(start, end + _endMarker.length);
}

void main() {
  group('alloy landing gate (tentura-jc0)', () {
    test('jc0 acceptance test files declare jc0 landing gate markers', () {
      for (final path in kJc0AcceptanceTestPaths) {
        final file = _repoFile(path);
        expect(file.existsSync(), isTrue, reason: 'missing acceptance path $path');
        final source = file.readAsStringSync();
        expect(
          source,
          contains(_jc0LandingGateMarker),
          reason: '$path must tag the jc0 landing gate for Alloy trial-merge tracking',
        );
        expect(
          source,
          contains(_ptlTrialMergeMarker),
          reason: '$path must reference trial merge tentura-ptl',
        );
      }
    });

    test('AGENTS.md alloy memory tail matches tentura-jc0 landing fixture', () {
      final agentsPath = _repoFile('AGENTS.md');
      final fixturePath = _repoFile(_jc0LandingFixture);
      expect(fixturePath.existsSync(), isTrue, reason: 'missing $_jc0LandingFixture');
      final agents = agentsPath.readAsStringSync();
      final start = agents.indexOf(_beginMarker);
      expect(start, greaterThanOrEqualTo(0), reason: 'missing $_beginMarker');
      final actualTail = agents.substring(start).trimRight();
      final expectedTail = fixturePath.readAsStringSync().trimRight();
      expect(
        actualTail,
        equals(expectedTail),
        reason:
            'resolve tentura-ptl memory proposals and record jc0 landing beside ptl review',
      );
    });

    test('managed memory no longer lists unreviewed ptl proposal headings', () {
      final block = _managedMemoryBlock(_repoFile('AGENTS.md').readAsStringSync());
      for (final heading in _pendingProposalHeadings) {
        expect(
          block,
          isNot(contains(heading)),
          reason: 'rename resolved proposals to ### alloy:lesson:<key>',
        );
      }
    });

    test('ptl memory review block is recorded outside managed memory', () {
      final text = _repoFile('AGENTS.md').readAsStringSync();
      final managed = _managedMemoryBlock(text);
      expect(text, contains(_ptlReviewBegin));
      expect(text, contains(_ptlReviewEnd));
      expect(managed, isNot(contains(_ptlReviewBegin)));
      expect(managed, isNot(contains(_ptlReviewEnd)));
      final managedEnd = text.indexOf(_endMarker) + _endMarker.length;
      final ptlBegin = text.indexOf(_ptlReviewBegin);
      expect(ptlBegin, greaterThan(managedEnd));
    });

    test('ptl review records applied outcomes for both proposals', () {
      final text = _repoFile('AGENTS.md').readAsStringSync();
      final ptlBlock = text.substring(
        text.indexOf(_ptlReviewBegin),
        text.indexOf(_ptlReviewEnd) + _ptlReviewEnd.length,
      );
      expect(ptlBlock, contains('- **$_layoutProposalKey**: applied'));
      expect(ptlBlock, contains('- **$_wrappedTestsProposalKey**: applied'));
    });
  });
}
