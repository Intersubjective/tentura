// Analyzer and test are transitive dependencies used only for source contracts.
// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:test/test.dart';

const _perfPath = 'lib/features/constellation/ui/util/constellation_perf.dart';

enum _Guard { nonRelease, debugOnly }

bool _allowsMode(Expression expression, _Guard guard, {bool negated = false}) {
  if (expression is ParenthesizedExpression) {
    return _allowsMode(expression.expression, guard, negated: negated);
  }
  if (expression is PrefixExpression && expression.operator.lexeme == '!') {
    return _allowsMode(expression.operand, guard, negated: !negated);
  }
  if (expression is BinaryExpression) {
    final left = _allowsMode(expression.leftOperand, guard, negated: negated);
    final right = _allowsMode(expression.rightOperand, guard, negated: negated);
    if (expression.operator.lexeme == '&&') {
      return negated ? left && right : left || right;
    }
    if (expression.operator.lexeme == '||') {
      return negated ? left || right : left && right;
    }
  }
  final name = switch (expression) {
    SimpleIdentifier() => expression.name,
    PrefixedIdentifier() => expression.identifier.name,
    PropertyAccess() => expression.propertyName.name,
    _ => null,
  };
  if (guard == _Guard.debugOnly) return name == 'kDebugMode' && !negated;
  return (name == 'kReleaseMode' && negated) ||
      ({'kDebugMode', 'kProfileMode'}.contains(name) && !negated);
}

bool _returns(AstNode branch) =>
    branch is ReturnStatement ||
    (branch is Block &&
        branch.statements.isNotEmpty &&
        branch.statements.last is ReturnStatement);

bool _guarded(AstNode operation, _Guard guard) {
  var child = operation;
  for (var parent = operation.parent; parent != null; parent = parent.parent) {
    if (parent is IfStatement &&
        ((_allowsMode(parent.expression, guard) &&
                child == parent.thenStatement) ||
            (_allowsMode(parent.expression, guard, negated: true) &&
                child == parent.elseStatement))) {
      return true;
    }
    if (parent is IfElement &&
        ((_allowsMode(parent.expression, guard) &&
                child == parent.thenElement) ||
            (_allowsMode(parent.expression, guard, negated: true) &&
                child == parent.elseElement))) {
      return true;
    }
    if (parent is ConditionalExpression &&
        ((_allowsMode(parent.condition, guard) &&
                child == parent.thenExpression) ||
            (_allowsMode(parent.condition, guard, negated: true) &&
                child == parent.elseExpression))) {
      return true;
    }
    if (parent is BinaryExpression &&
        parent.operator.lexeme == '&&' &&
        _allowsMode(parent.leftOperand, guard) &&
        child == parent.rightOperand) {
      return true;
    }
    if (parent is Block && child is Statement) {
      for (final earlier in parent.statements.takeWhile((s) => s != child)) {
        if (earlier is IfStatement &&
            _allowsMode(earlier.expression, guard, negated: true) &&
            _returns(earlier.thenStatement)) {
          return true;
        }
      }
    }
    child = parent;
  }
  return false;
}

Iterable<AstNode> _descendants(AstNode node) sync* {
  yield node;
  for (final child in node.childEntities.whereType<AstNode>()) {
    yield* _descendants(child);
  }
}

bool _developerTimeline(Element? element) =>
    element?.library?.uri.toString() == 'dart:developer' &&
    {
      'Timeline',
      'TimelineTask',
    }.contains(element?.enclosingElement?.displayName);

class _Operations extends RecursiveAstVisitor<void> {
  final timeline = <AstNode>[];
  final subscriptions = <MethodInvocation>[];
  final instrumentationState = <AstNode>[];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final element = node.methodName.element;
    if (_developerTimeline(element)) timeline.add(node);
    if (node.methodName.name == 'addTimingsCallback' &&
        element?.enclosingElement?.displayName == 'SchedulerBinding') {
      subscriptions.add(node);
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final constructor = node.constructorName.element;
    if (_developerTimeline(constructor)) timeline.add(node);
    final name = constructor?.enclosingElement.displayName ?? '';
    if ({
      'ValueNotifier',
      'ChangeNotifier',
      'Stopwatch',
      'Timer',
      'StreamController',
    }.contains(name)) {
      instrumentationState.add(node);
    }
    super.visitInstanceCreationExpression(node);
  }
}

