import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/error/error.dart';

import '../rule_helpers.dart';

/// When a Cubit takes more than one repository, it must also take a `*Case`.
final class CubitRequiresUseCaseForMultiRepos extends AnalysisRule {
  CubitRequiresUseCaseForMultiRepos()
    : super(
        name: 'cubit_requires_use_case_for_multi_repos',
        description:
            'Cubits injecting more than one repository must orchestrate via a *Case.',
      );

  static const LintCode code = LintCode(
    'cubit_requires_use_case_for_multi_repos',
    'Cubits injecting more than one repository must orchestrate them through '
    'a *Case (use_case). Direct multi-repo cubits violate the domain boundary.',
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

  final CubitRequiresUseCaseForMultiRepos rule;
  final RuleContext context;

  @override
  void visitCompilationUnit(CompilationUnit node) {
    final path = context.definingUnit.file.path;
    if (!path.contains('packages/client/') ||
        !path.contains('/ui/bloc/') ||
        !path.endsWith('_cubit.dart')) {
      return;
    }

    for (final decl in node.declarations) {
      if (decl is! ClassDeclaration) {
        continue;
      }
      if (!_extendsCubit(decl)) {
        continue;
      }

      for (final member in decl.members) {
        if (member is! ConstructorDeclaration) {
          continue;
        }
        if (member.factoryKeyword != null) {
          continue;
        }
        if (member.redirectedConstructor != null) {
          continue;
        }
        if (member.name?.lexeme.startsWith('_') == true) {
          continue;
        }

        final repos = _repositoryParamCount(member.parameters);
        if (repos < 2) {
          continue;
        }
        if (_hasCaseParam(member.parameters)) {
          continue;
        }

        rule.reportAtNode(member);
      }
    }
  }

  static bool _extendsCubit(ClassDeclaration decl) {
    final ext = decl.extendsClause?.superclass;
    if (ext is! NamedType) {
      return false;
    }
    return ext.name.lexeme == 'Cubit';
  }

  static int _repositoryParamCount(FormalParameterList? list) {
    if (list == null) {
      return 0;
    }
    var n = 0;
    for (final p in list.parameters) {
      final type = _parameterType(p);
      if (type != null && _isRepositoryType(type)) {
        n++;
      }
    }
    return n;
  }

  static bool _hasCaseParam(FormalParameterList? list) {
    if (list == null) {
      return false;
    }
    for (final p in list.parameters) {
      final type = _parameterType(p);
      if (type != null && _isCaseType(type)) {
        return true;
      }
    }
    return false;
  }

  static DartType? _parameterType(FormalParameter p) {
    final inner = unwrapFormalParameter(p);
    return inner.declaredFragment?.element.type;
  }

  static bool _isRepositoryType(DartType type) {
    if (type is! InterfaceType) {
      return false;
    }
    final name = type.element.name ?? '';
    return name.endsWith('Repository') || name.endsWith('RepositoryPort');
  }

  static bool _isCaseType(DartType type) {
    if (type is! InterfaceType) {
      return false;
    }
    final name = type.element.name ?? '';
    return name.endsWith('Case');
  }
}
