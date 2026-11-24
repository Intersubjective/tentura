@TestOn('vm')
library;

import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:flutter_test/flutter_test.dart';

const _feature = 'lib/features/phantoms';
const _port = 'PhantomRepositoryPort';

void main() {
  test('the phantom entity and repository port stay in the domain layer', () {
    final domain = _sources('$_feature/domain');
    expect(_classNames(domain), containsAll(['Phantom', _port]));

    for (final (file, unit) in domain) {
      for (final directive in unit.directives.whereType<UriBasedDirective>()) {
        final rawUri = directive.uri.stringValue;
        if (rawUri == null) continue;
        final uri = file.absolute.uri.resolve(rawUri);
        final isClientFile =
            uri.scheme == 'file' || uri.pathSegments.firstOrNull == 'tentura';
        if (isClientFile) {
          expect(
            uri.pathSegments,
            isNot(anyOf(contains('data'), contains('ui'))),
            reason: '${file.path} must not depend on $rawUri',
          );
        }
      }
    }
  });

  test('Injectable binds the phantom repository port to its data adapter', () {
    final data = _sources('$_feature/data');
    final declarations = [
      for (final (_, unit) in data)
        ...unit.declarations.whereType<ClassDeclaration>().where(
          (node) => node.namePart.typeName.lexeme == 'PhantomRepository',
        ),
    ];
    expect(
      declarations,
      hasLength(1),
      reason: 'The GraphQL adapter must be declared in the data layer',
    );
    final adapter = declarations.single;
    expect(
      adapter.implementsClause?.interfaces.map((type) => type.name.lexeme),
      contains(_port),
    );
    expect(
      adapter.metadata.any(
        (annotation) =>
            const {'Injectable', 'LazySingleton', 'Singleton'}.contains(
              annotation.name.name.split('.').last,
            ) &&
            (annotation.arguments?.arguments.whereType<NamedArgument>().any(
                  (argument) =>
                      argument.name.lexeme == 'as' &&
                      argument.argumentExpression.toSource().split('.').last ==
                          _port,
                ) ??
                false),
      ),
      isTrue,
      reason: 'Injectable must bind PhantomRepository as $_port',
    );
  });
}

List<(File, CompilationUnit)> _sources(String path) {
  final directory = Directory(path);
  if (!directory.existsSync()) return const [];
  return [
    for (final file in directory.listSync(recursive: true).whereType<File>())
      if (file.path.endsWith('.dart') &&
          !file.path.endsWith('.g.dart') &&
          !file.path.endsWith('.gql.dart') &&
          !file.path.endsWith('.freezed.dart') &&
          !file.path.endsWith('.config.dart'))
        (
          file,
          parseString(content: file.readAsStringSync(), path: file.path).unit,
        ),
  ];
}

Iterable<String> _classNames(List<(File, CompilationUnit)> sources) sync* {
  for (final (_, unit) in sources) {
    yield* unit.declarations.whereType<ClassDeclaration>().map(
      (declaration) => declaration.namePart.typeName.lexeme,
    );
  }
}
