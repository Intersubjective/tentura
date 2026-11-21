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

const _testSupportRepositories = {
  'band_candidate': ('BandCandidateRepository', 'BandCandidatePort'),
  'beacon_member_webs': (
    'BeaconMemberWebsRepository',
    'BeaconMemberWebsRepositoryPort',
  ),
  'beacon': ('BeaconRepository', 'BeaconRepositoryPort'),
  'capability_cell': ('CapabilityCellRepository', 'CapabilityCellPort'),
  'capability_evidence': (
    'CapabilityEvidenceRepository',
    'CapabilityEvidencePort',
  ),
  'capability_own_evidence': (
    'CapabilityOwnEvidenceRepository',
    'CapabilityOwnEvidencePort',
  ),
  'capability_telemetry': (
    'CapabilityTelemetryRepository',
    'CapabilityTelemetryPort',
  ),
  'closure': ('ClosureRepository', 'ClosureRepositoryPort'),
  'commitment': ('CommitmentRepository', 'CommitmentRepositoryPort'),
  'complaint': ('ComplaintRepository', 'ComplaintRepositoryPort'),
  'constellation_field': (
    'ConstellationFieldRepository',
    'ConstellationFieldRepositoryPort',
  ),
  'constellation_field_requests': (
    'ConstellationFieldRequestsRepository',
    'ConstellationFieldRequestsPort',
  ),
  'constellation_mutual_trust': (
    'ConstellationMutualTrustRepository',
    'ConstellationMutualTrustPort',
  ),
  'constellation_trust_chain': (
    'ConstellationTrustChainRepository',
    'ConstellationTrustChainPort',
  ),
};

// Remove the corresponding path when moving each remaining test registration.
const _unmoved = {
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
  group('Repository mocks owned by test support', () {
    final mockFiles = {
      for (final name in _testSupportRepositories.keys)
        '${name}_repository_mock.dart',
    };

    test('the mocks and their callers use test-support paths', () {
      final oldPaths = {
        for (final name in mockFiles) '$_legacyMockDirectory/$name',
      };
      final legacyImports = {
        for (final name in mockFiles)
          'package:tentura_server/data/repository/mock/$name',
      };
      final staleImports = [
        for (final root in ['lib', 'bin', 'test'])
          for (final file in _dartFiles(root))
            if (file.readAsStringSync().contains(
              'package:tentura_server/data/repository/mock/',
            ))
              for (final directive in _parse(
                file,
              ).directives.whereType<ImportDirective>())
                if (legacyImports.contains(directive.uri.stringValue))
                  '${file.path}: ${directive.uri.stringValue}',
      ];

      final callers = {
        'test/domain/use_case/leave_in_wrapping_up_test.dart': {
          'closure_repository_mock.dart',
        },
        'test/data/repository/beacon_repository_mock_cover_thumb_test.dart': {
          'beacon_repository_mock.dart',
        },
        'test/support/test_dependency_graph_expectations.dart': mockFiles,
      };
      final missingImports = <String>[];
      for (final MapEntry(key: path, value: names) in callers.entries) {
        final file = File(path);
        final imports = _parse(file).directives
            .whereType<ImportDirective>()
            .map((directive) => directive.uri.stringValue)
            .whereType<String>()
            .map(file.absolute.uri.resolve)
            .toSet();
        missingImports.addAll(
          names
              .where(
                (name) => !imports.contains(
                  File('$_mockDirectory/$name').absolute.uri,
                ),
              )
              .map((name) => '$path: $_mockDirectory/$name'),
        );
      }

      final violations = <String, Iterable<String>>{
        'missing test-support imports': missingImports,
        'missing test-support files': [
          for (final name in mockFiles)
            if (!File('$_mockDirectory/$name').existsSync()) name,
        ],
        'files still under lib': [
          for (final path in oldPaths)
            if (File(path).existsSync()) path,
        ],
        'obsolete allowlist entries': _unmoved.intersection(oldPaths),
        'legacy package imports': staleImports,
      }..removeWhere((_, findings) => findings.isEmpty);
      expect(violations, isEmpty);
    });

    test('the application graph keeps the dev and prod repositories', () {
      final file = File('lib/app/di.config.dart');
      final graph = _GeneratedGraph(file);
      final code = file.readAsStringSync();
      for (final (implementation, port) in _testSupportRepositories.values) {
        final bindings = graph.bindings.where(
          (binding) =>
              _typeName(binding) == port &&
              _implementation(binding)?.group(2) == implementation,
        );
        expect(bindings, hasLength(1), reason: port);
        expect(
          graph.environments(bindings.single),
          unorderedEquals(['dev', 'prod']),
          reason: port,
        );
      }
      final mockReferences = [
        for (final (implementation, _) in _testSupportRepositories.values)
          if (code.contains('${implementation}Mock')) '${implementation}Mock',
        for (final name in mockFiles)
          if (code.contains('data/repository/mock/$name')) name,
      ];
      expect(mockReferences, isEmpty);
    });

    test('the test initializer binds each mock to its test-only port', () {
      final graph = _GeneratedGraph(File('test/support/test_di.config.dart'));
      expect(
        graph.bindings.map(_typeName),
        containsAll(_testSupportRepositories.values.map((entry) => entry.$2)),
      );

      for (final MapEntry(key: name, value: (implementation, port))
          in _testSupportRepositories.entries) {
        final className = '${implementation}Mock';
        final bindings = graph.bindings.where(
          (binding) =>
              _typeName(binding) == port &&
              _implementation(binding)?.group(2) == className,
        );
        expect(bindings, hasLength(1), reason: port);
        final binding = bindings.single;
        expect(
          graph.environments(binding),
          unorderedEquals(['test']),
          reason: port,
        );
        final source = File('$_mockDirectory/${name}_repository_mock.dart');
        expect(
          graph
              .implementationFile(_implementation(binding)!.group(1)!)
              ?.absolute
              .uri,
          source.absolute.uri,
          reason: className,
        );

        final mock = _parse(source).declarations
            .whereType<ClassDeclaration>()
            .singleWhere(
              (declaration) =>
                  declaration.namePart.typeName.lexeme == className,
            );
        expect(
          mock.implementsClause?.interfaces.map((type) => type.name.lexeme),
          contains(port),
          reason: className,
        );
        final annotationName = name == 'closure'
            ? 'LazySingleton'
            : 'Injectable';
        expect(
          mock.metadata.where(
            (annotation) =>
                _annotationName(annotation) == annotationName &&
                _argument(annotation.arguments, 'as')?.toSource() == port &&
                _testOnly(annotation) &&
                _argument(annotation.arguments, 'order')?.toSource() == '1',
          ),
          hasLength(1),
          reason: '$className must preserve its registration annotation.',
        );
      }
    });
  });

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
