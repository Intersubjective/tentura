// Run explicitly. A cold generator build is too expensive for the client suite.
import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:collection/collection.dart';
import 'package:flutter_test/flutter_test.dart';

const _configPath = 'lib/app/di/di_current.config.dart';
const _buildLimit = Duration(minutes: 4);

void main() {
  test(
    'generated AttentionCase registration uses the operation ID port',
    () async {
      final baseline = await File(_configPath).readAsBytes();
      final scratch = await Directory.systemTemp.createTemp('attention-di-');
      addTearDown(() => scratch.delete(recursive: true));
      final client = await _copyClientWorkspace(scratch);
      final isolatedConfig = File.fromUri(client.uri.resolve(_configPath));
      // Force a fresh output even when a cached asset would otherwise be reused.
      await isolatedConfig.delete();
      await _regenerateConfig(client);

      final registrations = _AttentionRegistrations();
      parseString(content: await isolatedConfig.readAsString()).unit.accept(
        registrations,
      );
      expect(registrations.calls, hasLength(1));
      final factory =
          registrations
                  .calls
                  .single
                  .argumentList
                  .arguments
                  .first
                  .argumentExpression
              as FunctionExpression;
      final body = factory.body as ExpressionFunctionBody;
      // In an unresolved AST, a call to a prefixed constructor can be a
      // method invocation until the analyzer resolves the imported class.
      final arguments = switch (body.expression) {
        MethodInvocation(
          methodName: SimpleIdentifier(name: 'AttentionCase'),
          :final argumentList,
        ) =>
          argumentList,
        InstanceCreationExpression(:final constructorName, :final argumentList)
            when constructorName.type.name.lexeme == 'AttentionCase' =>
          argumentList,
        _ => fail('The generated factory must construct AttentionCase'),
      };
      final portLookups = arguments.arguments
          .map((argument) => argument.argumentExpression)
          .whereType<MethodInvocation>()
          .where(
            (call) =>
                call.target == null &&
                call.methodName.name == 'gh' &&
                _singleTypeArgumentIs(call, 'OpIdPort') &&
                call.argumentList.arguments.isEmpty,
          );
      expect(
        {
          'gh<OpIdPort>() arguments to AttentionCase': portLookups.length,
          'build_runner reproduced $_configPath': const ListEquality<int>()
              .equals(baseline, await isolatedConfig.readAsBytes()),
        },
        {
          'gh<OpIdPort>() arguments to AttentionCase': 1,
          'build_runner reproduced $_configPath': true,
        },
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

bool _singleTypeArgumentIs(MethodInvocation call, String name) =>
    switch (call.typeArguments?.arguments.singleOrNull) {
      NamedType(name: final type) => type.lexeme == name,
      _ => false,
    };

class _AttentionRegistrations extends RecursiveAstVisitor<void> {
  final calls = <MethodInvocation>[];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.target case SimpleIdentifier(name: 'gh')
        when node.methodName.name == 'lazySingleton' &&
            _singleTypeArgumentIs(node, 'AttentionCase')) {
      calls.add(node);
    }
    super.visitMethodInvocation(node);
  }
}

Future<Directory> _copyClientWorkspace(Directory scratch) async {
  final root = Directory.current.parent.parent;
  final packages = Directory.fromUri(root.uri.resolve('packages/'));
  final client = await Directory.fromUri(
    scratch.uri.resolve('packages/client/'),
  ).create(recursive: true);
  // Local dependencies are only read by this single-package build.
  await for (final package in packages.list()) {
    if (package is! Directory || package.uri == Directory.current.uri) continue;
    final name = package.uri.pathSegments.reversed.skip(1).first;
    await Link.fromUri(
      scratch.uri.resolve('packages/$name'),
    ).create(package.path);
  }
  await Link.fromUri(scratch.uri.resolve('lib')).create(
    Directory.fromUri(root.uri.resolve('lib/')).path,
  );
  final copy = await Process.run('cp', [
    '-Rp',
    'lib',
    'pubspec.yaml',
    'build.yaml',
    'analysis_options.yaml',
    client.path,
  ]);
  expect(copy.exitCode, 0, reason: '${copy.stdout}\n${copy.stderr}');

  final tool = await Directory.fromUri(
    scratch.uri.resolve('.dart_tool/'),
  ).create();
  for (final path in [
    'pubspec.yaml',
    'pubspec.lock',
    'pubspec_overrides.yaml',
    'analysis_options.yaml',
    '.dart_tool/package_config.json',
    '.dart_tool/package_graph.json',
  ]) {
    final source = File.fromUri(root.uri.resolve(path));
    if (source.existsSync()) {
      source.copySync(scratch.uri.resolve(path).toFilePath());
    }
  }
  expect(
    File.fromUri(tool.uri.resolve('package_config.json')).existsSync(),
    isTrue,
  );
  return client;
}

Future<void> _regenerateConfig(Directory client) async {
  final process = await Process.start(
    'dart',
    ['run', 'build_runner', 'build', '-d', '--build-filter=$_configPath'],
    workingDirectory: client.path,
  );
  final stdout = process.stdout.transform(utf8.decoder).join();
  final stderr = process.stderr.transform(utf8.decoder).join();
  final exitCode = await process.exitCode.timeout(
    _buildLimit,
    onTimeout: () async {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode;
      fail('DI regeneration exceeded $_buildLimit');
    },
  );
  expect(exitCode, 0, reason: '${await stdout}\n${await stderr}');
}
