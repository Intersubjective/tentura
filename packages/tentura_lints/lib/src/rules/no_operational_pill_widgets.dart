import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/listener.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';

const _bannedM3 = {
  'Chip',
  'ChoiceChip',
  'FilterChip',
  'InputChip',
  'ActionChip',
  'RawChip',
  'Badge',
  'SegmentedButton',
};

/// Forbids pill/chip/segmented Material widgets in beacon detail UI (use design-system primitives).
final class NoOperationalPillWidgetsInBeaconView extends DartLintRule {
  const NoOperationalPillWidgetsInBeaconView() : super(code: _code);

  static const _code = LintCode(
    name: 'no_operational_pill_widgets_in_beacon_view',
    problemMessage:
        'Do not use Chip/Badge/SegmentedButton in beacon_view. '
        'Use TenturaStatusText, TenturaTypeLabel, or TenturaUnderlineTabs.',
  );

  @override
  void run(
    CustomLintResolver resolver,
    DiagnosticReporter reporter,
    CustomLintContext context,
  ) {
    final p = resolver.path;
    if (!p.contains('packages/client/lib/features/beacon_view/')) return;
    if (p.contains('/test/')) return;
    // Dialogs may use Material pickers (e.g. help type); status surfaces are widget/ + screen/.
    if (p.contains('/dialog/')) return;
    context.registry.addCompilationUnit((unit) {
      unit.accept(_Visitor(reporter, _code));
    });
  }
}

class _Visitor extends RecursiveAstVisitor<void> {
  _Visitor(this._reporter, this._code);

  final DiagnosticReporter _reporter;
  final LintCode _code;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    // `NamedType.name2` is the supported accessor for the identifier in this analyzer.
    // ignore: deprecated_member_use
    final t = node.constructorName.type.name2.lexeme;
    if (_bannedM3.contains(t)) {
      _reporter.atNode(node.constructorName, _code);
    }
    super.visitInstanceCreationExpression(node);
  }
}
