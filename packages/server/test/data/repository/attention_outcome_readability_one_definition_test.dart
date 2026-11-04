// Analyzer is a transitive dependency, as in the other architecture guards.
// ignore_for_file: depend_on_referenced_packages
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:test/test.dart';

/// Ownership/composition guard, paired with the real PostgreSQL agreement
/// tests. Follow Dart references from public operations, through constants,
/// getters and helper functions, rather than matching one spelling of SQL.
/// SQL branch semantics are asserted by the PostgreSQL tests: CASE, reversed
/// operands, IN/ANY, aliases, parentheses and whitespace are not prescribed here.
/// SELECT projections of readability flags are not policy definitions.
void main() {
  final graph = _PolicyGraph();
  final consumers = {
    'Activity feed': graph.member('AttentionRepository', 'attentionFeed'),
    'Dismiss all': graph.member('AttentionSweepRepository', 'dismissAll'),
    'undo': graph.member('AttentionSweepRepository', 'undo'),
  };

  group('outcome readability has one shared policy', () {
    test('feed, Dismiss all and undo reach only one policy definition', () {
      final owners = {
        for (final root in consumers.values) ...graph.policies(root),
      };
      expect(
        owners.map((owner) => owner.label).toList(),
        hasLength(1),
        reason:
            'separate policy definitions can drift, including helper copies',
      );
    });

    test('repositories compose the policy from the shared SQL module', () {
      for (final entry in consumers.entries) {
        final owners = graph.policies(entry.value);
        expect(
          owners,
          isNotEmpty,
          reason: '${entry.key} must check readability',
        );
        expect(
          owners
              .where((owner) => owner.path != _sharedModule)
              .map(
                (owner) => owner.label,
              ),
          isEmpty,
          reason: '${entry.key} must not define its own readability policy',
        );
      }
    });

    test('one shared policy supplies both live and tombstone reads to every '
        'operation', () {
      final common = consumers.values
          .map(graph.policies)
          .reduce((left, right) => left.intersection(right));
      expect(
        common.map((owner) => owner.label).toList(),
        hasLength(1),
        reason: 'all operations must compose the same complete policy',
      );
      final owner = common.single;
      expect(owner.path, _sharedModule);
      expect(graph.functionsBelow(owner), _readabilityFunctions);
    });
  });
}

const _sharedModule = 'lib/data/repository/attention_dismissible_sql.dart';
const _readabilityFunctions = {
  'beacon_can_read_content',
  'beacon_can_read_tombstone',
};

class _PolicyGraph {
  _PolicyGraph() {
    for (final path in [
      _sharedModule,
      'lib/data/repository/attention_repository.dart',
      'lib/data/repository/attention_sweep_repository.dart',
    ]) {
      final collector = _Declarations(path);
      parseString(
        content: File(path).readAsStringSync(),
      ).unit.accept(collector);
      definitions.addAll(collector.definitions);
    }
    for (final definition in definitions) {
      final references = _References();
      definition.body.accept(references);
      for (final reference in references.names) {
        final parts = reference.split('.');
        final scope = parts.length == 2 ? parts.first : definition.scope;
        final name = parts.last;
        definition.dependencies.addAll(
          definitions.where((candidate) {
            if (candidate.name != name) return false;
            return candidate.scope == scope ||
                (parts.length == 1 &&
                    candidate.scope == null &&
                    (candidate.path == definition.path ||
                        candidate.path == _sharedModule));
          }),
        );
      }
    }
  }

  final definitions = <_Definition>[];

  _Definition member(String scope, String name) => definitions.singleWhere(
    (definition) => definition.scope == scope && definition.name == name,
  );

  Set<_Definition> below(_Definition root) {
    final visited = <_Definition>{};
    void walk(_Definition node) {
      if (!visited.add(node)) return;
      node.dependencies.forEach(walk);
    }

    walk(root);
    return visited;
  }

  Set<String> functionsBelow(_Definition root) => {
    for (final definition in below(root)) ...definition.functions,
  };

