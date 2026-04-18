import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/error/error.dart' hide LintCode;
import 'package:analyzer/error/listener.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';

/// When a Cubit takes more than one repository, it must also take a `*Case`.
final class CubitRequiresUseCaseForMultiRepos extends DartLintRule {
  const CubitRequiresUseCaseForMultiRepos() : super(code: _code);

  static const _code = LintCode(
    name: 'cubit_requires_use_case_for_multi_repos',
    problemMessage:
        'Cubits injecting more than one repository must orchestrate them through '
        'a *Case (use_case). Direct multi-repo cubits violate the domain boundary.',
    // LintCode (custom_lint_core) still requires ErrorSeverity until upstream migrates.
    // ignore: deprecated_member_use
    errorSeverity: ErrorSeverity.ERROR,
  );

  @override
  void run(
    CustomLintResolver resolver,
    DiagnosticReporter reporter,
    CustomLintContext context,
  ) {
    final path = resolver.path;
    if (!path.contains('packages/client/') ||
        !path.contains('/ui/bloc/') ||
        !path.endsWith('_cubit.dart')) {
      return;
    }

    context.registry.addCompilationUnit((unit) {
      for (final decl in unit.declarations) {
        if (decl is! ClassDeclaration) continue;
        if (!_extendsCubit(decl)) continue;

        for (final member in decl.members) {
          if (member is! ConstructorDeclaration) continue;
          if (member.factoryKeyword != null) continue;
          if (member.redirectedConstructor != null) continue;
          if (member.name?.lexeme.startsWith('_') == true) {
            continue;
          }

          final repos = _repositoryParamCount(member.parameters);
          if (repos < 2) continue;
          if (_hasCaseParam(member.parameters)) continue;

          reporter.atNode(member, _code);
        }
      }
    });
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
    final inner = p is DefaultFormalParameter ? p.parameter : p;
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
