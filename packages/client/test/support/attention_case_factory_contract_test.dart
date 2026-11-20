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

const _factoryName = 'buildAttentionCase';
const _myWorkHelper = 'buildStubAttentionCase';
const _myWorkSupport = 'test/features/my_work/my_work_test_support.dart';

// Existing users of the helper, including its use in the My Work fixture.
const _myWorkHelperCallers = [
  'test/features/beacon_lobby/beacon_lobby_rail_test.dart',
  'test/features/beacon_lobby/questions_open_clears_updates_test.dart',
  'test/features/beacon_lobby/questions_phone_text_legibility_test.dart',
  'test/features/beacon_lobby/questions_screen_shared_chat_test.dart',
  'test/features/beacon_lobby/questions_unread_divider_test.dart',
  'test/features/home/home_cold_deep_link_tab_traversal_test.dart',
  'test/features/home/home_my_work_load_failure_test.dart',
  'test/features/home/home_nav_landmark_test.dart',
  'test/features/home/home_post_join_post_lands_on_posts_test.dart',
  'test/features/home/home_snack_bar_beside_rail_test.dart',
  'test/features/home/my_desk_tab_reselect_scroll_wire_test.dart',
  'test/features/my_work/my_work_case_streams_test.dart',
  'test/features/my_work/requests_reload_when_back_online_test.dart',
  _myWorkSupport,
];

Iterable<File> _dartFiles(String directory) => Directory(directory)
    .listSync(recursive: true, followLinks: false)
    .whereType<File>()
    .where((file) => file.path.endsWith('.dart'));

Iterable<FunctionDeclaration> _functions(File file, String name) {
  final source = file.readAsStringSync();
  if (!source.contains(name)) return const [];
  return parseString(
    content: source,
    path: file.path,
  ).unit.declarations.whereType<FunctionDeclaration>().where(
    (declaration) =>
        declaration.name.lexeme == name &&
        declaration.functionExpression.parameters != null,
  );
}

File _sharedFactoryFile() {
  final factories = [
    for (final file in _dartFiles('test'))
      for (final _ in _functions(file, _factoryName)) file,
  ];
  expect(
    factories.map((file) => file.path),
    hasLength(1),
    reason: 'Test callers need a single top-level buildAttentionCase',
  );
  expect(factories.single.path, startsWith('test/support/'));
  return factories.single;
}

AnalysisContextCollection _analysisContexts(Iterable<File> files) {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  final contexts = AnalysisContextCollection(
    includedPaths: files.map((file) => file.absolute.path).toList(),
    sdkPath: flutterRoot == null ? null : '$flutterRoot/bin/cache/dart-sdk',
  );
  addTearDown(contexts.dispose);
  return contexts;
}

Future<ResolvedUnitResult> _resolve(
  File file, {
  AnalysisContextCollection? contexts,
}) async {
  final path = file.absolute.path;
  contexts ??= _analysisContexts([file]);
  final unit = await contexts
      .contextFor(path)
      .currentSession
      .getResolvedUnit(path);
  expect(
    unit,
    isA<ResolvedUnitResult>(),
    reason: 'Resolve the Dart file at $path',
  );
  return unit as ResolvedUnitResult;
}

