// The analyzer is a transitive dependency, as in the other AST guards.
// ignore_for_file: depend_on_referenced_packages
@Tags(['repo-files'])
library;

import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:test/test.dart';
import 'package:tentura_root/consts.dart' as shared;

import '../api/controllers/websocket/websocket_realtime_protocol_test.dart'
    show fanOutPrivateReadCursor;
import '../../../../test/support/shared_revision_pattern_guard.dart';

// Coverage map:
// - Handle ownership and runtime grammar: first test below. Server profile
//   normalization/rejection is also covered by domain/use_case/user_case_test.dart;
//   consts/user_handle_consts_test.dart
//   covers the legacy import if it remains as a re-export.
// - Decimal ownership and real authenticated websocket fan-out: second test.
//   Client decoding (both revision-bearing kinds, malformed hints and BigInt
//   precision) is exercised alongside ownership in client/test/data/service/
//   shared_revision_validation_test.dart; the existing
//   invalidation_service_constellation_revision_test.dart remains unchanged.
// - Analyzer preservation: check-analyze-baseline.sh and check-custom-lints.sh
//   for each package after implementation (not red acceptance tests).
// Sibling matrix: surfaces = auth/update and both realtime consumers;
// role = authenticated recipient; state = both revision-bearing entity kinds;
// freshness = incoming realtime notification. Input, network timing, width,
// locale: n/a, this refactor changes no interaction, timing or presentation.

void main() {
  final root = Directory('../..').absolute.uri;
  final units = <Uri, CompilationUnit>{};

  CompilationUnit read(Uri uri) => units.putIfAbsent(
    uri,
    () => parseString(content: File.fromUri(uri).readAsStringSync()).unit,
  );

  Uri? resolve(Uri source, String? target) {
    if (target == null || target.startsWith('dart:')) return null;
    for (final entry in const {
      'package:tentura_root/': 'lib/',
      'package:tentura_server/': 'packages/server/lib/',
      'package:tentura/': 'packages/client/lib/',
    }.entries) {
      if (target.startsWith(entry.key)) {
        return root.resolve(
          '${entry.value}${target.substring(entry.key.length)}',
        );
      }
    }
    return target.startsWith('package:') ? null : source.resolve(target);
  }

  bool exportsShared(Uri uri, String symbol, Set<Uri> visited) {
    if (!visited.add(uri)) return false;
    if (uri.path.startsWith(root.resolve('lib/').path)) {
      return _declarations(read(uri)).contains(symbol);
    }
    return read(uri).directives.whereType<ExportDirective>().any((directive) {
      if (!_allows(directive.combinators, symbol)) return false;
      final target = resolve(uri, directive.uri.stringValue);
      return target != null && exportsShared(target, symbol, visited);
    });
  }

  bool importsShared(Uri uri, String symbol) =>
      read(uri).directives.whereType<ImportDirective>().any((directive) {
        if (!_allows(directive.combinators, symbol)) return false;
        final target = resolve(uri, directive.uri.stringValue);
        return target != null && exportsShared(target, symbol, <Uri>{});
      });

  final rootSources = _sources(root.resolve('lib/')).toList();
  final packageSources = [
    ..._sources(root.resolve('packages/server/lib/')),
    ..._sources(root.resolve('packages/client/lib/')),
  ];

  group('shared validation patterns', () {
    test('user handle validation has one owner in the root library', () {
      const symbols = {
        'kUserHandleRegExp',
        'isValidUserHandleFormat',
      };
      // Ownership alone must not allow an empty or permissive shared validator.
      for (final handle in ['abc', 'alice_smith', 'user123', 'a' * 30]) {
        expect(shared.isValidUserHandleFormat(handle), isTrue, reason: handle);
        expect(
          shared.kUserHandleRegExp.hasMatch(handle),
          isTrue,
          reason: handle,
        );
      }
      for (final handle in [
        '',
        'ab',
        'a' * 31,
        'Alice',
        'a-b',
        'a b',
        ' абв',
      ]) {
        expect(shared.isValidUserHandleFormat(handle), isFalse, reason: handle);
        expect(
          shared.kUserHandleRegExp.hasMatch(handle),
          isFalse,
          reason: handle,
        );
      }
      final violations = <String>[];
      for (final symbol in symbols) {
        final owners = rootSources.where(
          (uri) => _declarations(read(uri)).contains(symbol),
        );
        if (owners.length != 1) {
          violations.add('$symbol needs exactly one root library definition');
        }
      }
      for (final uri in packageSources) {
        final duplicates = _declarations(read(uri)).intersection(symbols);
        if (duplicates.isNotEmpty) {
          violations.add('${uri.path}: package owns $duplicates');
        }
      }
      for (final path in const [
        'packages/server/lib/domain/use_case/auth_case.dart',
        'packages/server/lib/domain/use_case/user_case.dart',
      ]) {
        final uri = root.resolve(path);
        if (!importsShared(uri, 'isValidUserHandleFormat')) {
          violations.add('$path must import the root handle validator');
        }
        final calls = _Calls();
        read(uri).accept(calls);
        if (!calls.expressions.any(
          (call) => call.contains('isValidUserHandleFormat('),
        )) {
          violations.add('$path must call the shared handle validator');
        }
      }
      expect(violations, isEmpty, reason: violations.join('\n'));
    });

    test(
      'server fan-out validates revisions while both consumers share the root pattern',
      () async {
        // A private alias is a valid shared dependency. A string in documentation
        // or a fixture is not a second regexp definition.
        expect(
          decimalRevisionValidationViolations(r'''
            final _decimalRevision = kDecimalRevisionPattern;
            const example = r'^[0-9]+$';
            bool valid(String value) => _decimalRevision.hasMatch(value);
          '''),
          isEmpty,
        );
        expect(
          decimalRevisionValidationViolations('''
            final _decimalRevision = RegExp(kDecimalRevisionPattern);
            bool valid(String value) => _decimalRevision.hasMatch(value);
          '''),
          isEmpty,
        );
        // Exercise production validation and serialization, not a reconstructed
        // frame: the helper authenticates two sessions and invokes fan-out.
        for (final entity in ['constellation_anchor', 'person_tag']) {
          for (final revision in <Object?>[
            '0',
            '007',
            '9007199254740993',
            '',
            '12abc',
            '-1',
            '+1',
            '1.5',
            ' 7',
            42,
            true,
            null,
          ]) {
            final valid =
                revision is String &&
                const ['0', '007', '9007199254740993'].contains(revision);
            final frames = await fanOutPrivateReadCursor({
              'entity': entity,
              'id': 'Uaaaaaaaaaaaa',
              'event': 'update',
              'actor_user_id': 'Uaaaaaaaaaaaa',
              'user_ids': ['Uaaaaaaaaaaaa'],
              'revision': revision,
            });
            for (final received in [frames.first, frames.second]) {
              expect(
                received,
                hasLength(valid ? 1 : 0),
                reason: '$entity revision $revision',
              );
              if (valid) {
                expect(received.single['path'], 'entity_changes');
                expect(
                  received.single['payload'],
                  allOf(
                    containsPair('entity', entity),
                    containsPair('revision', revision),
                  ),
                );
              }
            }
          }
        }
        const symbol = 'kDecimalRevisionPattern';
        final violations = <String>[];
        final owners = rootSources.where(
          (uri) => _declarations(read(uri)).contains(symbol),
        );
        if (owners.length != 1) {
          violations.add('$symbol needs exactly one root library definition');
        }
        for (final uri in packageSources) {
          if (_declarations(read(uri)).contains(symbol)) {
            violations.add('${uri.path}: package defines $symbol');
          }
        }
        for (final path in const [
          'packages/client/lib/data/service/invalidation_service.dart',
          'packages/server/lib/api/controllers/websocket/path_handler/websocket_path_entity_changes.dart',
        ]) {
          final uri = root.resolve(path);
          if (!importsShared(uri, symbol)) {
            violations.add('$path must import the root decimal pattern');
          }
          violations.addAll(
            decimalRevisionValidationViolations(
              File.fromUri(uri).readAsStringSync(),
            ).map((violation) => '$path: $violation'),
          );
        }
        expect(violations, isEmpty, reason: violations.join('\n'));
      },
    );
  });
}

