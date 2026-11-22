// The analyzer is reachable transitively through build_runner.
// ignore_for_file: depend_on_referenced_packages

import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:test/test.dart';

void main() {
  test('new test-only injectable registrations stay outside lib', () {
    final offenders = <String>[];
    for (final file in _dartFiles('lib')) {
      final annotations = _TestOnlyAnnotations();
      _parse(file).accept(annotations);
      if (annotations.found) {
        offenders.add(file.path);
      }
    }

    expect(
      offenders..sort(),
      isEmpty,
      reason: 'Move these test-only injectable registrations to test/support.',
    );
  });
}

Iterable<File> _dartFiles(String directory) => Directory(directory)
    .listSync(recursive: true)
    .whereType<File>()
    .where((file) => file.path.endsWith('.dart'));

CompilationUnit _parse(File file) =>
    parseString(path: file.path, content: file.readAsStringSync()).unit;

String _annotationName(Annotation annotation) =>
    annotation.name.name.split('.').last;

Expression? _argument(ArgumentList? arguments, String name) {
  for (final argument
      in arguments?.arguments.whereType<NamedArgument>() ??
          const <NamedArgument>[]) {
    if (argument.name.lexeme == name) return argument.argumentExpression;
  }
  return null;
}

bool _testOnly(Annotation annotation) {
  final env = _argument(annotation.arguments, 'env');
  if (env is! ListLiteral || env.elements.length != 1) return false;
  final name = env.elements.single.toSource();
  return name == 'Environment.test' || name.endsWith('.Environment.test');
}

class _TestOnlyAnnotations extends RecursiveAstVisitor<void> {
  bool found = false;

  @override
  void visitAnnotation(Annotation node) {
    if (const {
          'Injectable',
          'Singleton',
          'LazySingleton',
        }.contains(_annotationName(node)) &&
        _testOnly(node)) {
      found = true;
    }
    super.visitAnnotation(node);
  }
}
