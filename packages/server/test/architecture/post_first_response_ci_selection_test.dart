// The analyzer is a transitive dependency, as in the other AST guards.
// ignore_for_file: depend_on_referenced_packages

import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:test/test.dart';

const _raceName =
    'a message and a reaction from the same member at the same '
    'time make exactly one claim, in every round';
const _multiTag = 'multi-connection';
const _suite = 'test/domain/use_case/post_first_response_pg_test.dart';
const _selectionTimeout = Timeout(Duration(minutes: 2));

Future<ProcessResult> _runPgSelection(List<String> tags) => Process.run(
  'timeout',
  [
    '--kill-after=5s',
    '90s',
    Platform.resolvedExecutable,
    'test',
    '--reporter=expanded',
    ...tags,
    _suite,
  ],
  environment: {'TENTURA_TEST_PG_POOL_SIZE': '1'},
);

bool _containsMultiTag(AstNode value) => switch (value) {
  StringLiteral() => value.stringValue == _multiTag,
  ListLiteral() => value.elements.any(_containsMultiTag),
  _ => false,
};

bool _hasMultiTag(MethodInvocation call) =>
    call.argumentList.arguments.whereType<NamedArgument>().any(
      (arg) =>
          arg.name.lexeme == 'tags' &&
          _containsMultiTag(arg.argumentExpression),
    );

bool _inheritsMultiTag(MethodInvocation test) {
  for (var node = test.parent; node != null; node = node.parent) {
    if (node is MethodInvocation &&
        node.methodName.name == 'group' &&
        _hasMultiTag(node)) {
      return true;
    }
  }
  return false;
}

String _testName(MethodInvocation test) =>
    (test.argumentList.arguments.first as StringLiteral).stringValue!;

class _Tests extends RecursiveAstVisitor<void> {
  final registrations = <MethodInvocation>[];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'test') registrations.add(node);
    super.visitMethodInvocation(node);
  }
}

void main() {
  final unit = parseString(content: File(_suite).readAsStringSync()).unit;
  final tests = _Tests();
  unit.accept(tests);

  test(
    'only the Post first-response race moves out of the single-pool run',
    () {
      final suiteTagged = unit.directives
          .expand((d) => d.metadata)
          .any(
            (annotation) =>
                annotation.name.name == 'Tags' &&
                (annotation.arguments?.arguments.any(_containsMultiTag) ??
                    false),
          );
      final tagged = [
        for (final registration in tests.registrations)
          if (suiteTagged ||
              _inheritsMultiTag(registration) ||
              _hasMultiTag(registration))
            _testName(registration),
      ];
      expect(tagged, [_raceName]);
      final race = tests.registrations.singleWhere(
        (t) => _testName(t) == _raceName,
      );
      expect(_hasMultiTag(race), isTrue, reason: 'tag the race test directly');
    },
  );

  test(
    'the single-connection CI run passes every Post first-response sibling',
    () async {
      final run = await _runPgSelection([
        '--tags',
        'pg',
        '--exclude-tags',
        'mr,multi-connection',
      ]);
      final output = '${run.stdout}\n${run.stderr}';
      expect(output, isNot(contains(_raceName)), reason: output);
      expect(run.exitCode, 0, reason: output);
      final siblings = tests.registrations
          .map(_testName)
          .where(
            (name) => name != _raceName && name != 'Postgres unavailable',
          );
      for (final name in siblings) {
        expect(output, contains(name));
      }
      expect(output, contains('+${siblings.length}: All tests passed!'));
    },
    tags: 'pg',
    timeout: _selectionTimeout,
  );

  test(
    'the multi-connection CI run passes only the Post first-response race',
    () async {
      final run = await _runPgSelection(['--tags', _multiTag, '-j', '1']);
      final output = '${run.stdout}\n${run.stderr}';
      expect(output, contains(_raceName), reason: output);
      expect(run.exitCode, 0, reason: output);
      expect(output, contains('+1: All tests passed!'));
    },
    tags: 'pg',
    timeout: _selectionTimeout,
  );
}
