// The analyzer is reachable transitively through build_runner.
// ignore_for_file: depend_on_referenced_packages

import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:test/test.dart';

const _legacyImportPath = 'data/repository/mock';
const _legacyMockDirectory = 'lib/$_legacyImportPath';
const _mockFileName = 'user_trust_edge_repository_mock.dart';
const _mockClass = 'UserTrustEdgeRepositoryMock';
const _repositoryPort = 'UserTrustEdgeRepositoryPort';
const _mockDirectory = 'test/support/mocks';

const _coordinationThroughInvitationRepositories = {
  'coordination': ('CoordinationRepository', 'CoordinationRepositoryPort'),
  'fcm_remote': ('FcmRemoteRepository', 'FcmRemoteRepositoryPort'),
  'fcm_token': ('FcmTokenRepository', 'FcmTokenRepositoryPort'),
  'forward_attribution': (
    'ForwardAttributionRepository',
    'ForwardAttributionRepositoryPort',
  ),
  'forward_candidate_context': (
    'ForwardCandidateContextRepository',
    'ForwardCandidateContextRepositoryPort',
  ),
  'forward_edge': ('ForwardEdgeRepository', 'ForwardEdgeRepositoryPort'),
  'help_offer_admission': (
    'HelpOfferAdmissionRepository',
    'HelpOfferAdmissionRepositoryPort',
  ),
  'help_offer': ('HelpOfferRepository', 'HelpOfferRepositoryPort'),
  'image_object_gc': ('ImageObjectGcRepository', 'ImageObjectGcPort'),
  'image': ('ImageRepository', 'ImageRepositoryPort'),
  'inbox': ('InboxRepository', 'InboxRepositoryPort'),
  'invitation': ('InvitationRepository', 'InvitationRepositoryPort'),
};

const _inviteGenealogyThroughTaskRepositories = {
  'invite_genealogy': (
    'InviteGenealogyRepository',
    'InviteGenealogyRepositoryPort',
  ),
  'lineage_memory_read': (
    'LineageMemoryReadRepository',
    'LineageMemoryReadPort',
  ),
  'meritrank': ('MeritrankRepository', 'MeritrankRepositoryPort'),
  'meritrank_status': ('MeritrankStatusRepository', 'MeritrankStatusPort'),
  'mutual_friends': ('MutualFriendsRepository', 'MutualFriendsRepositoryPort'),
  'pair_block_query': ('PairBlockQueryRepository', 'PairBlockQueryPort'),
  'people_tags': ('PeopleTagsRepository', 'PeopleTagsRepositoryPort'),
  'person_capability_event': (
    'PersonCapabilityEventRepository',
    'PersonCapabilityEventRepositoryPort',
  ),
  'polling_act': ('PollingActRepository', 'PollingActRepositoryPort'),
  'polling': ('PollingRepository', 'PollingRepositoryPort'),
  'routing_mute': ('RoutingMuteRepository', 'RoutingMutePort'),
  'task': ('TaskRepository', 'TaskRepositoryPort'),
};

const _repositoryMocksLeavingLib = {
  'invite_seed_prompt': ('InviteSeedPromptRepository', 'InviteSeedPromptPort'),
  'trust_ledger': ('TrustLedgerRepository', 'TrustLedgerPort'),
  'trust_preference': ('TrustPreferenceRepository', 'TrustPreferencePort'),
  'upload_quota': ('UploadQuotaRepository', 'UploadQuotaRepositoryPort'),
  'user_availability': (
    'UserAvailabilityRepository',
    'UserAvailabilityRepositoryPort',
  ),
  'user_block': ('UserBlockRepository', 'UserBlockRepositoryPort'),
  'user_contact': ('UserContactRepository', 'UserContactRepositoryPort'),
  'user_presence': ('UserPresenceRepository', 'UserPresenceRepositoryPort'),
  'user': ('UserRepository', 'UserRepositoryPort'),
  'witness_window': ('WitnessWindowRepository', 'WitnessWindowPort'),
};