class _HudMenu extends RecursiveAstVisitor<void> {
  final actions = <NamedArgument>[];

  @override
  void visitNamedArgument(NamedArgument node) {
    if ({'onChanged', 'onPressed'}.contains(node.name.lexeme) &&
        node.argumentExpression is! NullLiteral &&
        _guarded(node, _Guard.debugOnly)) {
      actions.add(node);
    }
    super.visitNamedArgument(node);
  }
}

// Connect menu callbacks to rendered widgets through resolved shared state,
// rather than requiring a particular label, control flow syntax or HUD class.
class _SharedState {
  _SharedState(Iterable<CompilationUnit> units) {
    for (final node in units.expand(_descendants)) {
      final element = switch (node) {
        FunctionDeclaration() => node.declaredFragment?.element,
        MethodDeclaration() => node.declaredFragment?.element,
        VariableDeclaration() => node.declaredFragment?.element,
        _ => null,
      };
      if (element != null) declarations[element] = node;
    }
  }

  final declarations = <Element, AstNode>{};

  Set<Element> variables(AstNode node, [Set<Element>? visited]) {
    final seen = visited ?? <Element>{};
    final result = <Element>{};
    for (final identifier in _descendants(node).whereType<SimpleIdentifier>()) {
      final element = identifier.element;
      if (element == null || !seen.add(element)) continue;
      final variable = element is PropertyAccessorElement
          ? element.variable
          : element;
      if (variable is VariableElement &&
          (declarations.containsKey(variable) ||
              variable.library?.uri.toString().startsWith('package:tentura/') ==
                  true)) {
        result.add(variable);
      }
      final declaration = declarations[element] ?? declarations[variable];
      if (declaration != null && declaration != node) {
        result.addAll(variables(declaration, seen));
      }
    }
    return result;
  }
}

bool _createsWidget(InstanceCreationExpression node) {
  final type = node.constructorName.element?.enclosingElement;
  if (type is! InterfaceElement) return false;
  return type.allSupertypes.any(
    (parent) =>
        parent.element.name == 'Widget' &&
        parent.element.library.uri.toString() ==
            'package:flutter/src/widgets/framework.dart',
  );
}

List<AstNode> _controlledHud(
  Iterable<CompilationUnit> units,
  _HudMenu menu,
) {
  final sharedState = _SharedState(units);
  final toggled = menu.actions
      .expand((action) => sharedState.variables(action.argumentExpression))
      .toSet();
  bool readsToggle(AstNode node) =>
      sharedState.variables(node).intersection(toggled).isNotEmpty;

  final rendered = <AstNode>[];
  for (final node in units.expand(_descendants)) {
    if (node is NamedArgument &&
        node.name.lexeme == 'showPerformanceOverlay' &&
        readsToggle(node.argumentExpression)) {
      rendered.add(node.argumentExpression);
    }
    if (node is! InstanceCreationExpression || !_createsWidget(node)) continue;
    // A menu control containing its own callback is not the overlay it toggles.
    if (_descendants(node).any(menu.actions.contains)) continue;
    var connected = node.argumentList.arguments.any((argument) {
      if (argument is NamedArgument &&
          argument.name.lexeme == 'showPerformanceOverlay') {
        return false;
      }
      // Check the allocation consuming state, not an ancestor container whose
      // children happen to include the HUD.
      if (_descendants(
        argument,
      ).whereType<InstanceCreationExpression>().any(_createsWidget)) {
        return false;
      }
      return readsToggle(argument);
    });
    for (var parent = node.parent; parent != null; parent = parent.parent) {
      final condition = switch (parent) {
        IfElement() => parent.expression,
        IfStatement() => parent.expression,
        ConditionalExpression() => parent.condition,
        _ => null,
      };
      if (condition != null && readsToggle(condition)) connected = true;
    }
    if (connected) rendered.add(node);
  }
  return rendered;
}

