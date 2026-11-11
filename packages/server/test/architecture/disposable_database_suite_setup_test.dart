// The analyzer is a transitive dependency, as in the other AST guards.
// ignore_for_file: depend_on_referenced_packages
@Tags(['repo-files'])
library;

import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:test/test.dart';

class _Calls extends RecursiveAstVisitor<void> {
  final calls = <MethodInvocation>[];
  final constructors = <InstanceCreationExpression>[];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    calls.add(node);
    super.visitMethodInvocation(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    constructors.add(node);
    super.visitInstanceCreationExpression(node);
  }
}

class _Declarations extends RecursiveAstVisitor<void> {
  final bodies = <String, List<AstNode>>{};

  void add(String name, AstNode body) =>
      bodies.putIfAbsent(name, () => []).add(body);

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    add(node.name.lexeme, node.functionExpression.body);
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    add(node.name.lexeme, node.body);
    super.visitMethodDeclaration(node);
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    final initializer = node.initializer;
    if (initializer is FunctionExpression) {
      add(node.name.lexeme, initializer.body);
    }
    super.visitVariableDeclaration(node);
  }
}

class _Unit {
  factory _Unit(File file, {String? source}) =>
      _Unit._(file, source ?? file.readAsStringSync());

  _Unit._(this.file, this.source) : unit = parseString(content: source).unit {
    unit.accept(declarations);
  }

  final File file;
  final String source;
  final CompilationUnit unit;
  final declarations = _Declarations();

  Iterable<_Unit> imports(Map<String, _Unit> cache, String? prefix) sync* {
    for (final directive in unit.directives.whereType<ImportDirective>()) {
      if (directive.prefix?.name != prefix) continue;
      final uri = Uri.parse(directive.uri.stringValue!);
      if (uri.hasScheme && uri.scheme != 'file') continue;
      final imported = File.fromUri(file.absolute.uri.resolveUri(uri));
      if (!imported.existsSync()) continue;
      yield cache.putIfAbsent(imported.path, () => _Unit(imported));
    }
  }
}

// Follow local and imported test helpers, including closures assigned to a
// variable. Report a call chain, rather than trusting a helper's name to say
// whether it provisions a database. Cycles are visited only once per root.
List<String>? _provisioningPath(
  _Unit owner,
  AstNode body,
  Map<String, _Unit> cache,
  Set<String> seen,
) {
  if (body is FunctionReference) {
    return _provisioningPath(owner, body.function, cache, seen);
  }
  if (!seen.add('${owner.file.path}:${body.offset}')) return null;
  final reference = switch (body) {
    SimpleIdentifier() => (body.name, null),
    PrefixedIdentifier() => (body.identifier.name, body.prefix.name),
    PropertyAccess() => (body.propertyName.name, body.target?.toSource()),
    _ => null,
  };
  if (reference != null) {
    for (final candidate in [owner, ...owner.imports(cache, reference.$2)]) {
      for (final next
          in candidate.declarations.bodies[reference.$1] ?? <AstNode>[]) {
        final path = _provisioningPath(candidate, next, cache, seen);
        if (path != null) return [reference.$1, ...path];
      }
    }
  }
  final visitor = _Calls();
  body.accept(visitor);
  for (final call in visitor.calls) {
    final name = call.methodName.name;
    if (name == 'setUpDisposablePgWriter' || name == 'recreate') {
      return [name];
    }
    final target = call.target;
    final prefix = target is SimpleIdentifier ? target.name : null;
    final candidates = <_Unit>[
      owner,
      ...owner.imports(cache, prefix),
    ];
    for (final candidate in candidates) {
      for (final next in candidate.declarations.bodies[name] ?? <AstNode>[]) {
        final path = _provisioningPath(candidate, next, cache, seen);
        if (path != null) return [name, ...path];
      }
    }
  }
  return null;
}

