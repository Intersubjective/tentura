import 'dart:io';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

const _casePaths = {
  'AuthorInviteCase': 'lib/domain/use_case/author_invite_case.dart',
  'BeaconThreadsCase':
      'lib/features/beacon_threads/domain/use_case/beacon_threads_case.dart',
  'CredentialsCase':
      'lib/features/credentials/domain/use_case/credentials_case.dart',
  'ForwardCase': 'lib/features/forward/domain/use_case/forward_case.dart',
  'FriendsCase': 'lib/features/friends/domain/use_case/friends_case.dart',
  'InboxCase': 'lib/features/inbox/domain/use_case/inbox_case.dart',
  'MyWorkCase': 'lib/features/my_work/domain/use_case/my_work_case.dart',
  'PostsCase': 'lib/features/inbox/domain/use_case/posts_case.dart',
};

const _ambientDependencies = {'env', 'logger'};
const _postBudAndSuggestionCases = {
  'PostBudCase': 'lib/domain/use_case/post_bud_case.dart',
  'PeopleTagSuggestionCase':
      'lib/features/people_tags/domain/use_case/people_tag_suggestion_case.dart',
};
final _ambientNames = RegExp(r'\b(?:env|logger|UseCaseBase)\b');
final _forwardAmbientNames = RegExp(
  r'\b(?:env|logger|Env|Logger|UseCaseBase)\b',
);
final _generatedDart = RegExp(r'\.(?:config|freezed|g|gr|schema)\.dart$');
const _forwardDependencyTypes = [
  'ForwardRepository',
  'AuthLocalRepositoryPort',
  'BeaconFactCardRepository',
  'ProfileRepositoryPort',
  'ContactsCase',
  'BlockCase',
];

void main() {
  _testWiring('Use case wiring only supplies feature dependencies', {
    for (final entry in _casePaths.entries)
      if (entry.key != 'ForwardCase') entry.key: entry.value,
  });
  _testWiring('ForwardCase wiring only supplies feature dependencies', {
    'ForwardCase': _casePaths['ForwardCase']!,
  });
  group('Client use cases depend only on services they use', () {
    _testWiring(
      'Post budding and people tag suggestions only need feature dependencies',
      _postBudAndSuggestionCases,
    );
    test('the shared base serves at least three cases that read its fields', () {
      final subclasses = <String, _AmbientFieldReads>{};
      for (final file in Directory(
        'lib',
      ).listSync(recursive: true, followLinks: false).whereType<File>()) {
        if (!file.path.endsWith('.dart') ||
            _generatedDart.hasMatch(file.path) ||
            file.path.contains('/_g/')) {
          continue;
        }
        final source = file.readAsStringSync();
        if (!source.contains('UseCaseBase')) continue;
        final unit = parseString(content: source, path: file.path).unit;
        for (final declaration
            in unit.declarations.whereType<ClassDeclaration>()) {
          if (declaration.extendsClause?.superclass.name.lexeme !=
              'UseCaseBase') {
            continue;
          }
          final reads = _AmbientFieldReads();
          declaration.body.accept(reads);
          subclasses['${declaration.namePart.typeName.lexeme} (${file.path})'] =
              reads;
        }
      }
      expect(
        subclasses.entries.where((entry) => entry.value.fields.isNotEmpty),
        hasLength(greaterThanOrEqualTo(3)),
      );

      const basePath = 'lib/domain/use_case/use_case_base.dart';
      final base =
          parseString(
            content: File(basePath).readAsStringSync(),
            path: basePath,
          ).unit.declarations.whereType<ClassDeclaration>().singleWhere(
            (node) => node.namePart.typeName.lexeme == 'UseCaseBase',
          );
      expect(base.baseKeyword, isNotNull);
      final body = base.body as BlockClassBody;
      final fields = {
        for (final member in body.members.whereType<FieldDeclaration>())
          for (final field in member.fields.variables)
            field.name.lexeme: member.fields.type?.toSource(),
      };
      expect(fields, containsPair('env', 'Env'));
      expect(fields, containsPair('logger', 'Logger'));
      final requiredFields = body.members
          .whereType<ConstructorDeclaration>()
          .single
          .parameters
          .parameters
          .whereType<FieldFormalParameter>()
          .where((parameter) => parameter.isRequiredNamed)
          .map((parameter) => parameter.name.lexeme);
      expect(requiredFields, containsAll(_ambientDependencies));

      expect(
        subclasses.entries
            .where((entry) => entry.value.fields.isEmpty)
            .map((entry) => entry.key),
        isEmpty,
        reason: 'Each subclass must read env or logger in its own body',
      );
    });
  });
}