bool _debugOnlyHud(AstNode allocation) =>
    (allocation is Expression &&
        (_allowsMode(allocation, _Guard.debugOnly) ||
            (allocation is BinaryExpression &&
                allocation.operator.lexeme == '&&' &&
                _allowsMode(allocation.leftOperand, _Guard.debugOnly)) ||
            (allocation is ConditionalExpression &&
                _allowsMode(allocation.condition, _Guard.debugOnly) &&
                allocation.elseExpression.toSource() == 'false'))) ||
    _guarded(allocation, _Guard.debugOnly);

Iterable<File> _sourceFiles() =>
    [
          Directory('lib/features/constellation'),
          Directory('lib/features/settings/ui'),
        ]
        .expand(
          (directory) => directory.listSync(recursive: true).whereType<File>(),
        )
        .where((file) => file.path.endsWith('.dart'))
        .where(
          (file) => ![
            '.g.dart',
            '.freezed.dart',
            '.gr.dart',
            '.config.dart',
            '.schema.dart',
            '.gql.dart',
          ].any(file.path.endsWith),
        );

Iterable<File> _hudSourceFiles() sync* {
  final files = {for (final file in _sourceFiles()) file.path: file};
  // Flutter's built-in HUD can be enabled at MaterialApp, while a custom
  // readout can live wherever the instrumentation state is imported.
  final app = File('lib/app/app.dart');
  if (app.existsSync()) files[app.path] = app;
  for (final file in Directory(
    'lib',
  ).listSync(recursive: true).whereType<File>()) {
    if (!file.path.endsWith('.dart') ||
        files.containsKey(file.path) ||
        [
          '.g.dart',
          '.freezed.dart',
          '.gr.dart',
          '.config.dart',
          '.schema.dart',
          '.gql.dart',
        ].any(file.path.endsWith)) {
      continue;
    }
    final unit = parseString(content: file.readAsStringSync()).unit;
    if (unit.directives.whereType<ImportDirective>().any(
      (directive) =>
          directive.uri.stringValue?.endsWith(
            'constellation_perf.dart',
          ) ==
          true,
    )) {
      files[file.path] = file;
    }
  }
  yield* files.values;
}

Future<CompilationUnit> _resolved(
  File file,
  AnalysisContextCollection contexts,
) async {
  final path = file.absolute.path;
  final result = await contexts
      .contextFor(path)
      .currentSession
      .getResolvedUnit(path);
  expect(
    result,
    isA<ResolvedUnitResult>(),
    reason: 'Resolve API owners in $path',
  );
  return (result as ResolvedUnitResult).unit;
}

/// `flutter test` runs in flutter_tester, so the analyzer cannot infer the
/// Dart SDK from the resolved executable; point it at the Flutter-bundled one.
String? _dartSdkPath() {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot == null) return null;
  final sdk = Directory('$flutterRoot/bin/cache/dart-sdk');
  return sdk.existsSync() ? sdk.path : null;
}

