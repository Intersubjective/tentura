import 'package:test/test.dart';

const forwardingProfilePath = 'docs/perf/viewer-can-forward-m0318.md';
const forwardingProfileOperations = {
  'Inbox feed': 'inbox_fetch.graphql',
  'My Work': 'my_work_fetch.graphql',
};

String forwardingProfileSection(String markdown, String headingText) {
  final headings = RegExp(
    r'^(#{1,6})[ \t]+(.+)$',
    multiLine: true,
  ).allMatches(markdown).toList();
  final index = headings.indexWhere(
    (heading) => heading[2]!.toLowerCase().contains(headingText),
  );
  if (index < 0) fail('no benchmark section for $headingText');
  final heading = headings[index];
  final next = headings
      .skip(index + 1)
      .where((candidate) => candidate[1]!.length <= heading[1]!.length);
  return markdown.substring(
    heading.end,
    next.isEmpty ? markdown.length : next.first.start,
  );
}

bool forwardingProfileVerdict(String section) {
  final verdicts = RegExp(
    r'^[ \t]*(?:[-*+][ \t]+)?verdict[ \t]*:[ \t]*(not slower|slower)[ \t]*\.?[ \t]*$',
    caseSensitive: false,
    multiLine: true,
  ).allMatches(section.replaceAll(RegExp(r'`|\*\*|__'), '')).toList();
  expect(
    verdicts,
    hasLength(1),
    reason: 'record one verdict for each operation',
  );
  return verdicts.single[1]!.toLowerCase() == 'slower';
}