const _testSupportRepositories = {
  ..._coordinationThroughInvitationRepositories,
  ..._inviteGenealogyThroughTaskRepositories,
  ..._repositoryMocksLeavingLib,
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
      final mockUris = {
        for (final name in mockFiles)
          name: File('$_mockDirectory/$name').absolute.uri,
      };
      final staleReferences = <String>[];
      final misplacedImports = <String>[];
      for (final root in ['lib', 'bin', 'test']) {
        for (final file in _dartFiles(root)) {
          final code = file.readAsStringSync();
          if (code.contains('$_legacyImportPath/')) {
            staleReferences.add(file.path);
          }
          if (!mockFiles.any(code.contains)) continue;
          for (final uri in _imports(file)) {
            final expected = mockUris[uri.pathSegments.lastOrNull];
            if (expected != null && uri != expected) {
              misplacedImports.add('${file.path}: ${uri.path}');
            }
          }
        }
      }

      final callers = {
        'test/domain/use_case/leave_in_wrapping_up_test.dart': {
          'closure_repository_mock.dart',
        },
        'test/data/repository/beacon_repository_mock_cover_thumb_test.dart': {
          'beacon_repository_mock.dart',
        },
        'test/domain/use_case/request_only_guards_test.dart': {
          'pair_block_query_repository_mock.dart',
        },
        // The live graph checks these ports against the isolated test
        // initializer, so their mock classes need no direct test import.
        'test/support/test_dependency_graph_expectations.dart': {
          for (final name in _testSupportRepositories.keys)
            if (!_inviteGenealogyThroughTaskRepositories.containsKey(name) &&
                !_repositoryMocksLeavingLib.containsKey(name))
              '${name}_repository_mock.dart',
        },
      };
      final missingImports = <String>[];
      for (final MapEntry(key: path, value: names) in callers.entries) {
        final file = File(path);
        final imports = _imports(file).toSet();
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
        'obsolete lib mock directory': [
          if (Directory(_legacyMockDirectory).existsSync())
            _legacyMockDirectory,
        ],
        'legacy path references': staleReferences,
        'imports outside test support': misplacedImports,
      }..removeWhere((_, findings) => findings.isEmpty);
      expect(violations, isEmpty);
    });

    test('beacon, invitation and user callers import test-support fixtures', () {
      const fixtures = {
        'beacon': 'beacons.dart',
        'invitation': 'invitations.dart',
        'user': 'users.dart',
      };
      final legacyUris = {
        for (final fixture in fixtures.values)
          File('$_legacyMockDirectory/data/$fixture').absolute.uri,
      };
      final violations = [
        for (final uri in legacyUris)
          if (File.fromUri(uri).existsSync()) 'Legacy fixture: ${uri.path}',
        for (final MapEntry(key: mock, value: fixture) in fixtures.entries)
          ..._fixtureViolations(mock, fixture),
        if (!_imports(
          File('test/app/test_dependency_graph_pg_test.dart'),
        ).contains(File('$_mockDirectory/data/users.dart').absolute.uri))
          'The live dependency graph test must import the test-support users fixture.',
        for (final root in ['lib', 'bin', 'test'])
          for (final file in _dartFiles(root))
            if (fixtures.values.any(file.readAsStringSync().contains))
              for (final uri in _imports(file))
                if (legacyUris.contains(uri)) '${file.path}: ${uri.path}',
      ];
      expect(violations, isEmpty);
    });

    test('the application graph keeps the dev and prod repositories', () {
      final file = File('lib/app/di.config.dart');
      final graph = _GeneratedGraph(file);
      final code = file.readAsStringSync();
      final violations = <String>[];
      for (final MapEntry(key: name, value: (implementation, port))
          in _testSupportRepositories.entries) {
        final bindings = graph.bindings
            .where((binding) => _typeName(binding) == port)
            .toList();
        if (bindings.length != 1) {
          violations.add('$port has ${bindings.length} bindings');
          continue;
        }
        final binding = bindings.single;
        if (!unorderedEquals(['dev', 'prod']).matches(
          graph.environments(binding),
          {},
        )) {
          violations.add('$port registers for ${graph.environments(binding)}');
        }
        if (_coordinationThroughInvitationRepositories.containsKey(name)) {
          if (RegExp(r'\b\w*RepositoryMock\b').hasMatch(binding.toSource())) {
            violations.add('$port constructs a repository mock');
          }
        } else {
          expect(
            _implementation(binding)?.group(2),
            implementation,
            reason: port,
          );
        }
      }
      final mockReferences = [
        for (final (implementation, _) in _testSupportRepositories.values)
          if (code.contains('${implementation}Mock')) '${implementation}Mock',
        for (final name in mockFiles)
          if (code.contains('$_legacyImportPath/$name')) name,
        ...RegExp(
          r'\b\w*RepositoryMock\b',
        ).allMatches(code).map((match) => match.group(0)!).toSet(),
      ];
      final testDirectory = Directory('test').absolute.uri.path;
      final testImports = [
        for (final libFile in _dartFiles('lib'))
          if (libFile.readAsStringSync().contains('test/'))
            for (final uri in _imports(libFile))
              if (uri.path.startsWith(testDirectory))
                '${libFile.path}: ${uri.path}',
      ];
      expect([...violations, ...mockReferences, ...testImports], isEmpty);
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
          (binding) => _typeName(binding) == port,
        );
        expect(bindings, hasLength(1), reason: port);
        final binding = bindings.single;
        expect(_implementation(binding)?.group(2), className, reason: port);
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
        final annotationName = switch (name) {
          'fcm_remote' || 'trust_ledger' => 'Singleton',
          'closure' ||
          'forward_attribution' ||
          'forward_candidate_context' ||
          'task' => 'LazySingleton',
          _ => 'Injectable',
        };
        final registrations = mock.metadata.where(
          (annotation) => const {
            'Injectable',
            'Singleton',
            'LazySingleton',
            'injectable',
            'singleton',
            'lazySingleton',
          }.contains(_annotationName(annotation)),
        );
        expect(registrations, hasLength(1), reason: className);
        expect(
          registrations.where(
            (annotation) =>
                _annotationName(annotation) == annotationName &&
                _argument(annotation.arguments, 'as')?.toSource() == port &&
                _testOnly(annotation) &&
                _argument(annotation.arguments, 'order')?.toSource() ==
                    (name == 'task' ? null : '1'),
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
      if (annotations.found) {
        offenders.add(file.path);
      }
    }

    expect(
      offenders..sort(),
      isEmpty,
      reason: 'Move these test-only injectable registrations to test/support.',
    );
  });

  test('shared server test doubles are registered only by test DI', () {
    final violations = <String>[];
    if (Directory(_legacyMockDirectory).existsSync()) {
      violations.add('Obsolete mock directory: $_legacyMockDirectory');
    }
    for (final file in _dartFiles('lib')) {
      final unit = _parse(file);
      final annotations = _TestOnlyAnnotations();
      unit.accept(annotations);
      if (annotations.found) {
        violations.add('${file.path}: test-only Injectable annotation');
      }
      if (const [
        '.config.dart',
        '.freezed.dart',
        '.g.dart',
        '.gr.dart',
        '.schema.dart',
      ].any(file.path.endsWith)) {
        continue;
      }
      for (final declaration
          in unit.declarations.whereType<ClassDeclaration>()) {
        final name = declaration.namePart.typeName.lexeme;
        if ((name.endsWith('Mock') || file.path.endsWith('_mock.dart')) &&
            declaration.implementsClause != null) {
          violations.add(
            '${file.path}: $name implements a production interface',
          );
        }
      }
    }

    final config = File('lib/app/di.config.dart');
    final graph = _GeneratedGraph(config);
    final testDirectory = Directory('test').absolute.uri.path;
    for (final uri in _imports(config)) {
      if (uri.path.startsWith(testDirectory)) {
        violations.add('${config.path}: imports ${uri.path}');
      }
    }
    for (final binding in graph.bindings) {
      if (unorderedEquals(['test']).matches(graph.environments(binding), {})) {
        violations.add(
          '${config.path}: test-only binding for ${_typeName(binding)}',
        );
      }
      final implementation = _implementation(binding)?.group(2);
      if (implementation != null && implementation.endsWith('Mock')) {
        violations.add('${config.path}: registers $implementation');
      }
    }
    expect([...violations, ..._testGraphViolations()]..sort(), isEmpty);
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

List<String> _testGraphViolations() {
  const helper = 'test/support/test_di.dart';
  final mockDirectory = Directory(_mockDirectory).absolute.uri.path;
  final violations = <String>[];
  final initializerFiles = <String>[];
  for (final file in _dartFiles('test')) {
    final source = file.readAsStringSync();
    if (!source.contains('Environment') && !source.contains('InjectableInit')) {
      continue;
    }
    final annotations = _TestOnlyAnnotations();
    parseString(path: file.path, content: source).unit.accept(annotations);
    initializerFiles.addAll(List.filled(annotations.initializers, file.path));
    if (annotations.found &&
        !file.absolute.uri.path.startsWith(mockDirectory)) {
      violations.add(
        '${file.path}: test-only injectable outside test DI sources',
      );
    }
  }
  if (!orderedEquals([helper]).matches(initializerFiles, {})) {
    violations.add(
      'Expected a single test DI initializer in $helper. Found $initializerFiles',
    );
  }

  final graph = _GeneratedGraph(File('test/support/test_di.config.dart'));
  final bindings = <String?, List<String?>>{};
  for (final binding in graph.bindings) {
    final constructor = _implementation(binding);
    final localSource = constructor == null
        ? null
        : graph.implementationFile(constructor.group(1)!)?.absolute.uri.path;
    final port = _typeName(binding);
    if (localSource == null ||
        !localSource.startsWith(mockDirectory) ||
        !unorderedEquals(['test']).matches(graph.environments(binding), {})) {
      violations.add(
        '${graph.file.path}: $port must bind a test-support implementation for test only',
      );
      continue;
    }
    (bindings[port] ??= []).add(constructor?.group(2));
  }
  final expectedMocks = {
    for (final (implementation, port) in _testSupportRepositories.values)
      port: '${implementation}Mock',
    _repositoryPort: _mockClass,
  };
  for (final entry in expectedMocks.entries) {
    if (!orderedEquals([entry.value]).matches(bindings[entry.key], {})) {
      violations.add(
        '${graph.file.path}: ${entry.key} must bind ${entry.value}',
      );
    }
  }
  if (bindings['EmailSenderPort']?.length != 1) {
    violations.add(
      '${graph.file.path}: missing unique test email sender binding',
    );
  }
  return violations;
}

Iterable<File> _dartFiles(String directory) => Directory(directory)
    .listSync(recursive: true)
    .whereType<File>()
    .where((file) => file.path.endsWith('.dart'));

Iterable<String> _fixtureViolations(String mock, String fixture) sync* {
  final source = File('$_mockDirectory/${mock}_repository_mock.dart');
  final data = File('$_mockDirectory/data/$fixture');
  if (!data.existsSync()) yield 'Missing fixture: ${data.path}';
  if (!source.existsSync() || !_imports(source).contains(data.absolute.uri)) {
    yield '${source.path} must import ${data.path}';
  }
}

Iterable<Uri> _imports(File file) sync* {
  const packagePrefix = 'package:tentura_server/';
  for (final directive in _parse(
    file,
  ).directives.whereType<ImportDirective>()) {
    final paths = [
      directive.uri.stringValue,
      ...directive.configurations.map(
        (configuration) => configuration.uri.stringValue,
      ),
    ];
    for (final path in paths.whereType<String>()) {
      yield path.startsWith(packagePrefix)
          ? Directory(
              'lib',
            ).absolute.uri.resolve(path.substring(packagePrefix.length))
          : file.absolute.uri.resolve(path);
    }
  }
}

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
  int initializers = 0;

  @override
  void visitAnnotation(Annotation node) {
    if (_annotationName(node) == 'InjectableInit') initializers++;
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
