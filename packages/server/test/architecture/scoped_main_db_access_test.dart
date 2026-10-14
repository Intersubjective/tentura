// The analyzer is only reachable transitively; this is a test-only AST check.
// ignore_for_file: depend_on_referenced_packages
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:test/test.dart';

void main() {
  group('Independent main database scopes', () {
    final database = File('lib/data/database/tentura_db.dart');

    test('the main database is not registered as a singleton', () {
      expect(
        RegExp(
          r'^\s*@(?:singleton|Singleton)\b',
          multiLine: true,
        ).hasMatch(database.readAsStringSync()),
        isFalse,
        reason:
            'Independent V2 requests must receive scoped DB handles. '
            'The named auth database may still own its separate pool.',
      );
    });

    test('transaction ownership uses the leased scope executor', () {
      expect(
        RegExp(
          r'@override\s+Future<[^>]+>\s+transaction<[^>]+>\s*\(',
        ).hasMatch(database.readAsStringSync()),
        isFalse,
        reason:
            'TenturaDb must inherit Drift transaction ownership instead '
            'of leasing a connection before acquiring a shared Drift lock.',
      );
    });

    test('pool pinning shims are absent from production database code', () {
      expect(
        _classDefinitions({'_PinnedPoolSession'}),
        isEmpty,
        reason:
            'A connection lease belongs to one scope through commit or '
            'rollback; overlapping requests must not share a pinned session.',
      );
    });

    test('transaction executor spike and its rollout flag are retired', () {
      expect(
        _classDefinitions({
          '_TransactionPinnedPgDatabase',
          '_TransactionPinnedDelegate',
          '_PinnedTransactionDelegate',
        }),
        isEmpty,
        reason:
            'Scoped Drift executors replace the experimental transaction '
            'delegate and its savepoint ownership.',
      );
      expect(
        File('lib/env.dart').readAsStringSync(),
        isNot(contains('DRIFT_TRANSACTION_PINNED_POOL_ENABLED')),
        reason: 'Main DB concurrency must no longer depend on the spike flag.',
      );
    });

    test('constellation work has no separate waiting queue', () {
      final scheduler = File(
        'lib/data/service/constellation_db_scheduler.dart',
      );
      if (!scheduler.existsSync()) return;

      expect(
        RegExp(r'\bQueue\s*<').hasMatch(scheduler.readAsStringSync()),
        isFalse,
        reason:
            'A compatibility adapter may remain, but all main DB scopes '
            'must wait in one bounded admission queue.',
      );
    });
  });

  group('Transaction entry-point scanner', () {
    const database = '''
      class TenturaDb {
        Future<T> withTransaction<T>(Future<T> Function() a) =>
            owner.transaction(a);
        Future<T> withBatchedWrite<T>(Future<T> Function() a) =>
            withTransaction(a);
        Future<void> unrelated() async {}
      }
    ''';
    const probe = 'lib/data/repository/probe_repository.dart';

    // The stand-in database declares the wrappers; only call sites elsewhere
    // are of interest.
    List<String> outsideDatabase(Map<String, String> sources) => [
      for (final key in _scanTransactionEntryPoints({
        _tenturaDbPath: database,
        ...sources,
      }))
        if (!key.startsWith(_tenturaDbPath)) key,
    ];

    List<String> scan(String repository) =>
        outsideDatabase({probe: repository});

    test('database wrappers are derived from the code, not listed by hand', () {
      final wrappers = _transactionWrapperApis(
        _parse(_tenturaDbPath, database),
      );
      expect(wrappers, {'withTransaction', 'withBatchedWrite'});
    });

    test('the real database declares every known transaction boundary', () {
      final wrappers = _transactionWrapperApis(
        _parse(_tenturaDbPath, File(_tenturaDbPath).readAsStringSync()),
      );
      expect(
        wrappers,
        containsAll([
          'withTransaction',
          'withJoinedTransaction',
          'withMutatingUser',
          'withMutatingSystem',
          'withMutatingRepeatableRead',
          'withReadSnapshot',
        ]),
      );
      expect(wrappers, isNot(contains('withConnectionScope')));
    });

    test('a call to a wrapper added under a new name is reported', () {
      expect(
        scan('class R { void f() { _db.withBatchedWrite(() async {}); } }'),
        ['$probe | R.f | withBatchedWrite'],
      );
    });

    test('a torn-off or stored wrapper is reported', () {
      expect(
        scan('class R { void f() { final run = _db.withTransaction; } }'),
        ['$probe | R.f | withTransaction'],
      );
    });

    test(
      'a Drift transaction primitive call is reported, a property is not',
      () {
        expect(
          scan(
            'class R { void f() { owner.transaction(a); '
            'stage.transaction.record(1); scope.transaction = 2; } }',
          ),
          ['$probe | R.f | transaction'],
        );
      },
    );

    test('every explicit savepoint statement form is reported', () {
      final keys = scan(r"""
        class R {
          void f() {
            _db.customStatement('savepoint a');
            _db.customStatement('SAVEPOINT $name');
            _db.customStatement('ROLLBACK TO SAVEPOINT a');
            _db.customStatement('rollback to a');
            _db.customStatement('RELEASE SAVEPOINT a');
            _db.customStatement(
              'SAVE'
              'POINT b',
            );
            _db.customStatement('''
              SAVEPOINT
                c
            ''');
          }
        }
      """);
      expect(_countKeys(keys), {
        '$probe | R.f | SAVEPOINT': 4,
        '$probe | R.f | ROLLBACK TO SAVEPOINT': 2,
        '$probe | R.f | RELEASE SAVEPOINT': 1,
      });
    });

    test('a savepoint behind leading SQL comments is still reported', () {
      final keys = scan(r"""
        class R {
          void f() {
            _db.customStatement('/* nested scope */ SAVEPOINT a');
            _db.customStatement('-- open\nSAVEPOINT b');
            _db.customStatement('/* x */ -- y\n  RELEASE SAVEPOINT a');
            _db.customStatement('/* undo */ ROLLBACK TO SAVEPOINT a');
            _db.customStatement('-- SAVEPOINT only a comment');
          }
        }
      """);
      expect(_countKeys(keys), {
        '$probe | R.f | SAVEPOINT': 2,
        '$probe | R.f | RELEASE SAVEPOINT': 1,
        '$probe | R.f | ROLLBACK TO SAVEPOINT': 1,
      });
    });

    test('prose that merely mentions a savepoint is not reported', () {
      expect(
        scan(
          "class R { void f() { throw StateError('Cannot open a savepoint "
          "here'); } }",
        ),
        isEmpty,
      );
    });

    test('a unit-of-work call through a typed field is reported', () {
      final keys = outsideDatabase({
        'lib/data/repository/probe_unit_of_work.dart': '''
          class ProbeUnitOfWork implements ProbeUnitOfWorkPort {
            Future<T> run<T>(Future<T> Function() action) => action();
          }
        ''',
        'lib/domain/use_case/probe_case.dart': '''
          class ProbeCase {
            const ProbeCase(this._uow, this._other);
            final ProbeUnitOfWorkPort _uow;
            final Other _other;
            Future<void> a() => _uow.run(() async {});
            Future<void> b() => _other.run(() async {});
          }
        ''',
      });
      expect(keys, [
        'lib/domain/use_case/probe_case.dart | ProbeCase.a | ProbeUnitOfWorkPort.run',
      ]);
    });
  });

  group('Reviewed inventory of transaction entry points', () {
    final inventoryFile = File(_transactionInventoryPath);

    test('the inventory file exists', () {
      expect(
        inventoryFile.existsSync(),
        isTrue,
        reason:
            'Every transaction root, joining wrapper and explicit savepoint '
            'in lib/ is listed in $_transactionInventoryPath with an owner '
            'and a reason, one `path | Class.member | api | owner | reason` '
            'line per call site.',
      );
    });

    test('every inventoried entry point names an owner and a reason', () {
      expect(inventoryFile.existsSync(), isTrue);
      final incomplete = [
        for (final line in _inventoryLines(inventoryFile))
          if (_inventoryFields(line).length != 5 ||
              _inventoryFields(line).any((field) => field.isEmpty))
            line,
      ];
      expect(
        incomplete,
        isEmpty,
        reason:
            'Each entry needs exactly: path | Class.member | api | owner | '
            'reason, none of them blank.',
      );
      expect(
        _inventoryLines(inventoryFile),
        isNotEmpty,
        reason: 'The server has transaction entry points; none were listed.',
      );
    });

    test('every transaction entry point in lib is reviewed and listed', () {
      expect(inventoryFile.existsSync(), isTrue);
      final reviewed = _countKeys([
        for (final line in _inventoryLines(inventoryFile))
          _inventoryFields(line).take(3).join(' | '),
      ]);
      final actual = _countKeys(_transactionEntryPoints());

      final unreviewed = <String>[
        for (final entry in actual.entries)
          if (entry.value > (reviewed[entry.key] ?? 0)) entry.key,
      ];
      expect(
        unreviewed,
        isEmpty,
        reason:
            'New or changed transaction entry points must be added to '
            '$_transactionInventoryPath with an owner and a reason.',
      );
    });

    test('the inventory lists no entry point that no longer exists', () {
      expect(inventoryFile.existsSync(), isTrue);
      final reviewed = _countKeys([
        for (final line in _inventoryLines(inventoryFile))
          _inventoryFields(line).take(3).join(' | '),
      ]);
      final actual = _countKeys(_transactionEntryPoints());

      final stale = <String>[
        for (final entry in reviewed.entries)
          if (entry.value > (actual[entry.key] ?? 0)) entry.key,
      ];
      expect(
        stale,
        isEmpty,
        reason:
            'Remove inventory lines whose call site was deleted or moved, so '
            'the reviewed list stays exactly the live set.',
      );
    });
  });
}

