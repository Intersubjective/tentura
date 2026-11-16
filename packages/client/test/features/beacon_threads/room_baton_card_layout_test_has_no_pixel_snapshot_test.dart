// Guards the baton card layout test against pixel sizes measured on one
// machine: font metrics differ between developer machines and CI, so every
// expected size must be derived from something measured at runtime
// (`ref.`, `tester.` or a local assigned from them). Tolerances (the second
// closeTo argument) and the `greaterThan(40)` collapsed-name floor are
// structural thresholds and stay allowed.
// Source check only: the layout itself is exercised by
// room_baton_card_in_fact_bubble_test.dart. Run from packages/client.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _layoutTestPath =
    'test/features/beacon_threads/room_baton_card_in_fact_bubble_test.dart';

String _code() {
  final file = File(_layoutTestPath);
  if (!file.existsSync()) {
    fail('Run from packages/client: $_layoutTestPath not found in ${Directory.current.path}');
  }
  return file
      .readAsLinesSync()
      .map(
        (l) => l.trimLeft().startsWith('//')
            ? ''
            : l.replaceFirst(RegExp(r'''\s//[^'"]*$'''), ''),
      )
      .join('\n');
}

/// Arguments of every `name(...)` call (balanced parens), split on top-level
/// commas.
List<List<String>> _calls(String code, String name) {
  final result = <List<String>>[];
  for (final m in RegExp('\\b$name\\(').allMatches(code)) {
    var depth = 1;
    var i = m.end;
    final args = <String>[];
    var start = i;
    while (i < code.length && depth > 0) {
      final c = code[i];
      if ('([{'.contains(c)) depth++;
      if (')]}'.contains(c)) {
        depth--;
        if (depth == 0) break;
      }
      if (c == ',' && depth == 1) {
        args.add(code.substring(start, i).trim());
        start = i + 1;
      }
      i++;
    }
    final last = code.substring(start, i).trim();
    if (last.isNotEmpty) args.add(last);
    result.add(args);
  }
  return result;
}

/// Names of locals assigned (transitively) from `ref.` / `tester.` values.
Set<String> _measuredLocals(String code) {
  final assigns = RegExp(
    r'(\w+)\s*(?:\?\?)?=\s*([^;=][^;]*);',
  );
  final measured = <String>{};
  bool isMeasured(String expr) =>
      RegExp(r'\b(ref|tester)\.').hasMatch(expr) ||
      measured.any((n) => RegExp('\\b$n\\b').hasMatch(expr));
  var changed = true;
  while (changed) {
    changed = false;
    for (final m in assigns.allMatches(code)) {
      final name = m.group(1)!;
      if (!measured.contains(name) && isMeasured(m.group(2)!)) {
        measured.add(name);
        changed = true;
      }
    }
  }
  return measured;
}

void main() {
  test('closeTo expects only values measured at runtime', () {
    final code = _code();
    final measured = _measuredLocals(code);
    bool isMeasured(String expr) =>
        RegExp(r'\b(ref|tester)\.').hasMatch(expr) ||
        measured.any((n) => RegExp('\\b$n\\b').hasMatch(expr));
    final offenders = [
      for (final args in _calls(code, 'closeTo'))
        if (args.isEmpty || !isMeasured(args.first)) args.join(', '),
    ];
    expect(offenders, isEmpty, reason: 'closeTo expected value not measured');
  });

  test('size matchers never compare against a literal pixel value', () {
    final code = _code();
    final measured = _measuredLocals(code);
    bool isMeasured(String expr) =>
        RegExp(r'\b(ref|tester)\.').hasMatch(expr) ||
        measured.any((n) => RegExp('\\b$n\\b').hasMatch(expr));
    final offenders = <String>[];
    for (final name in const [
      'equals',
      'greaterThan',
      'greaterThanOrEqualTo',
      'lessThan',
      'lessThanOrEqualTo',
    ]) {
      for (final args in _calls(code, name)) {
        if (args.isEmpty) continue;
        final arg = args.first;
        final isFloor = name == 'greaterThan' && arg == '40';
        final hasNumber = RegExp(r'\d').hasMatch(arg);
        if (hasNumber && !isMeasured(arg) && !isFloor) {
          offenders.add('$name($arg)');
        }
      }
    }
    expect(offenders, isEmpty, reason: 'literal expected pixel value');
  });

  test('layout test declares no numeric constant holding a pixel size', () {
    final code = _code();
    final constants = RegExp(
      r'^\s*(?:static\s+)?(?:const|final)\s+(?:(?:double|int|num)\s+)?(\w+)\s*=\s*[-\d.\s*+/()]+;',
      multiLine: true,
    ).allMatches(code).map((m) => m.group(1)!).where(
      (n) => !n.toLowerCase().contains('tolerance') &&
          !n.toLowerCase().contains('floor'),
    ).toList();
    expect(constants, isEmpty, reason: 'hard-coded pixel constant(s)');
  });
}
