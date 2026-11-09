import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

/// Client `lib/**` outside `lib/app/` must not import `lib/app/router/`,
/// except `@RoutePage` screens.
///
/// The router's generated routes import every screen, so one such import puts
/// the whole app in a feature's import closure, and import-graph test
/// selection then picks nearly every test. Navigate through the
/// `AppNavigator` port (`lib/ui/navigation/app_navigator.dart`) instead, and
/// take `HomeTab` / `HomeTabSpec` from `lib/ui/navigation/home_tab.dart`.
final class NoRouterImportOutsideApp extends AnalysisRule {
  NoRouterImportOutsideApp()
    : super(
        name: 'no_router_import_outside_app',
        description:
            'Only lib/app/ and @RoutePage screens may import lib/app/router/; '
            'navigate through AppNavigator.',
      );

  static const LintCode code = LintCode(
    'no_router_import_outside_app',
    'Only lib/app/ and @RoutePage screens may import lib/app/router/; '
        'navigate through AppNavigator (lib/ui/navigation/app_navigator.dart).',
    severity: DiagnosticSeverity.ERROR,
  );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    registry.addCompilationUnit(this, _Visitor(this, context));
  }
}

const _routerPackagePrefix = 'package:tentura/app/router/';

final class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule, this.context);

  final NoRouterImportOutsideApp rule;
  final RuleContext context;

  @override
  void visitCompilationUnit(CompilationUnit node) {
    final path = context.definingUnit.file.path.replaceAll(r'\', '/');
    final libIndex = path.lastIndexOf('/lib/');
    if (libIndex == -1) {
      return;
    }
    final libRoot = path.substring(0, libIndex + '/lib/'.length);
    if (path.startsWith('${libRoot}app/')) {
      return;
    }
    if (_declaresRoutePage(node)) {
      return;
    }
    for (final d in node.directives) {
      if (d is! NamespaceDirective) {
        continue;
      }
      final uri = d.uri.stringValue;
      if (uri == null) {
        continue;
      }
      if (_targetsRouter(uri, from: path, libRoot: libRoot)) {
        rule.reportAtNode(d);
      }
    }
  }

  static bool _targetsRouter(
    String uri, {
    required String from,
    required String libRoot,
  }) {
    if (uri.startsWith(_routerPackagePrefix)) {
      return true;
    }
    if (uri.contains(':')) {
      return false;
    }
    return _resolveRelative(from, uri).startsWith('${libRoot}app/router/');
  }

  /// [uri] (relative, `/`-separated) resolved against the file at [from].
  static String _resolveRelative(String from, String uri) {
    final segments = from.split('/')..removeLast();
    for (final segment in uri.split('/')) {
      if (segment == '..') {
        if (segments.isNotEmpty) segments.removeLast();
      } else if (segment != '.' && segment.isNotEmpty) {
        segments.add(segment);
      }
    }
    return segments.join('/');
  }

  static bool _declaresRoutePage(CompilationUnit node) {
    for (final declaration in node.declarations) {
      for (final annotation in declaration.metadata) {
        if (annotation.name.name == 'RoutePage') {
          return true;
        }
      }
    }
    return false;
  }
}