List<String> _provisioningViolations(_Unit owner, Map<String, _Unit> cache) {
  final registrations = _Calls();
  owner.unit.accept(registrations);
  final violations = <String>[];
  for (final registration in registrations.calls) {
    final name = registration.methodName.name;
    if (name != 'test' && name != 'setUp') continue;
    // Named arguments may precede the body. test has a description then a
    // callback; setUp has just a callback. Neither may consume the test budget
    // provisioning a database, even through a named or generic tear-off.
    final positional = registration.argumentList.arguments
        .where((argument) => argument is! NamedArgument)
        .toList();
    if (positional.length != (name == 'test' ? 2 : 1)) continue;
    final path = _provisioningPath(owner, positional.last, cache, {});
    if (path == null) continue;
    final line = owner.source
        .substring(0, registration.offset)
        .split('\n')
        .length;
    final label = name == 'test' ? positional.first.toSource() : 'setUp';
    violations.add('${owner.file.path}:$line: $label -> ${path.join(' -> ')}');
  }
  return violations;
}

void main() {
  group('disposable provisioning callback audit', () {
    for (final registration in [
      "test('rows', skip: false, () => provision())",
      "test('rows', skip: false, provision)",
      "test('rows', provision, skip: false)",
      'setUp(() => provision())',
      'setUp(provision)',
      'setUp(genericProvision<int>)',
      'setUp(() => target.recreate())',
    ]) {
      test('rejects $registration', () {
        final owner = _Unit(
          File('callback_fixture.dart'),
          source:
              '''
Future<void> provision() => setUpDisposablePgWriter();
Future<void> genericProvision<T>() => provision();
void main() { $registration; }
''',
        );
        expect(_provisioningViolations(owner, {}), hasLength(1));
      });
    }
    test('allows provisioning confined to suite setup', () {
      final owner = _Unit(
        File('callback_fixture.dart'),
        source: '''
Future<void> provision() => setUpDisposablePgWriter();
void main() {
  setUpAll(provision);
  setUp(() => resetCounters());
  test('rows', skip: false, () => readRows());
}
''',
      );
      expect(_provisioningViolations(owner, {}), isEmpty);
    });
  });

  test('contention contains no Timer or Future.delayed calls', () {
    final file = File(
      'test/data/repository/'
      'constellation_received_request_provenance_contention_pg_test.dart',
    );
    final unit = _Unit(file);
    final calls = _Calls();
    unit.unit.accept(calls);
    String baseType(String source) =>
        source.replaceAll(RegExp('<.*>'), '').split('.').last;
    final waits = <String>[
      for (final constructor in calls.constructors)
        if (baseType(constructor.constructorName.type.toSource()) == 'Timer' ||
            (baseType(constructor.constructorName.type.toSource()) ==
                    'Future' &&
                constructor.constructorName.name?.name == 'delayed'))
          constructor.toSource(),
      for (final call in calls.calls)
        if (call.methodName.name == 'Timer' ||
            (baseType(call.target?.toSource() ?? '') == 'Future' &&
                call.methodName.name == 'delayed') ||
            baseType(call.target?.toSource() ?? '') == 'Timer')
          call.toSource(),
    ];
    expect(
      waits,
      isEmpty,
      reason:
          'Timer and Future.delayed are forbidden in the contention file; '
          'other release conditions are verified by the runtime probe.',
    );
  });

  test(
    'pg test bodies and per-test setup leave disposable provisioning to suite setup',
    () {
      final cache = <String, _Unit>{};
      final violations = <String>[];
      final files =
          Directory('test')
              .listSync(recursive: true)
              .whereType<File>()
              .where((file) => file.path.endsWith('_pg_test.dart'))
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));
      expect(files, isNotEmpty);
      for (final file in files) {
        final owner = cache.putIfAbsent(file.absolute.path, () => _Unit(file));
        violations.addAll(_provisioningViolations(owner, cache));
      }
      expect(
        violations,
        isEmpty,
        reason:
            'Provision in setUpAll so lifecycle-lock contention cannot consume '
            'the 30-second behaviour budget:\n${violations.join('\n')}',
      );
    },
  );
}
