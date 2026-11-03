// Like the existing architecture guards, this test helper uses the analyzer
// supplied transitively by the workspace tooling.
// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

/// Follows references from the consumer entry points rather than guessing an
/// owner from MIME literals or a particular spelling of basename extraction.
/// Only project libraries are followed; SDK and third-party calls are leaves.
class AttachmentNormalizationGraph {
  AttachmentNormalizationGraph(this.root);

  final Uri root;
  final _units = <Uri, CompilationUnit>{};
  final _definitions = <Uri, List<NormalizationDefinition>>{};

  CompilationUnit _unit(Uri uri) => _units.putIfAbsent(
    uri,
    () => parseString(content: File.fromUri(uri).readAsStringSync()).unit,
  );

  Uri? _resolve(Uri from, String? value) {
    if (value == null ||
        value.startsWith('dart:') ||
        RegExp(r'\.(g|freezed|gr|config|schema)\.dart$').hasMatch(value)) {
      return null;
    }
    for (final entry in const {
      'package:tentura_root/': 'lib/',
      'package:tentura_server/': 'packages/server/lib/',
      'package:tentura/': 'packages/client/lib/',
    }.entries) {
      if (value.startsWith(entry.key)) {
        return root.resolve(
          '${entry.value}${value.substring(entry.key.length)}',
        );
      }
    }
    return value.startsWith('package:') ? null : from.resolve(value);
  }

  List<NormalizationDefinition> _declared(Uri uri) =>
      _definitions.putIfAbsent(uri, () {
        final visitor = _Definitions(uri);
        _unit(uri).accept(visitor);
        return visitor.result;
      });

  Iterable<NormalizationDefinition> _exported(
    Uri uri,
    String name,
    Set<Uri> seen,
  ) sync* {
    if (!seen.add(uri)) return;
    yield* _declared(uri).where((definition) => definition.name == name);
    for (final directive in _unit(uri).directives) {
      if (directive is ExportDirective &&
          _allows(directive.combinators, name)) {
        final target = _resolve(uri, directive.uri.stringValue);
        if (target != null) yield* _exported(target, name, seen);
      }
      if (directive is PartDirective) {
        final target = _resolve(uri, directive.uri.stringValue);
        if (target != null) yield* _exported(target, name, seen);
      }
    }
  }

  Uri _libraryUri(Uri uri) {
    final partOf = _unit(uri).directives.whereType<PartOfDirective>();
    if (partOf.isEmpty) return uri;
    final explicit = _resolve(uri, partOf.single.uri?.stringValue);
    if (explicit != null) return _libraryUri(explicit);
    for (final entry in _units.entries.toList()) {
      if (entry.value.directives.whereType<PartDirective>().any(
        (directive) => _resolve(entry.key, directive.uri.stringValue) == uri,
      )) {
        return _libraryUri(entry.key);
      }
    }
    throw StateError('No owning library found for part $uri');
  }

  Iterable<NormalizationDefinition> _lookup(
    NormalizationDefinition from,
    String name,
  ) sync* {
    final local = _declared(from.uri)
        .where(
          (definition) =>
              definition.name == name &&
              (definition.container == null ||
                  definition.container == from.container),
        )
        .toList();
    if (local.isNotEmpty) {
      yield* local;
      return;
    }
    for (final directive in _unit(from.uri).directives) {
      if (directive is ImportDirective &&
          _allows(directive.combinators, name)) {
        if (name.startsWith('_')) continue;
        final target = _resolve(from.uri, directive.uri.stringValue);
        if (target != null) yield* _exported(target, name, {});
      }
      if (directive is PartDirective) {
        final target = _resolve(from.uri, directive.uri.stringValue);
        if (target != null) yield* _exported(target, name, {});
      }
      if (directive is PartOfDirective) {
        final target = _libraryUri(from.uri);
        yield* _exported(target, name, {});
      }
    }
  }

  NormalizationDefinition declaration(String path, String name) => _declared(
    root.resolve(path),
  ).singleWhere((definition) => definition.name == name);