class _AmbientFieldReads extends RecursiveAstVisitor<void> {
  final fields = <String>{};

  void _record(String? receiver) {
    if (_ambientDependencies.contains(receiver)) fields.add(receiver!);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    _record(node.target?.toSource());
    super.visitMethodInvocation(node);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    _record(node.prefix.name);
    super.visitPrefixedIdentifier(node);
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    _record(node.target?.toSource());
    super.visitPropertyAccess(node);
  }
}

void _testWiring(String description, Map<String, String> casePaths) {
  group(description, () {
    test('case sources omit the shared base and its unused imports', () {
      final violations = <String>[];
      for (final MapEntry(key: name, value: path) in casePaths.entries) {
        final source = File(path).readAsStringSync();
        final unit = parseString(content: source, path: path).unit;
        for (final directive in unit.directives.whereType<ImportDirective>()) {
          final uri = directive.uri.stringValue!;
          if (uri.endsWith('use_case_base.dart') ||
              uri.endsWith('/env.dart') ||
              uri == 'env.dart' ||
              uri.startsWith('package:logging/')) {
            violations.add('$path imports $uri');
          }
        }
        final declaration = unit.declarations
            .whereType<ClassDeclaration>()
            .singleWhere((node) => node.namePart.typeName.lexeme == name);
        if (const {'ForwardCase', 'MyWorkCase', 'PostsCase'}.contains(name)) {
          if (declaration.finalKeyword == null) {
            violations.add('$path must declare final class $name');
          }
        }
        final ambientPattern = switch (name) {
          'ForwardCase' => _forwardAmbientNames,
          'BeaconThreadsCase' || 'MyWorkCase' || 'PostsCase' => _ambientNames,
          _ => null,
        };
        if (ambientPattern != null) {
          for (final match in ambientPattern.allMatches(source)) {
            final line = unit.lineInfo.getLocation(match.start).lineNumber;
            violations.add('$path:$line mentions ${match.group(0)}');
          }
        }
        if (declaration.extendsClause?.superclass.name.lexeme ==
            'UseCaseBase') {
          violations.add('$path extends UseCaseBase');
        }
        if (declaration.body case BlockClassBody(:final members)) {
          for (final constructor
              in members.whereType<ConstructorDeclaration>()) {
            if (name == 'ForwardCase') {
              if (!_hasForwardConstructorParameters(constructor, members)) {
                violations.add(
                  '$path must take ${_forwardDependencyTypes.join(', ')} in order '
                  'and only the optional @ignoreParam overrides clock and postBudPort',
                );
              }
            }
            for (final parameter in constructor.parameters.parameters) {
              final parameterName = parameter.name?.lexeme;
              if (_ambientDependencies.contains(parameterName) &&
                  (parameter is SuperFormalParameter ||
                      _postBudAndSuggestionCases.containsKey(name))) {
                violations.add('$path declares ${parameter.toSource()}');
              }
            }
          }
        }
      }
      expect(violations, isEmpty);
    });

    test(
      'generated DI factories construct the cases without env or logger',
      () {
        const path = 'lib/app/di/di_current.config.dart';
        final parsed = parseString(
          content: File(path).readAsStringSync(),
          path: path,
        );
        final registrations = _CaseRegistrations(casePaths.keys);
        parsed.unit.accept(registrations);
        expect(registrations.calls.keys, unorderedEquals(casePaths.keys));

        final violations = <String>[];
        for (final entry in registrations.calls.entries) {
          if (entry.key == 'ForwardCase') {
            expect(entry.value, hasLength(1));
          }
          for (final registration in entry.value) {
            final constructors = _ConstructorCalls(casePaths.keys);
            registration.argumentList.accept(constructors);
            final calls = constructors.calls.where(
              (call) => call.name == entry.key,
            );
            expect(calls, isNotEmpty, reason: 'DI must construct ${entry.key}');
            for (final call in calls) {
              violations.addAll(_ambientArguments(path, parsed, call));
              if (call.name == 'BeaconThreadsCase' &&
                  (registration.methodName.name != 'singleton' ||
                      !_hasBeaconThreadsDependencies(call))) {
                violations.add(
                  '$path must register BeaconThreadsCase as a singleton '
                  'with six positional feature dependency lookups',
                );
              }
              if (call.name == 'ForwardCase' &&
                  (registration.methodName.name != 'singleton' ||
                      !_hasOrderedDependencyLookups(
                        call,
                        _forwardDependencyTypes,
                      ))) {
                violations.add(
                  '$path must register ForwardCase as a singleton with its '
                  'six positional feature dependency lookups in order',
                );
              }
              if (call.name == 'PostsCase' &&
                  (registration.methodName.name != 'singleton' ||
                      !_hasPostsFactoryDependencies(call))) {
                violations.add(
                  '$path must register PostsCase as a singleton using '
                  'withBeaconRepository and its three feature lookups',
                );
              }
              if (call.name == 'MyWorkCase') {
                final arguments = call.arguments.arguments;
                if (arguments.length != 12 ||
                    !arguments.every(_isPositionalDependencyLookup)) {
                  violations.add(
                    '$path must supply 12 positional gh<T>() lookups to '
                    'MyWorkCase',
                  );
                }
              }
            }
          }
        }
        expect(violations, isEmpty);
      },
    );

    final checksForward = casePaths.containsKey('ForwardCase');
    final callerDescription = checksForward
        ? 'library and test callers omit ambient arguments and tests reuse builders'
        : 'client test callers and builders omit env and logger';
    test(callerDescription, () {
      final files =
          ['test', if (checksForward) 'lib']
              .expand(
                (root) => Directory(root).listSync(
                  recursive: true,
                  followLinks: false,
                ),
              )
              .whereType<File>()
              .where((file) => file.path.endsWith('.dart'))
              .where(
                (file) =>
                    file.path.startsWith('test/') ||
                    (!_generatedDart.hasMatch(file.path) &&
                        !file.path.contains('/_g/')),
              )
              .toList()
            ..sort((left, right) => left.path.compareTo(right.path));
      final violations = <String>[];
      var myWorkCalls = 0;
      for (final file in files) {
        final source = file.readAsStringSync();
        if (!casePaths.keys.any(source.contains)) continue;
        final parsed = parseString(content: source, path: file.path);
        final constructors = _ConstructorCalls(casePaths.keys);
        parsed.unit.accept(constructors);
        for (final call in constructors.calls) {
          violations.addAll(_ambientArguments(file.path, parsed, call));
        }
        // The constructor argument rule also covers library callers. Builder
        // reuse applies only to test files.
        if (!file.path.startsWith('test/')) continue;

        var beaconThreadsCalls = 0;
        var forwardCalls = 0;
        var postsCalls = 0;
        for (final call in constructors.calls) {
          if (call.name == 'MyWorkCase') myWorkCalls++;
          if (call.name == 'PostsCase') postsCalls++;
          if (call.name == 'BeaconThreadsCase' && !call.isSuper) {
            beaconThreadsCalls++;
          }
          if (call.name == 'ForwardCase' && !call.isSuper) forwardCalls++;
        }
        if (beaconThreadsCalls > 1) {
          violations.add(
            '${file.path} should reuse one BeaconThreadsCase builder',
          );
        }
        if (forwardCalls > 1) {
          violations.add('${file.path} should reuse one ForwardCase builder');
        }
        if (postsCalls > 1) {
          violations.add('$file should reuse one PostsCase builder');
        }
      }
      expect(violations, isEmpty);
      expect(
        myWorkCalls,
        lessThanOrEqualTo(5),
        reason: 'Reuse buildTestMyWorkCase when another test needs MyWorkCase',
      );
    });
  });
}

