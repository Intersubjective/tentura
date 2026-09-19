import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// U07b2 item 3. `resolutionTransitions` is the specification for how an
/// obligation is allowed to end; the code is the evidence. U07a found the
/// contract naming two methods that do not exist (`withdrawHelpOffer`,
/// `submitReviewPackage`) — a declaration nobody can follow back to code is
/// worse than none, because it reads as a guarantee.
///
/// This test only enforces the cheap half of that: every declared transition
/// must name a method that exists on the class it names. Whether that method
/// *settles* is proven by the PG settlement suites, not by a grep.
void main() {
  test('every declared resolution transition names a method that exists', () {
    final missing = <String>[];
    for (final transition in _declaredTransitions()) {
      if (!_methodExists(transition)) missing.add(transition);
    }
    expect(
      missing,
      isEmpty,
      reason:
          'resolutionTransitions naming methods that do not exist in '
          'packages/server/lib:\n${missing.join('\n')}',
    );
  });

  test('the rule rejects a transition that names nothing', () {
    // Proof that the rule bites: these are the two labels U07a found, kept
    // here as the negative fixture after the contract stopped declaring them.
    expect(_methodExists('EvaluationCase.submitReviewPackage'), isFalse);
    expect(_methodExists('HelpOfferCase.withdrawHelpOffer'), isFalse);
    expect(_methodExists('NoSuchCase.doThing'), isFalse);
  });

  test('the rule accepts the live methods the settlement suites exercise', () {
    expect(_methodExists('EvaluationCase.evaluationFinalize'), isTrue);
    expect(_methodExists('HelpOfferCase.withdraw'), isTrue);
  });
}

List<String> _declaredTransitions() {
  final contract =
      jsonDecode(_contractFile().readAsStringSync()) as Map<String, dynamic>;
  final transitions = <String>[];
  for (final entry in (contract['eventClassifications']! as List)) {
    for (final variant in ((entry as Map)['variants']! as List)) {
      final declared = (variant as Map)['resolutionTransitions'] as List?;
      if (declared == null) continue;
      transitions.addAll(declared.cast<String>());
    }
  }
  expect(transitions, isNotEmpty, reason: 'contract declares no transitions');
  return transitions;
}

bool _methodExists(String transition) {
  final parts = transition.split('.');
  if (parts.length != 2) return false;
  final [className, methodName] = parts;
  final source = _sourceDeclaring(className);
  if (source == null) return false;
  // Member declarations in these use cases sit at two-space indent; matching
  // the declaration rather than any occurrence keeps a call site from
  // vouching for a method that was never defined.
  final declaration = RegExp(
    r'^  (?:@override\s+)?[A-Za-z_][\w<>,\[\]\?\s]*\s' +
        RegExp.escape(methodName) +
        r'\s*\(',
    multiLine: true,
  );
  return declaration.hasMatch(source);
}

String? _sourceDeclaring(String className) {
  final declaration = RegExp(
    r'^(?:abstract |final |base |sealed )*class ' +
        RegExp.escape(className) +
        r'\b',
    multiLine: true,
  );
  for (final file in _libFiles()) {
    final source = file.readAsStringSync();
    if (declaration.hasMatch(source)) return source;
  }
  return null;
}

List<File> _libFiles() {
  for (final path in const ['lib', 'packages/server/lib']) {
    final dir = Directory(path);
    if (!dir.existsSync()) continue;
    return dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .toList(growable: false);
  }
  throw StateError('server lib not found');
}

File _contractFile() {
  for (final path in const [
    '../../docs/contracts/updates-event-contract.json',
    'docs/contracts/updates-event-contract.json',
  ]) {
    final file = File(path);
    if (file.existsSync()) return file.absolute;
  }
  throw StateError('Updates event contract not found');
}
