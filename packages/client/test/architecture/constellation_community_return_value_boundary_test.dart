@Tags(['repo-files'])
library;

import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:test/test.dart';

const _layoutPath =
    'packages/client/lib/features/constellation/domain/layout/'
    'constellation_communities.dart';
final _communityName = RegExp('communit(y|ies)', caseSensitive: false);

Directory _repoRoot() {
  var directory = Directory.current.absolute;
  while (!File('${directory.path}/compose.prod.yaml').existsSync()) {
    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError('Tentura repository root not found');
    }
    directory = parent;
  }
  return directory;
}

CompilationUnit _parse(String source) {
  final result = parseString(content: source);
  expect(result.errors, isEmpty, reason: 'Boundary checks require valid Dart');
  return result.unit;
}

// Identifiers cover fields, Freezed factory parameters, getters, return types,
// repository methods and API resolver names. Wire keys and SQL identifiers
// cover untyped maps and raw SQL as well; prose and comments are not API data.
class _CommunityExposure extends RecursiveAstVisitor<void> {
  final violations = <String>{};

  @override
  void visitCompilationUnit(CompilationUnit node) {
    // Declaration names are tokens rather than SimpleIdentifier nodes in the
    // analyzer AST. Walk tokens so factory parameters and field names count.
    for (var token = node.beginToken; !token.isEof; token = token.next!) {
      if (token.type == TokenType.IDENTIFIER &&
          _communityName.hasMatch(token.lexeme)) {
        violations.add(token.lexeme);
      }
    }
    super.visitCompilationUnit(node);
  }

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    final value = node.value;
    final isWireName = RegExp(r'^\w+$').hasMatch(value);
    final isSql = RegExp(
      r'\b(CREATE|ALTER|INSERT|UPDATE|SELECT)\b',
      caseSensitive: false,
    ).hasMatch(value);
    if ((isWireName || isSql) && _communityName.hasMatch(value)) {
      violations.add(value);
    }
    super.visitSimpleStringLiteral(node);
  }
}

class _RetainedState extends RecursiveAstVisitor<void> {
  final violations = <String>[];

  @override
  void visitTopLevelVariableDeclaration(TopLevelVariableDeclaration node) {
    if (!node.variables.isConst) violations.add(node.toSource());
    super.visitTopLevelVariableDeclaration(node);
  }

  @override
  void visitFieldDeclaration(FieldDeclaration node) {
    // Instance fields on a returned layout are allowed. Static caches expose
    // state outside the return value, including final maps that can be mutated.
    if (node.isStatic && !node.fields.isConst) violations.add(node.toSource());
    super.visitFieldDeclaration(node);
  }
}

List<String> _retainedState(CompilationUnit unit) {
  final visitor = _RetainedState();
  unit.accept(visitor);
  return visitor.violations;
}

Iterable<File> _boundarySources(Directory root) sync* {
  for (final path in ['lib', 'packages/client/lib', 'packages/server/lib']) {
    for (final file in Directory(
      '${root.path}/$path',
    ).listSync(recursive: true, followLinks: false).whereType<File>()) {
      if (!file.path.endsWith('.dart') ||
          RegExp(
            r'\.(g|freezed|gr|config|schema|mocks)\.dart$',
          ).hasMatch(file.path)) {
        continue;
      }
      yield file;
    }
  }
}

// Public types the computation file declares: its returned layout and any
// record/typedef it hands back. Using one outside the overview layout helpers
// exposes the result regardless of the field or key name it travels under.
Set<String> _declaredTypes(String source) => {
  for (final match in RegExp(
    r'^(?:(?:abstract|base|final|interface|sealed|mixin)\s+)*'
    r'(?:class|typedef|enum|mixin|extension\s+type)\s+([A-Za-z]\w*)',
    multiLine: true,
  ).allMatches(source))
    match.group(1)!,
};

bool _isEntityOrStorage(String path) =>
    RegExp('/domain/entity/|/data/').hasMatch(path);

