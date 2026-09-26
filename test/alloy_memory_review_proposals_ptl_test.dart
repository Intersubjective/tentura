import 'dart:io';

import 'package:test/test.dart';

// tentura-jc0 landing gate acceptance (trial merge tentura-ptl)

/// tentura-ptl: Review memory proposals for workspace layout and wrapped test runs.
const _beginMarker = '<!-- alloy:memory:begin -->';
const _endMarker = '<!-- alloy:memory:end -->';
const _ptlReviewBegin = '<!-- alloy:memory-review:ptl:begin -->';
const _ptlReviewEnd = '<!-- alloy:memory-review:ptl:end -->';

const _layoutProposalKey =
    'tentura-layout-pub-workspace-packages-client-flutter-run';
const _wrappedTestsProposalKey =
    'tentura-tests-always-wrap-flutter-test-dart-test';

const _proposalKeys = [_layoutProposalKey, _wrappedTestsProposalKey];

const _pendingProposalHeadings = [
  '### $_layoutProposalKey',
  '### $_wrappedTestsProposalKey',
];

String _lessonKeyForProposal(String proposalKey) => 'alloy:lesson:$proposalKey';

String _managedMemoryBlock(String agentsText) {
  final start = agentsText.indexOf(_beginMarker);
  final end = agentsText.indexOf(_endMarker);
  expect(start, greaterThanOrEqualTo(0), reason: 'missing $_beginMarker');
  expect(end, greaterThan(start), reason: 'missing $_endMarker');
  return agentsText.substring(start, end + _endMarker.length);
}

String _ptlReviewBlock(String agentsText) {
  final start = agentsText.indexOf(_ptlReviewBegin);
  final end = agentsText.indexOf(_ptlReviewEnd);
  expect(start, greaterThanOrEqualTo(0), reason: 'missing $_ptlReviewBegin');
  expect(end, greaterThan(start), reason: 'missing $_ptlReviewEnd');
  return agentsText.substring(start, end + _ptlReviewEnd.length);
}

Map<String, String> _parsePtlOutcomes(String agentsText) {
  final block = _ptlReviewBlock(agentsText);
  final outcomes = <String, String>{};
  for (final key in _proposalKeys) {
    final match = RegExp(
      r'^- \*\*' + RegExp.escape(key) + r'\*\*: (applied|dismissed)\s*$',
      multiLine: true,
    ).firstMatch(block);
    if (match != null) {
      outcomes[key] = match.group(1)!;
    }
  }
  return outcomes;
}

String? _sectionBody(String block, String lessonKey) {
  final header = '### $lessonKey';
  final start = block.indexOf(header);
  if (start < 0) {
    return null;
  }
  final bodyStart = start + header.length;
  final nextHeader = block.indexOf('\n### ', bodyStart);
  final end = nextHeader < 0 ? block.length : nextHeader;
  return block.substring(bodyStart, end);
}

void main() {
  final agents = File('AGENTS.md');

  test('AGENTS.md defines the alloy managed memory block markers', () {
    expect(agents.existsSync(), isTrue, reason: 'expected ${agents.path}');
    final text = agents.readAsStringSync();
    expect(text, contains(_beginMarker));
    expect(text, contains(_endMarker));
  });

  test('ptl records applied or dismissed outcome for each proposal', () {
    final text = agents.readAsStringSync();
    final outcomes = _parsePtlOutcomes(text);
    for (final key in _proposalKeys) {
      expect(
        outcomes[key],
        anyOf('applied', 'dismissed'),
        reason: 'record outcome for $key in ptl review block',
      );
    }
  });

  test('managed memory no longer lists pending proposal headings', () {
    final block = _managedMemoryBlock(agents.readAsStringSync());
    for (final heading in _pendingProposalHeadings) {
      expect(
        block,
        isNot(contains(heading)),
        reason: 'resolve proposal; remove unreviewed $heading',
      );
    }
  });

  test('applied proposals become alloy lessons; dismissed ones do not', () {
    final text = agents.readAsStringSync();
    final outcomes = _parsePtlOutcomes(text);
    final block = _managedMemoryBlock(text);
    for (final key in _proposalKeys) {
      final lessonKey = _lessonKeyForProposal(key);
      final outcome = outcomes[key];
      expect(outcome, isNotNull, reason: 'missing outcome line for $key');
      if (outcome == 'applied') {
        expect(
          block,
          contains(lessonKey),
          reason: 'applied $key must appear as $lessonKey',
        );
      } else if (outcome == 'dismissed') {
        expect(
          block,
          isNot(contains('### $lessonKey')),
          reason: 'dismissed $key must not remain as a managed lesson',
        );
      }
    }
  });

  test('applied layout lesson documents pub workspace client test invocation', () {
    final text = agents.readAsStringSync();
    final outcome = _parsePtlOutcomes(text)[_layoutProposalKey];
    if (outcome == 'dismissed') {
      return;
    }
    expect(outcome, equals('applied'));
    final lessonKey = _lessonKeyForProposal(_layoutProposalKey);
    final body = _sectionBody(_managedMemoryBlock(text), lessonKey);
    expect(body, isNotNull, reason: 'missing ### $lessonKey section');
    expect(body!, contains('pub workspace'));
    expect(body, contains('packages/client'));
    expect(body, contains('packages/server'));
    expect(body, contains('flutter test'));
    expect(body, contains('--dart-define=ENV=test'));
    expect(body, contains('--dart-define-from-file=env/test.env'));
    expect(body, contains('packages/tentura_lints'));
    expect(body, contains('design-system'));
    expect(body, contains('build_runner'));
    expect(body, contains('*.g.dart'));
  });

  test('applied wrapped-tests lesson documents cleanup wrapper and serial runs', () {
    final text = agents.readAsStringSync();
    final outcome = _parsePtlOutcomes(text)[_wrappedTestsProposalKey];
    if (outcome == 'dismissed') {
      return;
    }
    expect(outcome, equals('applied'));
    final lessonKey = _lessonKeyForProposal(_wrappedTestsProposalKey);
    final body = _sectionBody(_managedMemoryBlock(text), lessonKey);
    expect(body, isNotNull, reason: 'missing ### $lessonKey section');
    expect(body!, contains('flutter test'));
    expect(body, contains('dart test'));
    expect(body, contains('scripts/check-custom-lints.sh'));
    expect(body, contains('./scripts/run_with_test_cleanup.sh'));
    expect(body, contains('Never wrap flutter run'));
    expect(body, contains('never two at once'));
  });
}
