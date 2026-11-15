// Analyzer is a transitive dependency, as in the other architecture guards.
// ignore_for_file: depend_on_referenced_packages
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:test/test.dart';

/// Ownership/composition guard, paired with the PostgreSQL agreement test in
/// `test/data/database/stale_help_offer_obligation_settle_migration_pg_test.dart`.
///
/// The rule that decides how a stale help-offer obligation settles (answered
/// → `resolved`, withdrawn or missing → `superseded`) must be written once.
/// The forward migration and the reconcile repository both compose that one
/// definition; a second copy could drift while the agreement test, which
/// only samples one dataset, still passes.
///
/// A declaration *defines* the rule when its SQL string literals together
/// name `withdraw_reason` and both settlement kinds. Shipped migrations
/// (m0314 and earlier) are frozen history and are not searched.
const _migrationFile = 'lib/data/database/migration/m0315.dart';
const _repositoryFile =
    'lib/data/repository/attention_reconciliation_repository.dart';

void main() {
  final definitions = _ruleDefinitions();

  group('the stale help-offer settlement rule has one definition', () {
    test('exactly one declaration under lib/ defines the rule', () {
      expect(
        definitions.map((d) => d.label).toList(),
        hasLength(1),
        reason:
            'separate copies of the settle rule can drift between the '
            'migration and the repository',
      );
    });

    test('the forward migration composes the shared rule instead of holding '
        'its own copy', () {
      expect(
        File(_migrationFile).existsSync(),
        isTrue,
        reason: 'the settle migration lives in $_migrationFile',
      );
      expect(
        definitions.where((d) => d.path == _migrationFile),
        isEmpty,
        reason: 'the migration must not define its own settle rule',
      );
      expect(definitions, hasLength(1));
      final owner = definitions.single;
      expect(
        _referencedNames(_migrationFile).intersection(
          _declaredNames(owner.path),
        ),
        isNotEmpty,
        reason: 'the migration must reference the shared rule in ${owner.path}',
      );
    });

    test('the reconcile repository composes the same shared rule', () {
      expect(definitions, hasLength(1));
      final owner = definitions.single;
      if (owner.path == _repositoryFile) return;
      expect(
        _referencedNames(_repositoryFile).intersection(
          _declaredNames(owner.path),
        ),
        isNotEmpty,
        reason:
            'settleObsoleteHelpOfferObligations must use the shared rule in '
            '${owner.path}',
      );
    });
  });
}

final class _Definition {
  const _Definition(this.path, this.name);

  final String path;
  final String name;

  String get label => '$path#$name';
}

bool _isShippedMigration(String path) {
  final match = RegExp(r'migration/m(\d{4})\.dart$').firstMatch(path);
  return match != null && int.parse(match.group(1)!) <= 314;
}

List<File> _libFiles() =>
    Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => !f.path.endsWith('.g.dart'))
        .where((f) => !f.path.endsWith('.freezed.dart'))
        .where((f) => !_isShippedMigration(f.path))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

CompilationUnit _parse(String path) =>
    parseString(content: File(path).readAsStringSync(), path: path).unit;

bool _definesRule(String sql) =>
    sql.contains('withdraw_reason') &&
    sql.contains("'superseded'") &&
    sql.contains("'resolved'");

List<_Definition> _ruleDefinitions() {
  final found = <_Definition>[];
  for (final file in _libFiles()) {
    final visitor = _DeclarationVisitor();
    _parse(file.path).accept(visitor);
    for (final entry in visitor.strings.entries) {
      if (_definesRule(entry.value.toString())) {
        found.add(_Definition(file.path, entry.key));
      }
    }
  }
  return found;
}

/// Names a file declares: top-level functions and variables, methods and
/// fields.
Set<String> _declaredNames(String path) {
  final visitor = _DeclarationVisitor();
  _parse(path).accept(visitor);
  return visitor.strings.keys.toSet();
}

/// String literal text gathered per declaration (function, method, or
/// variable), keyed by the declaration's name.
class _DeclarationVisitor extends RecursiveAstVisitor<void> {
  final strings = <String, StringBuffer>{};

  void _collect(String name, AstNode node) {
    final collector = _StringCollector();
    node.accept(collector);
    (strings[name] ??= StringBuffer()).write(collector.text);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    _collect(node.name.lexeme, node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    _collect(node.name.lexeme, node);
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    _collect(node.name.lexeme, node);
  }
}

/// Identifiers a file uses (not the ones it declares).
Set<String> _referencedNames(String path) {
  final collector = _IdentifierCollector();
  _parse(path).accept(collector);
  return collector.names;
}

class _StringCollector extends RecursiveAstVisitor<void> {
  final text = StringBuffer();

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    text
      ..write(node.value)
      ..write('\n');
  }

  @override
  void visitInterpolationString(InterpolationString node) {
    text.write(node.value);
  }
}

class _IdentifierCollector extends RecursiveAstVisitor<void> {
  final names = <String>{};

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (!node.inDeclarationContext()) {
      names.add(node.name);
    }
    super.visitSimpleIdentifier(node);
  }
}