void main() {
  final root = _repoRoot();
  final layout = File('${root.path}/$_layoutPath');

  group('Overview communities remain function return values', () {
    test(
      'entities, persistence ports and wire APIs expose no community data',
      () {
        final violations = <String>[];
        final resultTypes = layout.existsSync()
            ? _declaredTypes(layout.readAsStringSync())
            : <String>{};
        // Entities and storage/wire models, by declaration rather than name:
        // constructing one from the returned data is an exposure anywhere.
        final entityTypes = <String>{
          for (final file in _boundarySources(root))
            if (file.path != layout.path && _isEntityOrStorage(file.path))
              ..._declaredTypes(file.readAsStringSync()),
        };
        for (final file in _boundarySources(root)) {
          // Overview layout helpers may exchange the returned geometry. Every
          // other domain path, including use cases and feature-level domain
          // files, is checked alongside persistence and wire boundaries.
          if (file.path == layout.path) continue;
          final unit = _parse(file.readAsStringSync());
          final isBoundary =
              !file.path.contains('/domain/layout/') &&
              RegExp('/(domain|data|api)/').hasMatch(file.path);
          if (isBoundary) {
            final visitor = _CommunityExposure();
            unit.accept(visitor);
            violations.addAll(
              visitor.violations.map((name) => '${file.path}: $name'),
            );
          }
          violations.addAll(
            _returnedDataLeaks(
              unit,
              isBoundary: isBoundary,
              resultTypes: resultTypes,
              entityTypes: entityTypes,
            ).map((leak) => '${file.path}: $leak'),
          );
        }
        expect(violations, isEmpty);
      },
    );

    test(
      'the computation and its helpers retain no state and depend only on pure libraries',
      () {
        // An absent computation has no dependency or state leak. Its missing
        // outputs are exercised by the behavioral tests, not this invariant.
        if (!layout.existsSync()) return;
        final pending = [layout.uri];
        final visited = <Uri>{};
        while (pending.isNotEmpty) {
          final uri = pending.removeLast();
          if (!visited.add(uri)) continue;
          final unit = _parse(File.fromUri(uri).readAsStringSync());
          expect(
            _retainedState(unit),
            isEmpty,
            reason: '$uri retains layout state',
          );

          for (final directive in unit.directives) {
            if (directive is! UriBasedDirective) continue;
            final references = [
              directive.uri.stringValue!,
              if (directive is ImportDirective)
                for (final config in directive.configurations)
                  config.uri.stringValue!,
              if (directive is ExportDirective)
                for (final config in directive.configurations)
                  config.uri.stringValue!,
            ];
            for (final reference in references) {
              if (reference.startsWith('dart:')) {
                expect(
                  reference,
                  isIn([
                    'dart:core',
                    'dart:math',
                    'dart:collection',
                    'dart:typed_data',
                  ]),
                  reason:
                      '$uri must not access IO, platform APIs or global services',
                );
              } else if (reference.startsWith('package:')) {
                if (reference.startsWith('package:tentura/') ||
                    reference.startsWith('package:tentura_root/')) {
                  final client = reference.startsWith('package:tentura/');
                  final relative = reference.substring(
                    reference.indexOf('/') + 1,
                  );
                  expect(
                    relative,
                    contains('domain/'),
                    reason: '$uri -> $reference',
                  );
                  pending.add(
                    root.uri.resolve(
                      '${client ? 'packages/client/' : ''}lib/$relative',
                    ),
                  );
                } else {
                  expect(
                    reference,
                    anyOf(
                      startsWith('package:meta/'),
                      startsWith('package:collection/'),
                    ),
                    reason:
                        '$uri must not reach storage or a service locator through $reference',
                  );
                }
              } else {
                pending.add(uri.resolve(reference));
              }
            }
          }
        }
      },
    );

    test(
      'boundary checks detect entity fields, persistence APIs, wire keys and retained caches',
      () {
        for (final source in [
          'class Person { final String communityId; Person(this.communityId); }',
          'abstract class Store { void saveCommunities(Map<String, Object> value); }',
          "Map<String, Object> encode() => {'communities': {}};",
          "const sql = 'CREATE TABLE overview_community (id text)';",
        ]) {
          final visitor = _CommunityExposure();
          _parse(source).accept(visitor);
          expect(visitor.violations, isNotEmpty, reason: source);
        }
        for (final source in [
          'final lastLayout = <String, Object>{};',
          'class Layout { static final cache = <String, Object>{}; }',
        ]) {
          expect(_retainedState(_parse(source)), isNotEmpty, reason: source);
        }
        expect(
          _retainedState(
            _parse(
              'class Layout { final Object communities; Layout(this.communities); }',
            ),
          ),
          isEmpty,
          reason: 'Community data is allowed on the returned layout itself',
        );
      },
    );

    test(
      'returned data cannot escape through renamed entity fields, storage arguments or wire keys',
      () {
        for (final source in [
          '''
class Person {
  Object? groupId;
  void update() {
    final result = computeConstellationCommunities();
    final renamed = result.communities;
    groupId = renamed;
  }
}
''',
          '''
void update() {
  final result = computeConstellationCommunities();
  final renamed = Map.of(result.communities);
  final layoutData = jsonEncode(renamed);
  store.save('layoutData', layoutData);
}
''',
          '''
Map<String, Object> response() {
  final result = computeConstellationCommunities();
  final groupId = result.communities;
  return {'layoutData': groupId};
}
''',
          '''
void update() {
  final result = computeConstellationCommunities();
  final groupId = result.communities;
  final person = Person(groupId: groupId);
}
''',
        ]) {
          expect(
            _returnedDataLeaks(_parse(source), isBoundary: true),
            isNotEmpty,
            reason: source,
          );
        }
        expect(
          _returnedDataLeaks(
            _parse('''
void draw() {
  final result = computeConstellationCommunities();
  final layoutData = result.communities;
  final person = Person(groupId: layoutData);
}
'''),
            isBoundary: false,
            entityTypes: {'Person'},
          ),
          isNotEmpty,
          reason:
              'An entity constructor in UI code is still an exposure boundary',
        );
        expect(
          _returnedDataLeaks(
            _parse('''
Map<String, Object> overview() {
  final result = computeConstellationCommunities();
  return result.positions;
}
'''),
            isBoundary: true,
          ),
          isEmpty,
          reason: 'Ordinary placement geometry is not community membership',
        );
      },
    );

    test(
      'the returned layout type cannot cross entity, persistence or wire boundaries under any name',
      () {
        const layoutSource = '''
class OverviewLayout {
  const OverviewLayout(this.positions, this.groups);
  final Map<String, Object> positions;
  final Map<String, Set<String>> groups;
}
typedef OverviewGroups = Map<String, Set<String>>;
class _Scratch {}
OverviewLayout computeConstellationCommunities() => throw 0;
''';
        final resultTypes = _declaredTypes(layoutSource);
        expect(resultTypes, {'OverviewLayout', 'OverviewGroups'});

        for (final source in [
          // Entity field typed with the returned layout.
          '''
class Person {
  const Person(this.layoutData);
  final OverviewLayout? layoutData;
}
''',
          // Persistence port accepting the returned shape.
          '''
abstract class LayoutStore {
  Future<void> put(String key, OverviewGroups value);
}
''',
          // Wire/API mapping returning the shape under a generic key.
          '''
Map<String, Object?> toJson(OverviewLayout layout) => {'layoutData': layout.groups};
''',
        ]) {
          expect(
            _returnedDataLeaks(
              _parse(source),
              isBoundary: true,
              resultTypes: resultTypes,
            ),
            isNotEmpty,
            reason: source,
          );
        }

        for (final source in [
          // A UI helper holding the result writes it to storage.
          '''
void remember(OverviewLayout layout, Store store) {
  store.save(jsonEncode(layout.groups));
}
''',
          // A UI helper builds an entity from it.
          '''
Object tag(OverviewLayout layout) => Person(groupId: layout.groups);
''',
        ]) {
          expect(
            _returnedDataLeaks(
              _parse(source),
              isBoundary: false,
              resultTypes: resultTypes,
              entityTypes: {'Person'},
            ),
            isNotEmpty,
            reason: source,
          );
        }

        expect(
          _returnedDataLeaks(
            _parse('''
Object paint(OverviewLayout layout, Canvas canvas) {
  canvas.drawPoints(layout.positions);
  return OverviewScene(layout);
}
'''),
            isBoundary: false,
            resultTypes: resultTypes,
            entityTypes: {'Person'},
          ),
          isEmpty,
          reason:
              'Presentation code may consume the return value without exposing it',
        );
      },
    );
  });
}