typedef _ConstructorCall = ({
  String name,
  String? constructorName,
  ArgumentList arguments,
  bool isSuper,
});

bool _hasForwardConstructorParameters(
  ConstructorDeclaration constructor,
  Iterable<ClassMember> members,
) {
  final parameters = constructor.parameters.parameters;
  final positional = parameters
      .where((parameter) => parameter.isPositional)
      .toList();
  final named = parameters.where((parameter) => parameter.isNamed);
  final fieldTypes = {
    for (final member in members.whereType<FieldDeclaration>())
      for (final field in member.fields.variables)
        field.name.lexeme: member.fields.type?.toSource(),
  };
  return positional.length == _forwardDependencyTypes.length &&
      positional.indexed.every((entry) {
        final (index, parameter) = entry;
        final type =
            parameter.type?.toSource() ??
            (parameter is FieldFormalParameter
                ? fieldTypes[parameter.name.lexeme]
                : null);
        return parameter.isRequiredPositional &&
            type == _forwardDependencyTypes[index];
      }) &&
      named.length == 2 &&
      named.map((parameter) => parameter.name?.lexeme).toSet().containsAll({
        'clock',
        'postBudPort',
      }) &&
      named.every(
        (parameter) =>
            parameter.isOptionalNamed &&
            parameter.metadata.any(
              (annotation) => annotation.name.name == 'ignoreParam',
            ),
      );
}