const _transactionInventoryPath =
    'test/architecture/transaction_entry_inventory.txt';

const _tenturaDbPath = 'lib/data/database/tentura_db.dart';

/// Drift's own transaction primitives. Only a call counts: the bare names
/// are also ordinary properties elsewhere (`scope.transaction`).
const _primitiveTransactionApis = {'transaction', 'beginTransaction'};

List<String> _inventoryLines(File file) => [
  for (final line in file.readAsLinesSync())
    if (line.trim().isNotEmpty && !line.trimLeft().startsWith('#')) line.trim(),
];

List<String> _inventoryFields(String line) => [
  for (final field in line.split('|')) field.trim(),
];

Map<String, int> _countKeys(Iterable<String> keys) {
  final counts = <String, int>{};
  for (final key in keys) {
    counts[key] = (counts[key] ?? 0) + 1;
  }
  return counts;
}

Map<String, String> _productionSources() => {
  for (final file in Directory('lib').listSync(recursive: true))
    if (file is File && file.path.endsWith('.dart') && !_isGenerated(file.path))
      file.path: file.readAsStringSync(),
};

/// One `path | Class.member | api` key per call site in production code.
List<String> _transactionEntryPoints() =>
    _scanTransactionEntryPoints(_productionSources());

CompilationUnit _parse(String path, String content) => parseString(
  content: content,
  path: path,
  throwIfDiagnostics: false,
).unit;

