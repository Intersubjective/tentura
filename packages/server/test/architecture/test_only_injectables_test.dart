// The analyzer is reachable transitively through build_runner.
// ignore_for_file: depend_on_referenced_packages

import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:test/test.dart';

const _legacyMockDirectory = 'lib/data/repository/mock';
const _mockFileName = 'user_trust_edge_repository_mock.dart';
const _mockClass = 'UserTrustEdgeRepositoryMock';
const _repositoryPort = 'UserTrustEdgeRepositoryPort';
const _mockDirectory = 'test/support/mocks';

// Remove the corresponding path when moving each remaining test registration.
const _unmoved = {
  '$_legacyMockDirectory/band_candidate_repository_mock.dart',
  '$_legacyMockDirectory/beacon_member_webs_repository_mock.dart',
  '$_legacyMockDirectory/beacon_repository_mock.dart',
  '$_legacyMockDirectory/capability_cell_repository_mock.dart',
  '$_legacyMockDirectory/capability_evidence_repository_mock.dart',
  '$_legacyMockDirectory/capability_own_evidence_repository_mock.dart',
  '$_legacyMockDirectory/capability_telemetry_repository_mock.dart',
  '$_legacyMockDirectory/closure_repository_mock.dart',
  '$_legacyMockDirectory/commitment_repository_mock.dart',
  '$_legacyMockDirectory/complaint_repository_mock.dart',
  '$_legacyMockDirectory/constellation_field_repository_mock.dart',
  '$_legacyMockDirectory/constellation_field_requests_repository_mock.dart',
  '$_legacyMockDirectory/constellation_mutual_trust_repository_mock.dart',
  '$_legacyMockDirectory/constellation_trust_chain_repository_mock.dart',
  '$_legacyMockDirectory/coordination_repository_mock.dart',
  '$_legacyMockDirectory/fcm_remote_repository_mock.dart',
  '$_legacyMockDirectory/fcm_token_repository_mock.dart',
  '$_legacyMockDirectory/forward_attribution_repository_mock.dart',
  '$_legacyMockDirectory/forward_candidate_context_repository_mock.dart',
  '$_legacyMockDirectory/forward_edge_repository_mock.dart',
  '$_legacyMockDirectory/help_offer_admission_repository_mock.dart',
  '$_legacyMockDirectory/help_offer_repository_mock.dart',
  '$_legacyMockDirectory/image_object_gc_repository_mock.dart',
  '$_legacyMockDirectory/image_repository_mock.dart',
  '$_legacyMockDirectory/inbox_repository_mock.dart',
  '$_legacyMockDirectory/invitation_repository_mock.dart',
  '$_legacyMockDirectory/invite_genealogy_repository_mock.dart',
  '$_legacyMockDirectory/invite_seed_prompt_repository_mock.dart',
  '$_legacyMockDirectory/lineage_memory_read_repository_mock.dart',
  '$_legacyMockDirectory/meritrank_repository_mock.dart',
  '$_legacyMockDirectory/meritrank_status_repository_mock.dart',
  '$_legacyMockDirectory/mutual_friends_repository_mock.dart',
  '$_legacyMockDirectory/pair_block_query_repository_mock.dart',
  '$_legacyMockDirectory/people_tags_repository_mock.dart',
  '$_legacyMockDirectory/person_capability_event_repository_mock.dart',
  '$_legacyMockDirectory/polling_act_repository_mock.dart',
  '$_legacyMockDirectory/polling_repository_mock.dart',
  '$_legacyMockDirectory/routing_mute_repository_mock.dart',
  '$_legacyMockDirectory/task_repository_mock.dart',
  '$_legacyMockDirectory/trust_ledger_repository_mock.dart',
  '$_legacyMockDirectory/trust_preference_repository_mock.dart',
  '$_legacyMockDirectory/upload_quota_repository_mock.dart',
  '$_legacyMockDirectory/user_availability_repository_mock.dart',
  '$_legacyMockDirectory/user_block_repository_mock.dart',
  '$_legacyMockDirectory/user_contact_repository_mock.dart',
  '$_legacyMockDirectory/user_presence_repository_mock.dart',
  '$_legacyMockDirectory/user_repository_mock.dart',
  '$_legacyMockDirectory/witness_window_repository_mock.dart',
  'lib/data/service/email/logging_email_sender.dart',
};