Iterable<Uri> _sources(Uri directory) => Directory.fromUri(directory)
    .listSync(recursive: true)
    .whereType<File>()
    .where((file) => file.path.endsWith('.dart'))
    .where(
      (file) => !RegExp(
        r'\.(g|freezed|gr|config|schema)\.dart$',
      ).hasMatch(file.path),
    )
    .map((file) => file.uri);

Set<String> _declarations(CompilationUnit unit) {
  final visitor = _Declarations();
  unit.accept(visitor);
  return visitor.names;
}

bool _allows(NodeList<Combinator> combinators, String symbol) =>
    combinators.every((combinator) {
      if (combinator is ShowCombinator) {
        return combinator.shownNames.any((name) => name.name == symbol);
      }
      if (combinator is HideCombinator) {
        return !combinator.hiddenNames.any((name) => name.name == symbol);
      }
      return true;
    });

class _Declarations extends RecursiveAstVisitor<void> {
  final names = <String>{};

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    names.add(node.name.lexeme);
    super.visitVariableDeclaration(node);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    names.add(node.name.lexeme);
    super.visitFunctionDeclaration(node);
  }
}

class _Calls extends RecursiveAstVisitor<void> {
  final expressions = <String>[];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    expressions.add(node.toSource());
    super.visitMethodInvocation(node);
  }

  // parseString currently represents bare top-level calls as MethodInvocation;
  // also accept calls represented as function-expression invocations.
  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) {
    expressions.add(node.toSource());
    super.visitFunctionExpressionInvocation(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    expressions.add(node.toSource());
    super.visitInstanceCreationExpression(node);
  }
}