void main() {
  group('Constellation performance instrumentation', () {
    late AnalysisContextCollection contexts;

    setUp(() {
      contexts = AnalysisContextCollection(
        includedPaths: [Directory('lib').absolute.path],
        sdkPath: _dartSdkPath(),
      );
    });
    tearDown(() => contexts.dispose());

    Future<CompilationUnit> perfUnit() async {
      final file = File(_perfPath);
      expect(
        file.existsSync(),
        isTrue,
        reason: 'Constellation must provide guarded performance helpers',
      );
      return _resolved(file, contexts);
    }

    Future<List<CompilationUnit>> hudUnits() async {
      final units = <CompilationUnit>[];
      for (final file in _hudSourceFiles()) {
        units.add(await _resolved(file, contexts));
      }
      return units;
    }

    Future<_HudMenu> hudMenu() async {
      final menu = _HudMenu();
      (await _resolved(
        File('lib/features/settings/ui/screen/debug_settings_screen.dart'),
        contexts,
      )).accept(menu);
      return menu;
    }

    test('timeline operations are excluded from release execution', () async {
      final operations = _Operations();
      (await perfUnit()).accept(operations);
      expect(operations.timeline, isNotEmpty);
      for (final file in _sourceFiles().where(
        (file) => file.path != _perfPath,
      )) {
        (await _resolved(file, contexts)).accept(operations);
      }
      for (final operation in operations.timeline) {
        expect(
          _guarded(operation, _Guard.nonRelease),
          isTrue,
          reason: 'Release must bypass ${operation.toSource()}',
        );
      }
    });

    test(
      'frame timing subscription remains available in debug and profile',
      () async {
        final operations = _Operations();
        (await perfUnit()).accept(operations);
        expect(operations.subscriptions, isNotEmpty);
        for (final registration in operations.subscriptions) {
          expect(_guarded(registration, _Guard.nonRelease), isTrue);
          expect(
            _guarded(registration, _Guard.debugOnly),
            isFalse,
            reason: 'Profile must retain the frame timing callback',
          );
          for (
            var parent = registration.parent;
            parent != null;
            parent = parent.parent
          ) {
            expect(
              parent is AssertStatement || parent is AssertInitializer,
              isFalse,
              reason:
                  'Profile must retain the frame timing callback without asserts',
            );
          }
        }
      },
    );

    test(
      'developer menu exposes a debug-only performance HUD toggle',
      () async {
        final menu = await hudMenu();
        expect(
          menu.actions,
          isNotEmpty,
          reason: 'The debug-only HUD entry must have an actionable callback',
        );
        expect(
          _controlledHud(await hudUnits(), menu),
          isNotEmpty,
          reason: 'The menu action must control rendered overlay state',
        );
      },
    );

    test(
      'HUD overlay and instrumentation state allocate nothing in release',
      () async {
        final utility = _Operations();
        (await perfUnit()).accept(utility);
        for (final allocation in utility.instrumentationState) {
          expect(
            _guarded(allocation, _Guard.nonRelease),
            isTrue,
            reason: 'Release must not allocate ${allocation.toSource()}',
          );
        }
        final hud = _controlledHud(await hudUnits(), await hudMenu());
        expect(
          hud,
          isNotEmpty,
          reason: 'A HUD toggle must be backed by a performance overlay',
        );
        for (final allocation in hud) {
          expect(
            _debugOnlyHud(allocation),
            isTrue,
            reason: 'HUD overlay code must be reachable only in debug',
          );
        }
      },
    );

    test('developer actions support statement and collection debug guards', () {
      for (final content in [
        "Object menu() { if (kDebugMode) { return Control(label: 'Frame statistics', onPressed: toggle); } return Empty(); }",
        "List<Object> menu() => [if (kDebugMode) Control(label: 'Rendering', onChanged: toggle)];",
        "Object menu() => kDebugMode ? Control(label: 'Diagnostics', onPressed: toggle) : Empty();",
        "Object menu() { if (kDebugMode && available) { return Control(label: 'Rendering', onPressed: toggle); } return Empty(); }",
      ]) {
        final menu = _HudMenu();
        parseString(content: content).unit.accept(menu);
        expect(menu.actions, hasLength(1), reason: content);
      }
      final menu = _HudMenu();
      parseString(
        content:
            "Object menu() => Control(label: 'Diagnostics', onPressed: toggle);",
      ).unit.accept(menu);
      expect(menu.actions, isEmpty);
    });

    test(
      'developer toggles control custom readouts and Flutter overlays',
      () async {
        final directory = Directory.systemTemp.createTempSync('debug_readout_');
        final configFile = File(
          '../../.dart_tool/package_config.json',
        ).absolute;
        final config =
            jsonDecode(configFile.readAsStringSync()) as Map<String, dynamic>;
        for (final package in config['packages'] as List<dynamic>) {
          final entry = package as Map<String, dynamic>;
          entry['rootUri'] = configFile.uri
              .resolve(entry['rootUri'] as String)
              .toString();
        }
        File('${directory.path}/.dart_tool/package_config.json')
          ..parent.createSync(recursive: true)
          ..writeAsStringSync(jsonEncode(config));
        final fixtureContexts = AnalysisContextCollection(
          includedPaths: [directory.path],
          sdkPath: _dartSdkPath(),
        );
        try {
          var index = 0;
          for (final scene in [
            '''
Widget scene() {
  if (!kDebugMode) return const SizedBox.shrink();
  return Stack(children: [if (enabled) const Readout()]);
}''',
            'Widget scene() => Stack(children: [if (kDebugMode && enabled) const Readout()]);',
            'Widget scene() => MaterialApp(showPerformanceOverlay: kDebugMode && enabled);',
            'Widget scene() => Stack(children: [if (enabled) const Readout()]);',
          ]) {
            final file = File('${directory.path}/readout${index++}.dart')
              ..writeAsStringSync('''
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
bool enabled = false;
void toggle() { enabled = !enabled; }
Widget menu() {
  if (kDebugMode) {
    return SwitchListTile(
      title: const Text('Rendering statistics'),
      value: enabled,
      onChanged: (_) => toggle(),
    );
  }
  return const SizedBox.shrink();
}
class Readout extends StatelessWidget {
  const Readout();
  @override
  Widget build(BuildContext context) => const Text('16 ms');
}
$scene
''');
            final unit = await _resolved(file, fixtureContexts);
            final menu = _HudMenu();
            unit.accept(menu);
            expect(menu.actions, hasLength(1));
            final hud = _controlledHud([unit], menu);
            expect(hud, hasLength(1), reason: scene);
            expect(
              _debugOnlyHud(hud.single),
              scene.contains('kDebugMode'),
              reason: scene,
            );
          }
        } finally {
          await fixtureContexts.dispose();
          directory.deleteSync(recursive: true);
        }
      },
    );

    test('release guard traversal terminates for nested unguarded code', () {
      final unit = parseString(
        content: 'void f() { if (ready) { work(); } }',
      ).unit;
      final function = unit.declarations.single as FunctionDeclaration;
      final body = function.functionExpression.body as BlockFunctionBody;
      final branch =
          (body.block.statements.single as IfStatement).thenStatement as Block;
      expect(_guarded(branch.statements.single, _Guard.nonRelease), isFalse);
    });

    test(
      'release guards protect work through nested branches and early exits',
      () {
        for (final content in [
          'void f() { if (!kReleaseMode) { if (ready) { work(); } } }',
          'void f() { if (kReleaseMode) return; if (ready) { work(); } }',
          'void f() { if (kReleaseMode) {} else { if (ready) { work(); } } }',
          'void f() { final result = !kReleaseMode && work(); }',
        ]) {
          final call = _descendants(
            parseString(content: content).unit,
          ).whereType<MethodInvocation>().single;
          expect(_guarded(call, _Guard.nonRelease), isTrue, reason: content);
          expect(_guarded(call, _Guard.debugOnly), isFalse, reason: content);
        }
      },
    );

    test(
      'ordinary start and finish methods are not Timeline operations',
      () async {
        final directory = Directory.systemTemp.createTempSync(
          'timeline_api_owner_',
        );
        final file = File('${directory.path}/operations.dart')
          ..writeAsStringSync('''
import 'dart:developer' as tracing;
class Work {
  void start() {}
  void finish() {}
}
void capture() {
  Work().start();
  Work().finish();
  tracing.Timeline.startSync('work');
  tracing.Timeline.finishSync();
  final task = tracing.TimelineTask();
  task.start('async work');
  task.finish();
}
''');
        final fixtureContexts = AnalysisContextCollection(
          includedPaths: [directory.path],
          sdkPath: _dartSdkPath(),
        );
        try {
          final operations = _Operations();
          (await _resolved(file, fixtureContexts)).accept(operations);
          expect(
            operations.timeline.whereType<MethodInvocation>().map(
              (node) => node.methodName.name,
            ),
            unorderedEquals(['startSync', 'finishSync', 'start', 'finish']),
          );
          expect(
            operations.timeline.whereType<InstanceCreationExpression>(),
            hasLength(1),
          );
        } finally {
          await fixtureContexts.dispose();
          await directory.delete(recursive: true);
        }
      },
    );
  }, timeout: const Timeout(Duration(minutes: 3))); // Cold analyzer start.
}