void main() {
  test('new test-only injectable registrations stay outside lib', () {
    final offenders = <String>[];
    for (final file in _dartFiles('lib')) {
      final annotations = _TestOnlyAnnotations();
      _parse(file).accept(annotations);
      if (annotations.found && !_unmoved.contains(file.path)) {
        offenders.add(file.path);
      }
    }

    expect(
      offenders..sort(),
      isEmpty,
      reason: 'Move these test-only injectable registrations to test/support.',
    );
  });

  test(
    'the application graph keeps the real trust-edge binding in dev and prod',
    () {
      final applicationConfig = File('lib/app/di.config.dart');
      final code = applicationConfig.readAsStringSync();
      final graph = _GeneratedGraph(applicationConfig);
      final bindings = graph.bindings.where(
        (binding) =>
            _typeName(binding) == _repositoryPort &&
            _implementation(binding)?.group(2) == 'UserTrustEdgeRepository',
      );
      expect(bindings, hasLength(1));
      expect(
        graph.environments(bindings.single),
        unorderedEquals(['dev', 'prod']),
      );
      expect(
        code.contains(_mockClass),
        isFalse,
        reason: '${applicationConfig.path} still references $_mockClass.',
      );
      expect(
        File('$_legacyMockDirectory/$_mockFileName').existsSync(),
        isFalse,
      );
      final staleImports = [
        for (final file in _dartFiles('lib'))
          if (_parse(file).directives.whereType<ImportDirective>().any(
            (directive) =>
                directive.uri.stringValue?.split('/').last == _mockFileName,
          ))
            file.path,
      ];
      expect(
        staleImports,
        isEmpty,
        reason: 'Remove lib imports of the moved mock.',
      );
    },
  );

  test(
    'the test initializer generates registrations only for test-support mocks',
    () {
      final initializers = [
        for (final file in _dartFiles('test/support'))
          for (final declaration in _parse(
            file,
          ).declarations.whereType<FunctionDeclaration>())
            for (final annotation in declaration.metadata)
              if (_annotationName(annotation) == 'InjectableInit')
                (file, annotation),
      ];
      expect(
        initializers,
        hasLength(1),
        reason: 'Test support needs its own @InjectableInit function.',
      );

      final (initializerFile, annotation) = initializers.single;
      final name = _argument(annotation.arguments, 'initializerName');
      expect(name, isA<StringLiteral>());
      expect(
        (name! as StringLiteral).stringValue,
        allOf(isNotEmpty, isNot('init')),
      );

      final configFile = File(
        initializerFile.path.replaceFirst(RegExp(r'\.dart$'), '.config.dart'),
      );
      expect(
        configFile.existsSync(),
        isTrue,
        reason: 'Generate ${configFile.path}.',
      );
      final graph = _GeneratedGraph(configFile);
      final implementations = <(String?, String)>[];
      for (final binding in graph.bindings) {
        final constructor = _implementation(binding);
        expect(constructor, isNotNull, reason: binding.toSource());
        final source = graph.implementationFile(constructor!.group(1)!);
        expect(
          source?.absolute.path,
          startsWith('${Directory(_mockDirectory).absolute.path}/'),
          reason: '${binding.toSource()} must construct a test-support mock.',
        );
        final className = constructor.group(2)!;
        expect(
          _parse(source!).declarations.whereType<ClassDeclaration>().map(
            (declaration) => declaration.namePart.typeName.lexeme,
          ),
          contains(className),
          reason: '${source.path} must declare $className.',
        );
        if (className == _mockClass) {
          expect(
            source.absolute.path,
            File('$_mockDirectory/$_mockFileName').absolute.path,
          );
          expect(_typeName(binding), _repositoryPort);
          expect(graph.environments(binding), unorderedEquals(['test']));
        }
        implementations.add((_typeName(binding), className));
      }
      expect(implementations, contains((_repositoryPort, _mockClass)));

      final mock = _parse(File('$_mockDirectory/$_mockFileName')).declarations
          .whereType<ClassDeclaration>()
          .singleWhere(
            (declaration) => declaration.namePart.typeName.lexeme == _mockClass,
          );
      expect(
        mock.implementsClause?.interfaces.map((type) => type.name.lexeme),
        contains(_repositoryPort),
      );
      final registrations = mock.metadata.where(
        (annotation) =>
            _annotationName(annotation) == 'Injectable' &&
            _argument(annotation.arguments, 'as')?.toSource() ==
                _repositoryPort &&
            _testOnly(annotation),
      );
      expect(
        registrations,
        hasLength(1),
        reason: 'Keep the mock’s test-only port annotation.',
      );
    },
  );
}