  Set<NormalizationDefinition> reachable(String path, String entryPoint) {
    final entry = _exported(root.resolve(path), entryPoint, {}).single;
    final seen = <NormalizationDefinition>{};
    void visit(NormalizationDefinition definition) {
      if (!seen.add(definition)) return;
      final references = _References();
      definition.body.accept(references);
      for (final name in references.names) {
        _lookup(definition, name).forEach(visit);
      }
    }

    visit(entry);
    return seen;
  }

  /// Inventories mapping definitions across all production sources, including
  /// unreachable leftovers. Labels identify extension branches/entries; their
  /// values are resolved through project constants rather than matched by file.
  List<NormalizationDefinition> mimeTables(Set<String> extensions) {
    final result = <NormalizationDefinition>[];
    for (final directory in [
      'lib/',
      'packages/server/lib/',
      'packages/client/lib/',
    ]) {
      for (final file in Directory.fromUri(
        root.resolve(directory),
      ).listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart') ||
            RegExp(
              r'\.(g|freezed|gr|config|schema)\.dart$',
            ).hasMatch(file.path)) {
          continue;
        }
        for (final definition in _declared(file.absolute.uri)) {
          final shape = _MappingShape(extensions);
          definition.body.accept(shape);
          if (shape.labels.length < 2) continue;
          final values = shape.outputs
              .map((expression) => _stringValue(definition, expression, {}))
              .whereType<String>();
          if (values
                  .where(
                    (value) =>
                        RegExp(r'^[a-z-]+/[a-z0-9.+-]+$').hasMatch(value),
                  )
                  .toSet()
                  .length >=
              2) {
            result.add(definition);
          }
        }
      }
    }
    return result;
  }

  String? _stringValue(
    NormalizationDefinition from,
    Expression expression,
    Set<NormalizationDefinition> seen,
  ) {
    if (expression is StringLiteral) return expression.stringValue;
    final name = switch (expression) {
      SimpleIdentifier() => expression.name,
      PrefixedIdentifier() => expression.identifier.name,
      PropertyAccess() => expression.propertyName.name,
      _ => null,
    };
    if (name == null) return null;
    for (final definition in _lookup(from, name)) {
      if (seen.add(definition) && definition.body is Expression) {
        final value = _stringValue(
          definition,
          definition.body as Expression,
          seen,
        );
        if (value != null) return value;
      }
    }
    return null;
  }

  /// Executes the actual declaration in a small VM probe. Reflection permits
  /// exercising private basename helpers without changing production visibility.
  /// Map values are evaluated by Dart, so aliases/constants/computed values work.
  Future<Object?> evaluate(
    NormalizationDefinition definition, {
    List<String>? inputs,
  }) async {
    final directory = Directory.systemTemp.createTempSync('attachment-probe-');
    try {
      final script = File('${directory.path}/probe.dart');
      final libraryUri = _libraryUri(definition.uri);
      script.writeAsStringSync('''
import 'dart:convert';
import 'dart:mirrors';
import '$libraryUri';
void main() {
  final library = currentMirrorSystem().libraries.values.singleWhere(
    (library) => library.uri == Uri.parse(${jsonEncode(libraryUri.toString())}));
  final owner = ${definition.container == null ? 'library' : 'library.declarations[MirrorSystem.getSymbol(${jsonEncode(definition.container)}, library)] as ClassMirror'};
  final symbol = MirrorSystem.getSymbol(${jsonEncode(definition.name)}, library);
  final inputs = ${jsonEncode(inputs)};
  if (inputs != null) {
    final declaration = owner.declarations[symbol];
    if (declaration is! MethodMirror || declaration.parameters.length != 1 || declaration.parameters.single.type.reflectedType != String) {
      print('null');
      return;
    }
  }
  final dynamic value = inputs == null
      ? owner.getField(symbol).reflectee
      : [for (final input in inputs) owner.invoke(symbol, [input]).reflectee];
  print(jsonEncode(value is Map ? value.map((key, value) => MapEntry(key.toString(), value.toString())) : value is List ? value : null));
}
''');
      final result = await Process.run(Platform.resolvedExecutable, [
        '--packages=${File.fromUri(root.resolve('.dart_tool/package_config.json')).path}',
        script.path,
      ]).timeout(const Duration(seconds: 30));
      if (result.exitCode != 0) {
        throw StateError('Probe of $definition failed: ${result.stderr}');
      }
      return jsonDecode((result.stdout as String).trim().split('\n').last);
    } finally {
      directory.deleteSync(recursive: true);
    }
  }
}