/// Finds every transaction root, joining wrapper and explicit savepoint in
/// [sources] (path to Dart source). The wrapper vocabulary is derived from the
/// code rather than listed by hand:
///  * every [_tenturaDbPath] method that, directly or through another such
///    method, reaches a Drift transaction primitive is a boundary, so a newly
///    added wrapper is recognised the moment it is declared;
///  * every use of such a name counts, whether called, torn off or stored in a
///    function-valued variable;
///  * methods of `*UnitOfWork` classes (and the ports they implement) are
///    boundaries for fields and parameters declared with those types;
///  * every SQL string whose statement is SAVEPOINT, RELEASE SAVEPOINT or
///    ROLLBACK TO (optionally SAVEPOINT), in any case, split across adjacent literals,
///    over several lines or interpolated.
List<String> _scanTransactionEntryPoints(Map<String, String> sources) {
  final units = {
    for (final entry in sources.entries)
      entry.key: _parse(entry.key, entry.value),
  };
  final wrapperApis = _transactionWrapperApis(units[_tenturaDbPath]);
  final boundary = _UnitOfWorkBoundary.from(units.values);
  final keys = <String>[];
  for (final entry in units.entries) {
    final types = _DeclaredTypes();
    entry.value.accept(types);
    entry.value.accept(
      _TransactionEntryVisitor(
        path: entry.key,
        keys: keys,
        wrapperApis: wrapperApis,
        boundary: boundary,
        typeByName: types.typeByName,
      ),
    );
  }
  return keys;
}

