import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/error/error.dart' hide LintCode;
import 'package:analyzer/error/listener.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';

/// Domain use_case public APIs must not return untyped maps or dynamic.
final class NoMapDynamicInUseCaseApi extends DartLintRule {
  const NoMapDynamicInUseCaseApi() : super(code: _code);

  static const _code = LintCode(
    name: 'no_map_dynamic_in_use_case_api',
    problemMessage:
        'Domain use_case public API must return a typed DTO/entity, not '
        'Map<String, dynamic>/dynamic (see docs/future-arch-improvements.md Phase B).',
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
    if (!path.contains('/lib/domain/use_case/')) return;

    context.registry.addCompilationUnit((unit) {
      for (final decl in unit.declarations) {
        if (decl is ClassDeclaration) {
          _checkClassLike(decl.members, reporter);
        } else if (decl is MixinDeclaration) {
          _checkClassLike(decl.members, reporter);
        } else if (decl is ExtensionDeclaration) {
          _checkClassLike(decl.members, reporter);
        } else if (decl is FunctionDeclaration) {
          _checkTopLevelFunction(decl, reporter);
        }
      }
    });
  }

  void _checkClassLike(NodeList<ClassMember> members, DiagnosticReporter reporter) {
    for (final member in members) {
      if (member is! MethodDeclaration) continue;
      if (member.operatorKeyword != null) continue;
      if (member.isSetter) continue;
      if (member.name.lexeme.startsWith('_')) continue;

      final fragment = member.declaredFragment;
      if (fragment == null) continue;
      final element = fragment.element;
      if (element.isPrivate) continue;

      final returnType = element.returnType;
      if (!_hasDisallowedShape(returnType)) continue;

      reporter.atNode(member, _code);
    }
  }

  void _checkTopLevelFunction(
    FunctionDeclaration decl,
    DiagnosticReporter reporter,
  ) {
    if (decl.name.lexeme.startsWith('_')) return;
    final fragment = decl.declaredFragment;
    if (fragment == null) return;
    final element = fragment.element;
    if (element.isPrivate) return;
    if (!_hasDisallowedShape(element.returnType)) return;
    reporter.atNode(decl, _code);
  }
}

bool _hasDisallowedShape(DartType type) {
  return _walk(type);
}

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