void main() {
  test(
    'shared AttentionCase factory accepts every named dependency override',
    () {
      final factory = _functions(_sharedFactoryFile(), _factoryName).single;
      final parameters = factory.functionExpression.parameters!.parameters;
      expect(
        parameters.every((parameter) => parameter.isOptionalNamed),
        isTrue,
      );
      expect(
        parameters.map((parameter) => parameter.name?.lexeme),
        unorderedEquals([
          'repository',
          'accounts',
          'realtimeSyncCase',
          'blockCase',
          'feedSessions',
          'logger',
          'qaLatencyMeasurementEnabled',
        ]),
      );
    },
  );

  test(
    'client tests share one real AttentionCase constructor with fixture defaults',
    () async {
      final spelling = RegExp(r'\bAttentionCase\(');
      final callSites = <({String path, int line})>[];
      for (final file in _dartFiles('test')) {
        final lines = file.readAsLinesSync();
        for (var index = 0; index < lines.length; index++) {
          if (spelling.hasMatch(lines[index])) {
            callSites.add((path: file.path, line: index + 1));
          }
        }
      }
      expect(
        callSites,
        hasLength(1),
        reason: 'Only the shared factory should call the constructor directly',
      );

      final file = _sharedFactoryFile();
      final parsed = await _resolve(file);
      final factory = parsed.unit.declarations
          .whereType<FunctionDeclaration>()
          .singleWhere(
            (declaration) => declaration.name.lexeme == _factoryName,
          );
      final returnType = factory.declaredFragment?.element.returnType;
      if (returnType is! InterfaceType) {
        fail('The factory must return an AttentionCase, found $returnType');
      }
      final returnedClass = returnType.element;
      expect(returnedClass.name, 'AttentionCase');
      expect(
        returnedClass.library.firstFragment.source.fullName,
        File('lib/domain/attention/attention_case.dart').absolute.path,
      );
      final body = _FactoryBody();
      factory.functionExpression.body.accept(body);
      final calls = body.constructors.where(
        (call) =>
            call.constructorName.element?.enclosingElement == returnedClass,
      );
      expect(
        calls,
        hasLength(1),
        reason: 'The matched line must invoke the constructor in the factory',
      );
      final offset = calls.single.constructorName.type.name.offset;
      expect(callSites.single, (
        path: file.path,
        line: parsed.lineInfo.getLocation(offset).lineNumber,
      ));
      _expectFixtureDefaults(body, calls.single);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('My Work fixtures use the shared AttentionCase factory', () async {
    final file = File(_myWorkSupport);
    final helper = file.existsSync()
        ? _functions(file, _myWorkHelper).singleOrNull
        : null;
    if (helper == null) {
      final factory = _sharedFactoryFile();
      final callers = _myWorkHelperCallers.map(File.new).toList();
      for (final caller in callers) {
        expect(caller.existsSync(), isTrue, reason: caller.path);
      }
      final contexts = _analysisContexts(callers);
      for (final caller in callers) {
        final resolved = await _resolve(caller, contexts: contexts);
        final body = _FactoryBody();
        resolved.unit.accept(body);
        expect(body.retiredHelperCalls, isEmpty, reason: caller.path);
        expect(
          body.factoryCalls.map(_declaringFile),
          contains(factory.absolute.path),
          reason:
              '${caller.path} used the retired helper and must now use the factory',
        );
      }
      return;
    }
    final body = _FactoryBody();
    helper.functionExpression.body.accept(body);
    expect(
      body.factoryCalls,
      isNotEmpty,
      reason: 'The My Work helper must delegate to the shared factory if kept',
    );
    final factory = _sharedFactoryFile();
    final resolved = await _resolve(file);
    final resolvedHelper = resolved.unit.declarations
        .whereType<FunctionDeclaration>()
        .singleWhere(
          (declaration) => declaration.name.lexeme == _myWorkHelper,
        );
    final resolvedBody = _FactoryBody();
    resolvedHelper.functionExpression.body.accept(resolvedBody);
    expect(
      resolvedBody.factoryCalls.map(_declaringFile),
      contains(factory.absolute.path),
    );
  }, timeout: const Timeout(Duration(minutes: 3)));

  test(
    'default dependencies produce an independent signed-out case',
    () => _runFactoryProbe(
      qaMode: false,
      description: 'omitted dependencies produce an inert independent case',
    ),
    timeout: const Timeout(Duration(minutes: 4)),
  );

  test(
    'a repository override alone supplies the Request history page',
    () => _runFactoryProbe(
      qaMode: false,
      description: 'a repository override alone serves Request history',
    ),
    timeout: const Timeout(Duration(minutes: 4)),
  );

  test(
    'default case keeps latency sampling off even in QA mode',
    () => _runFactoryProbe(
      qaMode: true,
      description: 'default case has QA latency sampling disabled',
    ),
    timeout: const Timeout(Duration(minutes: 4)),
  );

  test(
    'overrides drive feed refreshes and enable latency sampling',
    () => _runFactoryProbe(
      qaMode: false,
      description: 'supplied collaborators drive feed refreshes and QA reports',
    ),
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

Future<void> _runFactoryProbe({
  required bool qaMode,
  required String description,
}) async {
  final factory = _sharedFactoryFile();
  final probe = File('test/support/attention_case_factory_probe.dart');
  // Compile the behavioral tests only once the factory is available. The
  // baseline therefore fails on the assertion above instead of an import.
  final scratch = Directory.systemTemp.createTempSync('attention-factory-');
  addTearDown(() => scratch.deleteSync(recursive: true));
  final launcher = File.fromUri(scratch.uri.resolve('factory_test.dart'))
    ..writeAsStringSync('''
import '${factory.absolute.uri}';
import '${probe.absolute.uri}';

void main() => registerAttentionCaseFactoryTests(buildAttentionCase);
''');

  final process = await Process.start('flutter', [
    'test',
    '--no-pub',
    '--no-test-assets',
    '--reporter=expanded',
    '--dart-define=QA_INTEGRATION_TEST_MODE=$qaMode',
    '--plain-name=$description',
    launcher.path,
  ]);
  final stdout = process.stdout.transform(utf8.decoder).join();
  final stderr = process.stderr.transform(utf8.decoder).join();
  final exitCode = await process.exitCode.timeout(
    const Duration(minutes: 3),
    onTimeout: () {
      process.kill(ProcessSignal.sigkill);
      fail('The factory behavior probe exceeded three minutes');
    },
  );
  expect(exitCode, 0, reason: '${await stdout}\n${await stderr}');
}

String? _declaringFile(MethodInvocation call) =>
    call.methodName.element?.library?.firstFragment.source.fullName;

void _expectFixtureDefaults(
  _FactoryBody body,
  InstanceCreationExpression constructor,
) {
  final arguments = constructor.argumentList.arguments;
  // Inspect the actual constructor arguments. Merely finding these helpers
  // elsewhere in the file would also accept dead code and eager fallbacks.
  body.fallbackFor(arguments[0], 'repository');
  expect(
    body.methodCalls.where((call) {
      final targetType = call.realTarget?.staticType;
      if (targetType is! InterfaceType) return false;
      return [targetType, ...targetType.allSupertypes].any(
        (type) => type.element.name == 'AttentionRepositoryPort',
      );
    }),
    isEmpty,
    reason:
        'The factory passes the selected repository to the case without calling it',
  );

  final realtime = body.fallbackFor(arguments[2], 'realtimeSyncCase');
  expect(realtime, isA<PropertyAccess>());
  final realtimeAccess = realtime as PropertyAccess;
  expect(realtimeAccess.propertyName.name, 'case_');
  expect(realtimeAccess.target, isA<MethodInvocation>());
  final realtimeBuilder = realtimeAccess.target! as MethodInvocation;
  expect(realtimeBuilder.methodName.name, 'buildTestRealtimeSync');
  expect(
    _declaringFile(realtimeBuilder),
    File('test/support/test_realtime_sync.dart').absolute.path,
  );

  final block = body.fallbackFor(arguments[3], 'blockCase');
  expect(block, isA<MethodInvocation>());
  final blockBuilder = block as MethodInvocation;
  expect(blockBuilder.methodName.name, 'noopBlockCase');
  expect(
    _declaringFile(blockBuilder),
    File(
      'test/features/block/support/controllable_block_case.dart',
    ).absolute.path,
  );

  final registry = body.fallbackFor(arguments[4], 'feedSessions');
  expect(registry, isA<InstanceCreationExpression>());
  expect(
    (registry as InstanceCreationExpression)
        .constructorName
        .element
        ?.enclosingElement
        .name,
    'FeedSessionRegistry',
  );

  final logger = body.fallbackFor(arguments[5], 'logger');
  expect(logger, isA<InstanceCreationExpression>());
  final loggerConstructor = logger as InstanceCreationExpression;
  expect(
    loggerConstructor.constructorName.element?.enclosingElement.name,
    'Logger',
  );
  final name = loggerConstructor.argumentList.arguments.single;
  final fixedName = switch (name) {
    StringLiteral() => name.stringValue,
    SimpleIdentifier(element: final VariableElement constant)
        when constant.isConst =>
      constant.computeConstantValue()?.toStringValue(),
    _ => null,
  };
  expect(fixedName, isNotEmpty, reason: 'The default logger has a fixed name');
}

class _FactoryBody extends RecursiveAstVisitor<void> {
  final constructors = <InstanceCreationExpression>[];
  final methodCalls = <MethodInvocation>[];
  final factoryCalls = <MethodInvocation>[];
  final retiredHelperCalls = <MethodInvocation>[];
  final _initializers = <Element, Expression>{};

  Expression fallbackFor(Argument argument, String override) {
    final selection = _initializer(argument);
    if (selection is! BinaryExpression) {
      fail('$override should select its fallback only when omitted');
    }
    expect(selection.operator.lexeme, '??', reason: override);
    final supplied = _initializer(selection.leftOperand);
    if (supplied is! SimpleIdentifier) {
      fail('$override should forward the supplied parameter');
    }
    final parameter = supplied.element;
    expect(parameter, isA<FormalParameterElement>());
    expect(parameter?.name, override);
    return selection.rightOperand;
  }

  Expression? _initializer(AstNode node) {
    if (node is! SimpleIdentifier) return node is Expression ? node : null;
    return _initializers[node.element] ?? node;
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
  void visitMethodInvocation(MethodInvocation node) {
    methodCalls.add(node);
    if (node.methodName.name == _factoryName) factoryCalls.add(node);
    if (node.methodName.name == _myWorkHelper) retiredHelperCalls.add(node);
    super.visitMethodInvocation(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    constructors.add(node);
    super.visitInstanceCreationExpression(node);
  }
}