/// Names of the database methods that open or join a transaction.
Set<String> _transactionWrapperApis(CompilationUnit? database) {
  if (database == null) return {};
  final collector = _MethodCollector('TenturaDb');
  database.accept(collector);
  final wrappers = <String>{};
  var changed = true;
  while (changed) {
    changed = false;
    for (final method in collector.methods) {
      final name = method.name.lexeme;
      if (wrappers.contains(name)) continue;
      final reach = _ReachesTransaction(wrappers);
      method.body.accept(reach);
      if (reach.found) {
        wrappers.add(name);
        changed = true;
      }
    }
  }
  return wrappers;
}

class _MethodCollector extends RecursiveAstVisitor<void> {
  _MethodCollector(this._className);

  final String _className;
  final methods = <MethodDeclaration>[];

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    if (_enclosingTypeName(node) == _className) methods.add(node);
    super.visitMethodDeclaration(node);
  }
}

class _ReachesTransaction extends RecursiveAstVisitor<void> {
  _ReachesTransaction(this._wrappers);

  final Set<String> _wrappers;
  bool found = false;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (_primitiveTransactionApis.contains(node.methodName.name)) found = true;
    super.visitMethodInvocation(node);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (_wrappers.contains(node.name)) found = true;
    super.visitSimpleIdentifier(node);
  }
}

/// Unit-of-work types: classes named `*UnitOfWork` and the ports they
/// implement, with the methods those classes declare.
class _UnitOfWorkBoundary {
  _UnitOfWorkBoundary(this.types, this.methods);

  factory _UnitOfWorkBoundary.from(Iterable<CompilationUnit> units) {
    final types = <String>{};
    final methods = <String>{};
    for (final unit in units) {
      for (final declaration in unit.declarations) {
        if (declaration is! ClassDeclaration) continue;
        final name = declaration.namePart.typeName.lexeme;
        if (!name.endsWith('UnitOfWork')) continue;
        types.add(name);
        for (final port
            in declaration.implementsClause?.interfaces ?? <NamedType>[]) {
          types.add(port.name.lexeme);
        }
        final collector = _MethodCollector(name);
        declaration.accept(collector);
        methods.addAll(collector.methods.map((m) => m.name.lexeme));
      }
    }
    return _UnitOfWorkBoundary(types, methods);
  }

  final Set<String> types;
  final Set<String> methods;
}

/// Declared type names by variable, field and parameter name (per file).
class _DeclaredTypes extends RecursiveAstVisitor<void> {
  final typeByName = <String, Set<String>>{};

  void _add(String? name, TypeAnnotation? type) {
    if (name == null || type is! NamedType) return;
    typeByName.putIfAbsent(name, () => {}).add(type.name.lexeme);
  }

  @override
  void visitVariableDeclarationList(VariableDeclarationList node) {
    for (final variable in node.variables) {
      _add(variable.name.lexeme, node.type);
    }
    super.visitVariableDeclarationList(node);
  }

  @override
  void visitRegularFormalParameter(RegularFormalParameter node) {
    _add(node.name?.lexeme, node.type);
    super.visitRegularFormalParameter(node);
  }
}

class _TransactionEntryVisitor extends RecursiveAstVisitor<void> {
  _TransactionEntryVisitor({
    required this.path,
    required this.keys,
    required this.wrapperApis,
    required this.boundary,
    required this.typeByName,
  });