bool _hasBeaconThreadsDependencies(_ConstructorCall call) =>
    _hasOrderedDependencyLookups(call, const [
      'BeaconThreadsRepository',
      'BeaconFactCardRepository',
      'PollingRepository',
      'BeaconRoomHintsRepository',
      'RoomReadWatermarkStore',
      'RealtimeSyncCase',
    ]);

bool _hasOrderedDependencyLookups(_ConstructorCall call, List<String> types) {
  final arguments = call.arguments.arguments;
  return call.constructorName == null &&
      arguments.length == types.length &&
      arguments.indexed.every(
        (entry) => _isPositionalDependencyLookup(entry.$2, types[entry.$1]),
      );
}

bool _hasPostsFactoryDependencies(_ConstructorCall call) {
  if (call.arguments.arguments case [
    final repository,
    final realtime,
    final NamedArgument beacon,
  ]) {
    return call.constructorName == 'withBeaconRepository' &&
        _isPositionalDependencyLookup(repository, 'PostsRepositoryPort') &&
        _isPositionalDependencyLookup(realtime, 'RealtimeSyncCase') &&
        beacon.name.lexeme == 'beaconRepository' &&
        _isDependencyLookup(beacon, 'BeaconRepository');
  }
  return false;
}

bool _isPositionalDependencyLookup(Argument argument, [String? typeName]) =>
    argument is! NamedArgument && _isDependencyLookup(argument, typeName);

bool _isDependencyLookup(Argument argument, String? typeName) {
  final expression = argument.argumentExpression;
  return expression is MethodInvocation &&
      expression.target == null &&
      expression.methodName.name == 'gh' &&
      expression.typeArguments?.arguments.length == 1 &&
      (typeName == null ||
          expression.typeArguments!.arguments.single.endToken.lexeme ==
              typeName) &&
      expression.argumentList.arguments.isEmpty;
}

Iterable<String> _ambientArguments(
  String path,
  ParseStringResult parsed,
  _ConstructorCall call,
) sync* {
  for (final argument in call.arguments.arguments.whereType<NamedArgument>()) {
    final name = argument.name.lexeme;
    if (_ambientDependencies.contains(name)) {
      final line = parsed.lineInfo.getLocation(argument.offset).lineNumber;
      yield '$path:$line passes $name to ${call.name}';
    }
  }
}

class _CaseRegistrations extends RecursiveAstVisitor<void> {
  _CaseRegistrations(this.caseNames);

  final Iterable<String> caseNames;
  final calls = <String, List<MethodInvocation>>{};

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final type = node.typeArguments?.arguments.singleOrNull;
    if (node.target case SimpleIdentifier(
      name: 'gh',
    ) when type is NamedType && caseNames.contains(type.name.lexeme)) {
      (calls[type.name.lexeme] ??= []).add(node);
    }
    super.visitMethodInvocation(node);
  }
}

class _ConstructorCalls extends RecursiveAstVisitor<void> {
  _ConstructorCalls(this.caseNames);

  final Iterable<String> caseNames;
  final calls = <_ConstructorCall>[];

  void _record(
    String name,
    ArgumentList arguments, {
    String? constructorName,
    bool isSuper = false,
  }) {
    if (caseNames.contains(name)) {
      calls.add((
        name: name,
        constructorName: constructorName,
        arguments: arguments,
        isSuper: isSuper,
      ));
    }
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    if (node.body case BlockClassBody(
      :final members,
    ) when node.extendsClause?.superclass.name.lexeme == 'BeaconThreadsCase') {
      for (final constructor in members.whereType<ConstructorDeclaration>()) {
        for (final call
            in constructor.initializers
                .whereType<SuperConstructorInvocation>()) {
          _record('BeaconThreadsCase', call.argumentList, isSuper: true);
        }
      }
    }
    super.visitClassDeclaration(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    _record(
      node.constructorName.type.name.lexeme,
      node.argumentList,
      constructorName: node.constructorName.name?.name,
    );
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    // Implicit constructors can parse as method calls before name resolution.
    final name = node.methodName.name;
    final targetName = node.target?.endToken.lexeme;
    if (targetName == 'ForwardCase') {
      // ForwardCase has only an unnamed constructor. Its other members are
      // static methods, such as computeInvolvement.
      if (name == 'new') _record('ForwardCase', node.argumentList);
    } else if (targetName != null && caseNames.contains(targetName)) {
      _record(targetName, node.argumentList, constructorName: name);
    } else {
      _record(name, node.argumentList);
    }
    super.visitMethodInvocation(node);
  }
}
