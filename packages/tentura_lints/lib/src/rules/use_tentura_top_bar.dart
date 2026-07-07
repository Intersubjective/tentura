import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

/// Requires feature/shared UI app bars to use the Tentura design-system
/// primitive, except for immersive overlay surfaces that intentionally draw
/// transparent or black app bars over media/camera/map content.
final class UseTenturaTopBar extends AnalysisRule {
  UseTenturaTopBar()
    : super(
        name: 'use_tentura_top_bar',
        description:
            'Use TenturaTopBar for feature / shared UI app bars; raw AppBar '
            'and SliverAppBar are allowed only for immersive overlays.',
      );

  static const LintCode code = LintCode(
    'use_tentura_top_bar',
    'Use TenturaTopBar.of instead of raw AppBar/SliverAppBar in client '
        'feature and shared UI.',
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

const _targets = {'AppBar', 'SliverAppBar'};

const _allowedFiles = {
  '/ui/widget/beacon_gallery_viewer.dart',
  '/ui/widget/tentura_fullscreen_image_viewer.dart',
  '/features/beacon_room/ui/widget/room_attachment_widgets.dart',
  '/features/geo/ui/dialog/choose_location_dialog.dart',
  '/ui/dialog/qr_scan_dialog.dart',
};

final class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule, this.context);

  final UseTenturaTopBar rule;
  final RuleContext context;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final path = context.definingUnit.file.path;
    if (_inScope(path) &&
        _targets.contains(node.constructorName.type.name.lexeme)) {
      rule.reportAtNode(node.constructorName);
    }
    super.visitInstanceCreationExpression(node);
  }
}

bool _inScope(String path) {
  if (!path.contains('packages/client/lib/')) {
    return false;
  }
  if (path.contains('/design_system/')) {
    return false;
  }
  for (final allowed in _allowedFiles) {
    if (path.endsWith(allowed)) {
      return false;
    }
  }
  return path.contains('/features/') || path.contains('/ui/');
}