Iterable<File> _dartFiles(String directory) => Directory(directory)
    .listSync(recursive: true)
    .whereType<File>()
    .where((file) => file.path.endsWith('.dart'));

CompilationUnit _parse(File file) =>
    parseString(path: file.path, content: file.readAsStringSync()).unit;

String _annotationName(Annotation annotation) =>
    annotation.name.name.split('.').last;

Expression? _argument(ArgumentList? arguments, String name) {
  for (final argument
      in arguments?.arguments.whereType<NamedArgument>() ??
          const <NamedArgument>[]) {
    if (argument.name.lexeme == name) return argument.argumentExpression;
  }
  return null;
}

bool _testOnly(Annotation annotation) {
  final env = _argument(annotation.arguments, 'env');
  if (env is! ListLiteral || env.elements.length != 1) return false;
  final name = env.elements.single.toSource();
  return name == 'Environment.test' || name.endsWith('.Environment.test');
}

class _TestOnlyAnnotations extends RecursiveAstVisitor<void> {
  bool found = false;

  @override
  void visitAnnotation(Annotation node) {
    if (const {
          'Injectable',
          'Singleton',
          'LazySingleton',
        }.contains(_annotationName(node)) &&
        _testOnly(node)) {
      found = true;
    }
    super.visitAnnotation(node);
  }
}

String? _typeName(MethodInvocation binding) {
  final arguments = binding.typeArguments?.arguments;
  if (arguments == null || arguments.length != 1) return null;
  final type = arguments.single;
  return type is NamedType ? type.name.lexeme : null;
}

final _constructor = RegExp(
  r'^(?:(?:const|new)\s+)?(\w+)\.(\w+)(?:\.\w+)?\s*\(',
);

RegExpMatch? _implementation(MethodInvocation binding) {
  final factory = binding.argumentList.arguments.firstOrNull;
  if (factory is! FunctionExpression) return null;
  final body = factory.body;
  if (body is! ExpressionFunctionBody) return null;
  return _constructor.firstMatch(body.expression.toSource());
}

class _GeneratedGraph extends RecursiveAstVisitor<void> {
  _GeneratedGraph(this.file) : unit = _parse(file) {
    unit.accept(this);
  }

  final File file;
  final CompilationUnit unit;
  final bindings = <MethodInvocation>[];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.target?.toSource() == 'gh' && node.typeArguments != null) {
      bindings.add(node);
    }
    super.visitMethodInvocation(node);
  }

  Iterable<String?> environments(MethodInvocation binding) {
    final constants = {
      for (final declaration
          in unit.declarations.whereType<TopLevelVariableDeclaration>())
        for (final variable in declaration.variables.variables)
          if (variable.initializer case final StringLiteral value)
            variable.name.lexeme: value.stringValue,
    };
    final env = _argument(binding.argumentList, 'registerFor');
    return switch (env) {
      SetOrMapLiteral() => env.elements.map(
        (element) => element is StringLiteral
            ? element.stringValue
            : constants[element.toSource()],
      ),
      _ => const [],
    };
  }

  File? implementationFile(String prefix) {
    for (final directive in unit.directives.whereType<ImportDirective>()) {
      if (directive.prefix?.name != prefix) continue;
      final path = directive.uri.stringValue!;
      const package = 'package:tentura_server/';
      if (path.startsWith(package)) {
        return File.fromUri(
          Directory('lib').absolute.uri.resolve(path.substring(package.length)),
        );
      }
      final uri = file.absolute.uri.resolve(path);
      return uri.scheme == 'file' ? File.fromUri(uri) : null;
    }
    return null;
  }
}
