import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/error/error.dart';

import '../rule_helpers.dart';

/// Domain use_case public APIs must not return untyped maps or dynamic.
final class NoMapDynamicInUseCaseApi extends AnalysisRule {
  NoMapDynamicInUseCaseApi()
    : super(
        name: 'no_map_dynamic_in_use_case_api',
        description:
            'Domain use_case public API must return a typed DTO/entity, not '
            'Map<String, dynamic>/dynamic.',
      );

  static const LintCode code = LintCode(
    'no_map_dynamic_in_use_case_api',
    'Domain use_case public API must return a typed DTO/entity, not '
    'Map<String, dynamic>/dynamic (see docs/future-arch-improvements.md Phase B).',
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

final class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule, this.context);

  final NoMapDynamicInUseCaseApi rule;
  final RuleContext context;

  @override
  void visitCompilationUnit(CompilationUnit node) {
    if (!filePathContains(context, '/lib/domain/use_case/')) {
      return;
    }
    for (final decl in node.declarations) {
      if (decl is ClassDeclaration) {
        _checkClassLike(decl.body.members);
      } else if (decl is MixinDeclaration) {
        _checkClassLike(decl.body.members);
      } else if (decl is ExtensionDeclaration) {
        _checkClassLike(decl.body.members);
      } else if (decl is FunctionDeclaration) {
        _checkTopLevelFunction(decl);
      }
    }
  }

  void _checkClassLike(NodeList<ClassMember> members) {
    for (final member in members) {
      if (member is! MethodDeclaration) {
        continue;
      }
      if (member.operatorKeyword != null) {
        continue;
      }
      if (member.isSetter) {
        continue;
      }
      if (member.name.lexeme.startsWith('_')) {
        continue;
      }

      final fragment = member.declaredFragment;
      if (fragment == null) {
        continue;
      }
      final element = fragment.element;
      if (element.isPrivate) {
        continue;
      }

      final returnType = element.returnType;
      if (!_hasDisallowedShape(returnType)) {
        continue;
      }

      rule.reportAtNode(member);
    }
  }

  void _checkTopLevelFunction(FunctionDeclaration decl) {
    if (decl.name.lexeme.startsWith('_')) {
      return;
    }
    final fragment = decl.declaredFragment;
    if (fragment == null) {
      return;
    }
    final element = fragment.element;
    if (element.isPrivate) {
      return;
    }
    if (!_hasDisallowedShape(element.returnType)) {
      return;
    }
    rule.reportAtNode(decl);
  }
}

bool _hasDisallowedShape(DartType type) => _walk(type);

bool _walk(DartType type) {
  if (type is DynamicType) {
    return true;
  }
  if (type is! InterfaceType) {
    return false;
  }

  if (_isCoreMap(type)) {
    final args = type.typeArguments;
    if (args.length >= 2 && args[0].isDartCoreString) {
      final value = args[1];
      if (value is DynamicType) {
        return true;
      }
      if (_isDartCoreObjectLike(value)) {
        return true;
      }
      if (_walk(value)) {
        return true;
      }
    }
  }

  if (_isFutureOrStream(type) && type.typeArguments.isNotEmpty) {
    return _walk(type.typeArguments.first);
  }
  if (_isCoreListOrIterable(type) && type.typeArguments.isNotEmpty) {
    return _walk(type.typeArguments.first);
  }

  return false;
}

bool _isCoreMap(InterfaceType type) => type.isDartCoreMap;

bool _isDartCoreObjectLike(DartType type) {
  if (type is! InterfaceType) {
    return false;
  }
  return type.isDartCoreObject;
}

bool _isFutureOrStream(InterfaceType type) {
  final name = type.element.name;
  if (name != 'Future' && name != 'FutureOr' && name != 'Stream') {
    return false;
  }
  final uri = type.element.library.uri;
  return uri.isScheme('dart') && uri.path == 'async';
}

bool _isCoreListOrIterable(InterfaceType type) {
  final name = type.element.name;
  if (name != 'List' && name != 'Iterable') {
    return false;
  }
  return type.element.library.isDartCore;
}
