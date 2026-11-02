import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('database assets follow the running web build', () {
    for (final asset in ['sqlite3.wasm', 'drift_worker.js']) {
      test('$asset resolves through the running engine and document base', () {
        final parsed = parseString(
          content: File(
            'lib/data/database/open_local_database_web.dart',
          ).readAsStringSync(),
        );
        expect(parsed.errors, isEmpty);
        final visitor = _DatabaseAssetReferences();
        parsed.unit.accept(visitor);
        expect(visitor.probes, hasLength(1));
        final argumentName = asset == 'sqlite3.wasm'
            ? 'sqlite3Uri'
            : 'driftWorkerUri';
        final argument = visitor.probes.single.argumentList.arguments
            .whereType<NamedArgument>()
            .singleWhere(
              (argument) => argument.name.lexeme == argumentName,
            );

        // Inspect the expression actually passed to Drift, so an unused
        // assetManager call elsewhere cannot satisfy the contract. This
        // source guard pins the resolution specified for the web opener;
        // the Playwright test also observes its resulting network requests.
        final resolve = argument.argumentExpression;
        expect(resolve, isA<MethodInvocation>());
        final resolveCall = resolve as MethodInvocation;
        expect(
          resolveCall.methodName.name,
          'resolve',
          reason: '$argumentName must resolve the engine URL against baseURI',
        );
        expect(resolveCall.argumentList.arguments, hasLength(1));
        final base = resolveCall.target;
        expect(base, isA<MethodInvocation>());
        final parseBase = base! as MethodInvocation;
        expect(parseBase.target?.toSource(), 'Uri');
        expect(parseBase.methodName.name, 'parse');
        expect(
          parseBase.argumentList.arguments.map(
            (argument) => argument.argumentExpression.toSource(),
          ),
          ['web.document.baseURI'],
        );
        final engine =
            resolveCall.argumentList.arguments.single.argumentExpression;
        expect(engine, isA<MethodInvocation>());
        final engineCall = engine as MethodInvocation;
        expect(engineCall.target?.toSource(), 'ui_web.assetManager');
        expect(engineCall.methodName.name, 'getAssetUrl');
        expect(engineCall.argumentList.arguments, hasLength(1));
        final key = engineCall.argumentList.arguments.single.argumentExpression;
        expect(key, isA<SimpleStringLiteral>());
        expect((key as SimpleStringLiteral).value, 'packages/$asset');

        final imports = parsed.unit.directives.whereType<ImportDirective>();
        expect(
          imports.any(
            (directive) =>
                directive.uri.stringValue == 'dart:ui_web' &&
                directive.prefix?.name == 'ui_web',
          ),
          isTrue,
        );
        expect(
          visitor.identifiers,
          isNot(contains('getWebAppVersion')),
          reason: 'The latest root version is not the running build asset base',
        );
      });

      test('$asset has no root asset URL in client sources', () {
        final sources = Directory('lib')
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'));
        final offenders = <String>[];
        for (final file in sources) {
          final lines = file.readAsLinesSync();
          for (var i = 0; i < lines.length; i++) {
            if (lines[i].contains('/assets/packages/$asset')) {
              offenders.add('${file.path}:${i + 1}: ${lines[i].trim()}');
            }
          }
        }
        expect(
          offenders,
          isEmpty,
          reason:
              '$asset must resolve through the running engine asset base; '
              'root URLs can load a different deployment: $offenders',
        );
      });
    }
  });
}

class _DatabaseAssetReferences extends RecursiveAstVisitor<void> {
  final probes = <MethodInvocation>[];
  final identifiers = <String>{};

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.target?.toSource() == 'WasmDatabase' &&
        node.methodName.name == 'probe') {
      probes.add(node);
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    identifiers.add(node.name);
    super.visitSimpleIdentifier(node);
  }
}
