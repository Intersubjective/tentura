@Tags(['repo-files'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:flutter_test/flutter_test.dart';

import 'beacon_create_case_call_sites.dart';

const _factoryName = beaconCreateFactory;
const _legacyName = beaconCreateLegacyHelper;
const _fakePortsPath = 'test/features/beacon_create/fake_beacon_ports.dart';
const _opIdServicePath = 'lib/data/service/op_id_service.dart';
const _createCasePath = 'lib/domain/use_case/beacon_create_case.dart';
const _browserAppPath =
    'integration_test/support/post_draft_reload_browser_app.dart';
const _originalCallSites =
    'test/support/beacon_create_case_original_call_sites.json';

Iterable<File> _testSources() => Directory('test')
    .listSync(recursive: true, followLinks: false)
    .whereType<File>()
    .where((file) => file.path.endsWith('.dart'));

Iterable<FunctionDeclaration> _functions(File file, String name) {
  final source = file.readAsStringSync();
  if (!source.contains(name)) return const [];
  return parseString(content: source, path: file.path).unit.declarations
      .whereType<FunctionDeclaration>()
      .where((function) => function.name.lexeme == name);
}

final _constructorSpelling = RegExp(r'\bBeaconCreateCase\(');

Iterable<({File file, FunctionDeclaration function})> _declarations(
  String name,
) sync* {
  for (final file in _testSources()) {
    for (final function in _functions(file, name)) {
      yield (file: file, function: function);
    }
  }
}

File _factoryFile() {
  final declarations = _declarations(_factoryName).toList();
  expect(
    declarations.map((declaration) => declaration.file.path),
    hasLength(1),
    reason: 'Client tests need one top-level $_factoryName function',
  );
  final file = declarations.single.file;
  expect(file.path, startsWith('test/support/'));
  return file;
}

Future<ResolvedUnitResult> _resolve(String path) async {
  final absolutePath = File(path).absolute.path;
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  final contexts = AnalysisContextCollection(
    includedPaths: [absolutePath],
    sdkPath: flutterRoot == null ? null : '$flutterRoot/bin/cache/dart-sdk',
  );
  addTearDown(contexts.dispose);
  final resolved = await contexts
      .contextFor(absolutePath)
      .currentSession
      .getResolvedUnit(absolutePath);
  expect(resolved, isA<ResolvedUnitResult>(), reason: 'Resolve $path');
  return resolved as ResolvedUnitResult;
}

bool _isUuidPackage(String? uri) => uri?.startsWith('package:uuid/') ?? false;

void main() {
  test('one shared factory accepts optional write, image and ID ports', () {
    final factory = _functions(_factoryFile(), _factoryName).single;
    expect(factory.returnType?.toSource(), 'BeaconCreateCase');
    final parameters = factory.functionExpression.parameters!.parameters;
    expect(parameters.every((parameter) => parameter.isOptionalNamed), isTrue);
    expect(
      {
        for (final parameter in parameters)
          parameter.name?.lexeme: parameter.type?.toSource(),
      },
      {
        'beacons': 'BeaconWritePort?',
        'images': 'BeaconImagePort?',
        'opIds': 'OpIdPort?',
      },
    );
    expect(parameters, hasLength(3));
  });

  test(
    'omitted ports get fresh fakes and an ID service for each case',
    () async {
      final resolved = await _resolve(_factoryFile().path);
      final factory = resolved.unit.declarations
          .whereType<FunctionDeclaration>()
          .singleWhere((function) => function.name.lexeme == _factoryName);
      final body = _FactoryBody();
      factory.functionExpression.body.accept(body);
      expect(body.caseConstructors, hasLength(1));
      final construction = body.caseConstructors.single;
      final parameters = construction.constructorName.element!.formalParameters;
      expect(
        parameters.every((parameter) => parameter.isRequiredPositional),
        isTrue,
      );
      expect(
        parameters.map((parameter) => parameter.type.getDisplayString()),
        ['BeaconWritePort', 'BeaconImagePort', 'OpIdPort'],
      );
      final arguments = construction.argumentList.arguments;
      expect(arguments, hasLength(3));
      // Default collaborators are private. Inspect the actual fallback argument
      // so a shared image fake fails even if each fetch returns a fresh buffer.
      body
        ..expectFreshFallback(arguments[0], 'beacons', 'FakeBeaconWritePort')
        ..expectFreshFallback(arguments[1], 'images', 'FakeBeaconImagePort')
        ..expectFreshFallback(
          arguments[2],
          'opIds',
          'OpIdService',
          sourcePath: _opIdServicePath,
        );
    },
  );

  test('BeaconCreateCase has no UUID import or field fallback', () async {
    final resolved = await _resolve(_createCasePath);
    final createCase = resolved.libraryElement.getClass(
      beaconCreateConstructor,
    )!;
    final uuidImports = [
      for (final directive
          in resolved.unit.directives.whereType<ImportDirective>())
        for (final uri in [
          directive.uri.stringValue,
          for (final configuration in directive.configurations)
            configuration.uri.stringValue,
        ])
          if (_isUuidPackage(uri)) uri,
    ];
    final uuidFields = [
      for (final field in createCase.fields)
        if (field.type case InterfaceType(
          :final element,
        ) when _isUuidPackage(element.library.uri.toString()))
          field.name,
    ];

    expect(
      {'UUID imports': uuidImports, 'UUID fields': uuidFields},
      {'UUID imports': isEmpty, 'UUID fields': isEmpty},
    );
  });

  test(
    'picked images and cropped covers get their keys from the port',
    () async {
      final resolved = await _resolve(_createCasePath);
      final createCase = resolved.unit.declarations
          .whereType<ClassDeclaration>()
          .singleWhere(
            (declaration) =>
                declaration.declaredFragment?.element.name ==
                beaconCreateConstructor,
          );
      final methods = createCase.body.members.whereType<MethodDeclaration>();
      final keyAssignments = <String, List<Expression>>{};
      for (final name in ['pickImages', 'adjustCoverCrop']) {
        final method = methods.singleWhere(
          (method) => method.name.lexeme == name,
        );
        final collector = _ImageLocalKeys();
        method.body.accept(collector);
        keyAssignments[name] = collector.values;
      }

      final portCall = predicate<Expression>(
        (expression) =>
            expression is MethodInvocation &&
            expression.methodName.name == 'newOpId' &&
            expression.methodName.element?.library?.uri.toString() ==
                'package:tentura/domain/port/op_id_port.dart' &&
            expression.argumentList.arguments.isEmpty,
        'a call to OpIdPort.newOpId()',
      );
      expect(keyAssignments, {
        'pickImages': [portCall],
        'adjustCoverCrop': [portCall],
      });
    },
  );

  test('browser draft reload supplies an operation ID port', () async {
    final resolved = await _resolve(_browserAppPath);
    final body = _FactoryBody();
    resolved.unit.accept(body);
    expect(body.caseConstructors, hasLength(1));
    final construction = body.caseConstructors.single;
    final arguments = construction.argumentList.arguments;
    expect(
      arguments,
      hasLength(3),
      reason: 'Pass an OpIdPort as the third argument',
    );
    final portType =
        construction.constructorName.element!.formalParameters[2].type;
    expect(portType.getDisplayString(), 'OpIdPort');
    expect(
      resolved.typeSystem.isSubtypeOf(
        arguments[2].argumentExpression.staticType!,
        portType,
      ),
      isTrue,
      reason: 'The browser app must pass a value implementing OpIdPort',
    );
  });

  test('client tests construct cases only through the shared factory', () {
    final textualSites = <({String path, int offset})>[];
    final constructorSites = <({String path, int offset})>[];
    for (final file in _testSources()) {
      final source = file.readAsStringSync();
      for (final match in _constructorSpelling.allMatches(source)) {
        textualSites.add((path: file.path, offset: match.start));
      }
      for (final call in beaconCreateCalls(source, file.path)) {
        if (call.target == beaconCreateConstructor) {
          constructorSites.add((path: file.path, offset: call.offset));
        }
      }
    }
    expect(
      textualSites,
      hasLength(1),
      reason: 'Only the shared factory may contain the constructor spelling',
    );
    expect(
      constructorSites,
      textualSites,
      reason:
          'The spelling must be a real call, with no additional calls '
          'split across lines or written with alternate syntax',
    );
    final file = _factoryFile();
    final factory = _functions(file, _factoryName).single;
    final body = factory.functionExpression.body;
    final site = textualSites.single;
    expect(site.path, file.path);
    expect(
      site.offset >= body.offset && site.offset < body.end,
      isTrue,
      reason: 'The only direct construction belongs inside $_factoryName',
    );
  });

  test('migrated callers keep their original write and image overrides', () {
    // Snapshot of the pre-migration calls, including all legacy helper users.
    final original =
        jsonDecode(File(_originalCallSites).readAsStringSync())
            as Map<String, Object?>;
    final legacyKept = _declarations(_legacyName).isNotEmpty;
    final issues = <String>[];

    for (final MapEntry(key: path, value: rows) in original.entries) {
      final file = File(path);
      final callsByContext = <String, List<BeaconCreateCall>>{};
      for (final call in beaconCreateCalls(file.readAsStringSync(), path)) {
        (callsByContext[call.context] ??= []).add(call);
      }
      // Compare within each named test, helper, or injection argument.
      // For repeated calls in the same context, use their source order.
      final offsets = <String, int>{};
      for (final row in (rows! as List<Object?>).cast<List<Object?>>()) {
        final context = row[0]! as String;
        final legacyCall = row[1] == 'legacy';
        final expectedPorts = (row[2]! as Map<String, Object?>)
            .cast<String, String>();
        final index = offsets.update(
          context,
          (prior) => prior + 1,
          ifAbsent: () => 0,
        );
        final calls = callsByContext[context] ?? const [];
        if (index >= calls.length) {
          issues.add('$path ($context) is missing a factory call');
          continue;
        }
        final call = calls[index];
        final location = '$path:${call.line} ($context)';
        if (call.target != _factoryName &&
            !(legacyKept && legacyCall && call.target == _legacyName)) {
          issues.add('$location calls ${call.target} instead of $_factoryName');
        }
        final expected = _customPorts(expectedPorts);
        final actual = _customPorts(call.ports);
        for (final name in {...expected.keys, ...actual.keys}) {
          if (actual[name] != expected[name]) {
            issues.add(
              '$location must pass $name: ${expected[name] ?? '(default)'}, '
              'found ${actual[name] ?? '(default)'}',
            );
          }
        }
      }
    }
    expect(
      issues.length,
      0,
      reason: issues.take(12).join('\n'),
    );
  });

  test('the legacy helper is retired or forwards both ports', () {
    final helpers = _declarations(_legacyName).toList();
    expect(
      helpers.map((helper) => helper.file.path),
      hasLength(lessThanOrEqualTo(1)),
      reason: 'Client tests may keep at most one top-level $_legacyName helper',
    );
    if (helpers.isEmpty) {
      final factoryPath = _factoryFile().path;
      final callers = [
        for (final file in _testSources())
          for (final call in beaconCreateCalls(
            file.readAsStringSync(),
            file.path,
          ))
            (path: file.path, target: call.target),
      ];
      expect(
        callers.where((call) => call.target == _legacyName),
        isEmpty,
        reason: 'Removed helpers should have no callers',
      );
      expect(
        callers.where(
          (call) => call.path != factoryPath && call.target == _factoryName,
        ),
        isNotEmpty,
        reason: 'Former helper callers now call the shared factory',
      );
      return;
    }
    final returned = switch (helpers.single.function.functionExpression.body) {
      ExpressionFunctionBody(:final expression) => expression,
      BlockFunctionBody(:final block) => switch (block.statements) {
        [ReturnStatement(:final expression)] => expression,
        _ => null,
      },
      _ => null,
    };
    expect(
      returned,
      isA<MethodInvocation>(),
      reason: 'The existing helper may only delegate to the shared factory',
    );
    final call = returned! as MethodInvocation;
    expect(call.methodName.name, _factoryName);
    final arguments = call.argumentList.arguments;
    expect(arguments, hasLength(2));
    expect(
      {
        for (final argument in arguments.whereType<NamedArgument>())
          argument.name.lexeme: argument.argumentExpression.toSource(),
      },
      {'beacons': 'write', 'images': 'images'},
    );
  });

  test(
    'the factory builds independent cases and honors caller-supplied ports',
    () async {
      final factory = _factoryFile();
      final probe = File('test/support/beacon_create_case_factory_probe.dart');
      // Compile the consumer only after confirming the factory exists so the
      // missing factory is reported by an assertion on the baseline.
      final scratch = Directory.systemTemp.createTempSync(
        'beacon-create-factory-',
      );
      addTearDown(() => scratch.deleteSync(recursive: true));
      final launcher = File.fromUri(scratch.uri.resolve('factory_test.dart'))
        ..writeAsStringSync('''
import '${factory.absolute.uri}';
import '${probe.absolute.uri}';

void main() => registerBeaconCreateCaseFactoryTests(buildBeaconCreateCase);
''');
      final process = await Process.start('flutter', [
        'test',
        '--no-pub',
        '--no-test-assets',
        '--reporter=expanded',
        launcher.path,
      ]);
      final stdout = process.stdout.transform(utf8.decoder).join();
      final stderr = process.stderr.transform(utf8.decoder).join();
      final code = await process.exitCode.timeout(
        const Duration(minutes: 3),
        onTimeout: () {
          process.kill(ProcessSignal.sigkill);
          fail('The factory behavior probe exceeded three minutes');
        },
      );
      expect(code, 0, reason: '${await stdout}\n${await stderr}');
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

class _ImageLocalKeys extends RecursiveAstVisitor<void> {
  final values = <Expression>[];

  @override
  void visitNamedArgument(NamedArgument node) {
    if (node.name.lexeme == 'localKey') {
      values.add(node.argumentExpression.unParenthesized);
    }
    super.visitNamedArgument(node);
  }
}

Map<String, String> _customPorts(Map<String, String> ports) => {
  for (final MapEntry(:key, :value) in ports.entries)
    if ((key, value) != ('beacons', 'FakeBeaconWritePort()') &&
        (key, value) != ('images', 'FakeBeaconImagePort()'))
      key: value,
};

class _FactoryBody extends RecursiveAstVisitor<void> {
  final caseConstructors = <InstanceCreationExpression>[];
  final _initializers = <Element, Expression>{};

  void expectFreshFallback(
    Argument argument,
    String port,
    String fallbackType, {
    String sourcePath = _fakePortsPath,
  }) {
    final selection = _initializer(argument);
    expect(selection, isA<BinaryExpression>(), reason: port);
    final fallback = selection! as BinaryExpression;
    expect(fallback.operator.lexeme, '??');
    final supplied = _initializer(fallback.leftOperand);
    expect(supplied, isA<SimpleIdentifier>());
    final parameter = (supplied! as SimpleIdentifier).element;
    expect(parameter, isA<FormalParameterElement>());
    expect(parameter?.name, port);
    final defaultPort = fallback.rightOperand;
    expect(defaultPort, isA<InstanceCreationExpression>(), reason: port);
    final constructor = defaultPort as InstanceCreationExpression;
    expect(
      constructor.constructorName.element?.enclosingElement.name,
      fallbackType,
    );
    expect(
      constructor
          .constructorName
          .element
          ?.library
          .firstFragment
          .source
          .fullName,
      File(sourcePath).absolute.path,
    );
    expect(constructor.argumentList.arguments, isEmpty);
  }

  Expression? _initializer(AstNode node) {
    if (node is SimpleIdentifier) return _initializers[node.element] ?? node;
    return node is Expression ? node : null;
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    final element = node.declaredFragment?.element;
    final initializer = node.initializer;
    if (element != null && initializer != null) {
      _initializers[element] = initializer;
    }
    super.visitVariableDeclaration(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (node.constructorName.element?.enclosingElement.name ==
        'BeaconCreateCase') {
      caseConstructors.add(node);
    }
    super.visitInstanceCreationExpression(node);
  }
}
