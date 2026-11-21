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
  'FriendsCase': 'lib/features/friends/domain/use_case/friends_case.dart',
  'InboxCase': 'lib/features/inbox/domain/use_case/inbox_case.dart',
  'MyWorkCase': 'lib/features/my_work/domain/use_case/my_work_case.dart',
  'PostsCase': 'lib/features/inbox/domain/use_case/posts_case.dart',
};

const _ambientDependencies = {'env', 'logger'};
final _ambientNames = RegExp(r'\b(?:env|logger|UseCaseBase)\b');

void main() {
  group('Use case wiring only supplies feature dependencies', () {
    test('case sources omit the shared base and its unused imports', () {
      final violations = <String>[];
      for (final MapEntry(key: name, value: path) in _casePaths.entries) {
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
        if (name == 'MyWorkCase' || name == 'PostsCase') {
          if (declaration.finalKeyword == null) {
            violations.add('$path must declare final class $name');
          }
        }
        if (const {
          'BeaconThreadsCase',
          'MyWorkCase',
          'PostsCase',
        }.contains(name)) {
          for (final match in _ambientNames.allMatches(source)) {
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
            for (final parameter
                in constructor.parameters.parameters
                    .whereType<SuperFormalParameter>()) {
              if (_ambientDependencies.contains(parameter.name.lexeme)) {
                violations.add('$path declares super.${parameter.name.lexeme}');
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
        final registrations = _CaseRegistrations();
        parsed.unit.accept(registrations);
        expect(registrations.calls.keys, unorderedEquals(_casePaths.keys));

        final violations = <String>[];
        for (final entry in registrations.calls.entries) {
          for (final registration in entry.value) {
            final constructors = _ConstructorCalls();
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

    test('client test callers and builders omit env and logger', () {
      final files =
          Directory('test')
              .listSync(recursive: true, followLinks: false)
              .whereType<File>()
              .where((file) => file.path.endsWith('.dart'))
              .toList()
            ..sort((left, right) => left.path.compareTo(right.path));
      final violations = <String>[];
      var myWorkCalls = 0;
      for (final file in files) {
        final source = file.readAsStringSync();
        if (!_casePaths.keys.any(source.contains)) continue;
        final parsed = parseString(content: source, path: file.path);
        final constructors = _ConstructorCalls();
        parsed.unit.accept(constructors);
        var beaconThreadsCalls = 0;
        var postsCalls = 0;
        for (final call in constructors.calls) {
          if (call.name == 'MyWorkCase') myWorkCalls++;
          if (call.name == 'PostsCase') postsCalls++;
          if (call.name == 'BeaconThreadsCase' && !call.isSuper) {
            beaconThreadsCalls++;
          }
          violations.addAll(_ambientArguments(file.path, parsed, call));
        }
        if (beaconThreadsCalls > 1) {
          violations.add(
            '${file.path} should reuse one BeaconThreadsCase builder',
          );
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

bool _hasBeaconThreadsDependencies(_ConstructorCall call) {
  final arguments = call.arguments.arguments;
  const types = [
    'BeaconThreadsRepository',
    'BeaconFactCardRepository',
    'PollingRepository',
    'BeaconRoomHintsRepository',
    'RoomReadWatermarkStore',
    'RealtimeSyncCase',
  ];
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
  final calls = <String, List<MethodInvocation>>{};

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final type = node.typeArguments?.arguments.singleOrNull;
    if (node.target case SimpleIdentifier(
      name: 'gh',
    ) when type is NamedType && _casePaths.containsKey(type.name.lexeme)) {
      (calls[type.name.lexeme] ??= []).add(node);
    }
    super.visitMethodInvocation(node);
  }
}

class _ConstructorCalls extends RecursiveAstVisitor<void> {
  final calls = <_ConstructorCall>[];

  void _record(
    String name,
    ArgumentList arguments, {
    String? constructorName,
    bool isSuper = false,
  }) {
    if (_casePaths.containsKey(name)) {
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
    if (targetName != null && _casePaths.containsKey(targetName)) {
      _record(targetName, node.argumentList, constructorName: name);
    } else {
      _record(name, node.argumentList);
    }
    super.visitMethodInvocation(node);
  }
}