// Follow the computation's value, not the spelling of a field or storage key.
// Aliases and expressions derived from the result stay marked through map
// copies, projections and encoders. Positions alone are ordinary geometry.
class _ReturnedDataFlow extends RecursiveAstVisitor<void> {
  _ReturnedDataFlow({
    required this.isBoundary,
    required this.resultTypes,
    required this.entityTypes,
  });
  final bool isBoundary;
  final Set<String> resultTypes;
  final Set<String> entityTypes;
  final aliases = <String>{};
  final retainedNames = <String>{};
  final violations = <String>{};

  bool carriesResult(AstNode? node) {
    if (node == null) return false;
    if (node is PrefixedIdentifier && node.identifier.name == 'positions') {
      return false;
    }
    if (node is PropertyAccess && node.propertyName.name == 'positions') {
      return false;
    }
    if (node is SimpleIdentifier &&
        (aliases.contains(node.name) ||
            node.name == 'computeConstellationCommunities')) {
      return true;
    }
    if (node is MethodInvocation &&
        (node.methodName.name == 'computeConstellationCommunities' ||
            aliases.contains(node.methodName.name))) {
      return true;
    }
    return node.childEntities.whereType<AstNode>().any(carriesResult);
  }

  bool mentionsResultType(AstNode? type) {
    if (type == null) return false;
    if (type is NamedType && resultTypes.contains(type.name.lexeme)) {
      return true;
    }
    return type.childEntities.whereType<AstNode>().any(mentionsResultType);
  }