  /// A policy owns both primitives, directly or through smaller helpers.
  /// Wrappers which merely compose a complete policy are not extra owners.
  /// A wrapper containing another full literal remains an extra owner.
  Set<_Definition> policies(_Definition root) => {
    for (final definition in below(root))
      if (functionsBelow(definition).containsAll(_readabilityFunctions) &&
          (definition.functions.containsAll(_readabilityFunctions) ||
              !below(definition)
                  .where((child) => child != definition)
                  .any(
                    (child) => functionsBelow(child).containsAll(
                      _readabilityFunctions,
                    ),
                  )))
        definition,
  };
}

class _Definition {
  _Definition(this.path, this.scope, this.name, this.body) {
    final literals = _SqlLiterals();
    body.accept(literals);
    functions = {
      for (final sql in literals.values) ..._predicateFunctions(sql),
    };
  }

  final String path;
  final String? scope;
  final String name;
  final AstNode body;
  final dependencies = <_Definition>{};
  late final Set<String> functions;
  String get label => '$path: ${scope == null ? '' : '$scope.'}$name';
}

class _Declarations extends RecursiveAstVisitor<void> {
  _Declarations(this.path);
  final String path;
  final definitions = <_Definition>[];

  String? scope(AstNode node) {
    for (var parent = node.parent; parent != null; parent = parent.parent) {
      if (parent is ClassDeclaration) return parent.namePart.typeName.lexeme;
    }
    return null;
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    definitions.add(
      _Definition(path, scope(node), node.name.lexeme, node.body),
    );
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    if (node.parent is CompilationUnit) {
      definitions.add(
        _Definition(path, null, node.name.lexeme, node.functionExpression.body),
      );
    }
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    final parent = node.parent?.parent;
    if ((parent is FieldDeclaration || parent is TopLevelVariableDeclaration) &&
        node.initializer != null) {
      definitions.add(
        _Definition(path, scope(node), node.name.lexeme, node.initializer!),
      );
    }
  }
}

class _References extends RecursiveAstVisitor<void> {
  final names = <String>{};

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    final parent = node.parent;
    if (parent is PrefixedIdentifier) {
      if (node == parent.identifier) names.add(parent.toSource());
    } else if (parent is PropertyAccess && node == parent.propertyName) {
      names.add('${parent.target}.${node.name}');
    } else if (parent is MethodInvocation && node == parent.methodName) {
      names.add(
        parent.target == null ? node.name : '${parent.target}.${node.name}',
      );
    } else {
      names.add(node.name);
    }
  }
}

class _SqlLiterals extends RecursiveAstVisitor<void> {
  final values = <String>[];

  static String text(StringLiteral node) => switch (node) {
    AdjacentStrings() => node.strings.map(text).join(),
    StringInterpolation() =>
      node.elements
          .map(
            (element) => element is InterpolationString ? element.value : ' ',
          )
          .join(),
    _ => node.stringValue ?? '',
  };

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) =>
      values.add(text(node));

  @override
  void visitStringInterpolation(StringInterpolation node) =>
      values.add(text(node));

  @override
  void visitAdjacentStrings(AdjacentStrings node) => values.add(text(node));
}

/// Lex SQL tokens, ignoring comments and string values. Track SELECT lists so
/// projected readability flags do not masquerade as a second policy. This
/// inspects which primitives a policy depends on, never its boolean spelling.
Set<String> _predicateFunctions(String sql) {
  final result = <String>{};
  final projections = <bool>[false];
  final tokens = RegExp(
    r"--[^\n]*|/\*[\s\S]*?\*/|'(?:''|[^'])*'|[a-zA-Z_][a-zA-Z_0-9]*|[()]",
  );
  for (final match in tokens.allMatches(sql)) {
    final token = match.group(0)!.toLowerCase();
    if (token.startsWith('--') ||
        token.startsWith('/*') ||
        token.startsWith("'")) {
      continue;
    }
    if (token == '(') {
      projections.add(projections.last);
    } else if (token == ')') {
      if (projections.length > 1) projections.removeLast();
    } else if (token == 'select') {
      projections[projections.length - 1] = true;
    } else if (const {
      'from',
      'where',
      'when',
      'having',
      'on',
    }.contains(token)) {
      projections[projections.length - 1] = false;
    } else if (!projections.last && _readabilityFunctions.contains(token)) {
      result.add(token);
    }
  }
  return result;
}