bool _allows(
  NodeList<Combinator> combinators,
  String name,
) => combinators.every((combinator) {
  if (combinator is ShowCombinator) {
    return combinator.shownNames.any((identifier) => identifier.name == name);
  }
  if (combinator is HideCombinator) {
    return !combinator.hiddenNames.any((identifier) => identifier.name == name);
  }
  return true;
});

class NormalizationDefinition {
  NormalizationDefinition(
    this.uri,
    this.name,
    this.body, {
    this.container,
    this.isVariable = false,
  });
  final Uri uri;
  final String name;
  final AstNode body;
  final String? container;
  final bool isVariable;

  @override
  String toString() => '$uri#${container == null ? '' : '$container.'}$name';
}

class _Definitions extends RecursiveAstVisitor<void> {
  _Definitions(this.uri);
  final Uri uri;
  final result = <NormalizationDefinition>[];

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    if (node.parent is CompilationUnit) {
      result.add(
        NormalizationDefinition(
          uri,
          node.name.lexeme,
          node.functionExpression.body,
        ),
      );
    }
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    final container =
        node
            .thisOrAncestorOfType<ClassDeclaration>()
            ?.namePart
            .typeName
            .lexeme ??
        node.thisOrAncestorOfType<MixinDeclaration>()?.name.lexeme;
    result.add(
      NormalizationDefinition(
        uri,
        node.name.lexeme,
        node.body,
        container: container,
      ),
    );
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    final parent = node.parent?.parent;
    if ((parent is TopLevelVariableDeclaration ||
            parent is FieldDeclaration && parent.isStatic) &&
        node.initializer != null) {
      result.add(
        NormalizationDefinition(
          uri,
          node.name.lexeme,
          node.initializer!,
          container: parent is FieldDeclaration
              ? node
                    .thisOrAncestorOfType<ClassDeclaration>()
                    ?.namePart
                    .typeName
                    .lexeme
              : null,
          isVariable: true,
        ),
      );
    }
  }
}

class _References extends RecursiveAstVisitor<void> {
  final names = <String>{};
  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    names.add(node.name);
    super.visitSimpleIdentifier(node);
  }
}

class _MappingShape extends RecursiveAstVisitor<void> {
  _MappingShape(this.extensions);
  final Set<String> extensions;
  final labels = <String>{};
  final outputs = <Expression>[];

  void label(Expression expression) {
    if (expression is StringLiteral) {
      final value = expression.stringValue;
      if (value != null) {
        final extension = value.startsWith('.') ? value.substring(1) : value;
        if (extensions.contains(extension)) labels.add(extension);
      }
    }
  }

  @override
  void visitMapLiteralEntry(MapLiteralEntry node) {
    label(node.key);
    outputs.add(node.value);
    super.visitMapLiteralEntry(node);
  }

  @override
  void visitSwitchCase(SwitchCase node) {
    label(node.expression);
    super.visitSwitchCase(node);
  }

  @override
  void visitConstantPattern(ConstantPattern node) {
    label(node.expression);
    super.visitConstantPattern(node);
  }

  @override
  void visitSwitchExpressionCase(SwitchExpressionCase node) {
    outputs.add(node.expression);
    super.visitSwitchExpressionCase(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'endsWith' &&
        node.argumentList.arguments.length == 1) {
      label(node.argumentList.arguments.single.argumentExpression);
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitReturnStatement(ReturnStatement node) {
    if (node.expression case final expression?) outputs.add(expression);
    super.visitReturnStatement(node);
  }
}