  @override
  void visitNamedType(NamedType node) {
    // Any entity field, port signature or API mapping typed with the result.
    if (isBoundary && resultTypes.contains(node.name.lexeme)) {
      violations.add('${node.name.lexeme} in ${node.parent?.toSource()}');
    }
    super.visitNamedType(node);
  }

  @override
  void visitFormalParameterList(FormalParameterList node) {
    for (final parameter in node.parameters) {
      if (parameter.name != null && mentionsResultType(parameter)) {
        aliases.add(parameter.name!.lexeme);
      }
    }
    super.visitFormalParameterList(node);
  }

  @override
  void visitVariableDeclarationList(VariableDeclarationList node) {
    if (mentionsResultType(node.type)) {
      aliases.addAll(node.variables.map((v) => v.name.lexeme));
    }
    super.visitVariableDeclarationList(node);
  }

  @override
  void visitFieldDeclaration(FieldDeclaration node) {
    retainedNames.addAll(node.fields.variables.map((v) => v.name.lexeme));
    for (final variable in node.fields.variables) {
      if (isBoundary && carriesResult(variable.initializer)) {
        violations.add(node.toSource());
      }
    }
    super.visitFieldDeclaration(node);
  }

  @override
  void visitTopLevelVariableDeclaration(TopLevelVariableDeclaration node) {
    retainedNames.addAll(node.variables.variables.map((v) => v.name.lexeme));
    for (final variable in node.variables.variables) {
      if (carriesResult(variable.initializer)) violations.add(node.toSource());
    }
    super.visitTopLevelVariableDeclaration(node);
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    if (carriesResult(node.initializer)) aliases.add(node.name.lexeme);
    super.visitVariableDeclaration(node);
  }

  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    if (carriesResult(node.rightHandSide)) {
      final target = node.leftHandSide;
      if (target is SimpleIdentifier &&
          (!isBoundary || !retainedNames.contains(target.name))) {
        aliases.add(target.name);
      } else {
        violations.add(node.toSource());
      }
    }
    super.visitAssignmentExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final receivesResult = node.argumentList.arguments.any(carriesResult);
    final writesData = RegExp(
      r'^(write\w*|save\w*|set(String|Int|Double|Bool|StringList|Item|Value)?|insert\w*|upsert\w*|persist\w*|send\w*|post\w*|put\w*|(json)?encode\w*)$',
      caseSensitive: false,
    ).hasMatch(node.methodName.name);
    final constructsValue =
        node.target == null && entityTypes.contains(node.methodName.name);
    if (receivesResult &&
        (isBoundary || writesData || constructsValue) &&
        node.methodName.name != 'computeConstellationCommunities') {
      violations.add(node.toSource());
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final type = node.constructorName.type.name.lexeme;
    if ((isBoundary || entityTypes.contains(type)) &&
        node.argumentList.arguments.any(carriesResult)) {
      violations.add(node.toSource());
    }
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitReturnStatement(ReturnStatement node) {
    if (isBoundary && carriesResult(node.expression)) {
      violations.add(node.toSource());
    }
    super.visitReturnStatement(node);
  }
}

Set<String> _returnedDataLeaks(
  CompilationUnit unit, {
  required bool isBoundary,
  Set<String> resultTypes = const {},
  Set<String> entityTypes = const {},
}) {
  final flow = _ReturnedDataFlow(
    isBoundary: isBoundary,
    resultTypes: resultTypes,
    entityTypes: entityTypes,
  );
  var oldCount = -1;
  while (oldCount != flow.aliases.length) {
    oldCount = flow.aliases.length;
    unit.accept(flow);
  }
  return flow.violations;
}