  final String path;
  final List<String> keys;
  final Set<String> wrapperApis;
  final _UnitOfWorkBoundary boundary;
  final Map<String, Set<String>> typeByName;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final api = node.methodName.name;
    if (_primitiveTransactionApis.contains(api)) _add(node, api);
    super.visitMethodInvocation(node);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    final name = node.name;
    if (node.parent is Label) return;
    if (wrapperApis.contains(name)) {
      _add(node, name);
    } else if (boundary.methods.contains(name)) {
      final type = _boundaryReceiverType(node);
      if (type != null) _add(node, '$type.$name');
    }
  }

  String? _boundaryReceiverType(SimpleIdentifier node) {
    final parent = node.parent;
    Expression? target;
    if (parent is MethodInvocation && parent.methodName == node) {
      target = parent.target;
    } else if (parent is PrefixedIdentifier && parent.identifier == node) {
      target = parent.prefix;
    } else if (parent is PropertyAccess && parent.propertyName == node) {
      target = parent.target;
    }
    final String? receiver;
    if (target is SimpleIdentifier) {
      receiver = target.name;
    } else if (target is PrefixedIdentifier) {
      receiver = target.identifier.name;
    } else if (target is PropertyAccess) {
      receiver = target.propertyName.name;
    } else {
      receiver = null;
    }
    for (final type in typeByName[receiver] ?? const <String>{}) {
      if (boundary.types.contains(type)) return type;
    }
    return null;
  }

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    if (node.parent is! AdjacentStrings) _addSavepoints(node, node);
  }

  @override
  void visitStringInterpolation(StringInterpolation node) {
    if (node.parent is! AdjacentStrings) _addSavepoints(node, node);
    super.visitStringInterpolation(node);
  }

  @override
  void visitAdjacentStrings(AdjacentStrings node) {
    _addSavepoints(node, node);
    super.visitAdjacentStrings(node);
  }

  void _addSavepoints(AstNode at, StringLiteral literal) {
    for (final api in _savepointStatements(_stringText(literal))) {
      _add(at, api);
    }
  }

  void _add(AstNode node, String api) =>
      keys.add('$path | ${_enclosingMember(node)} | $api');
}

String _stringText(StringLiteral node) => switch (node) {
  final SimpleStringLiteral n => n.value,
  final AdjacentStrings n => n.strings.map(_stringText).join(),
  final StringInterpolation n =>
    n.elements.map((e) => e is InterpolationString ? e.value : '?').join(),
};

final _rollbackTo = RegExp(
  '^ROLLBACK (WORK |TRANSACTION )?TO ',
  caseSensitive: false,
);
final _releaseSavepoint = RegExp('^RELEASE SAVEPOINT ', caseSensitive: false);
final _openSavepoint = RegExp('^SAVEPOINT ', caseSensitive: false);

/// The savepoint statements ([sql] may hold several, `;`-separated, and may
/// carry leading or interleaved `/* */` and `--` comments).
Iterable<String> _savepointStatements(String sql) sync* {
  final withoutComments = sql
      .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), ' ')
      .replaceAll(RegExp(r'--[^\n]*'), ' ');
  for (final raw in withoutComments.split(';')) {
    final statement = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (_rollbackTo.hasMatch(statement)) {
      yield 'ROLLBACK TO SAVEPOINT';
    } else if (_releaseSavepoint.hasMatch(statement)) {
      yield 'RELEASE SAVEPOINT';
    } else if (_openSavepoint.hasMatch(statement)) {
      yield 'SAVEPOINT';
    }
  }
}

String? _enclosingTypeName(AstNode node) {
  for (AstNode? n = node; n != null; n = n.parent) {
    if (n is ClassDeclaration) return n.namePart.typeName.lexeme;
    if (n is MixinDeclaration) return n.name.lexeme;
    if (n is ExtensionDeclaration) return n.name?.lexeme;
  }
  return null;
}

String _enclosingMember(AstNode node) {
  String? member;
  for (AstNode? n = node; n != null && member == null; n = n.parent) {
    if (n is MethodDeclaration) member = n.name.lexeme;
    if (n is FunctionDeclaration) member = n.name.lexeme;
    if (n is ConstructorDeclaration) member = n.name?.lexeme ?? 'new';
  }
  return [?_enclosingTypeName(node), ?member].join('.');
}

List<String> _classDefinitions(Set<String> names) {
  final declaration = RegExp(
    r'^\s*(?:(?:abstract|base|final|sealed)\s+)*class\s+'
    '(${names.map(RegExp.escape).join('|')})\\b',
    multiLine: true,
  );
  return [
    for (final file in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>())
      if (file.path.endsWith('.dart') && !_isGenerated(file.path))
        for (final match in declaration.allMatches(file.readAsStringSync()))
          '${file.path}: ${match.group(1)}',
  ];
}

bool _isGenerated(String path) => [
  '.g.dart',
  '.freezed.dart',
  '.gr.dart',
  '.config.dart',
  '.schema.dart',
].any(path.endsWith);
