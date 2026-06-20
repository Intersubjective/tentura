import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

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

/// Forbids pill/chip/segmented Material widgets in beacon detail UI.
final class NoOperationalPillWidgetsInBeaconView extends AnalysisRule {
  NoOperationalPillWidgetsInBeaconView()
    : super(
        name: 'no_operational_pill_widgets_in_beacon_view',
        description:
            'Do not use Chip/Badge/SegmentedButton in beacon_view operational UI.',
      );

  static const LintCode code = LintCode(
    'no_operational_pill_widgets_in_beacon_view',
    'Do not use Chip/Badge/SegmentedButton in beacon_view. '
    'Use TenturaStatusText, TenturaTypeLabel, or TenturaUnderlineTabs.',
  );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    registry.addInstanceCreationExpression(this, _Visitor(this, context));
  }
}

final class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule, this.context);

  final NoOperationalPillWidgetsInBeaconView rule;
  final RuleContext context;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final p = context.definingUnit.file.path;
    if (!p.contains('packages/client/lib/features/beacon_view/')) {
      return;
    }
    if (p.contains('/test/')) {
      return;
    }
    if (p.contains('/dialog/')) {
      return;
    }
    final t = node.constructorName.type.name.lexeme;
    if (_bannedM3.contains(t)) {
      rule.reportAtNode(node.constructorName);
    }
    super.visitInstanceCreationExpression(node);
  }
}
