import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/domain/use_case/use_case_base.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/closure/data/repository/closure_repository.dart';
import 'package:tentura/features/closure/domain/use_case/closure_case.dart';
import 'package:tentura/features/complaint/data/repository/complaint_repository.dart';
import 'package:tentura/features/complaint/domain/use_case/complaint_case.dart';
import 'package:tentura/features/credentials/domain/use_case/credentials_case.dart';
import 'package:tentura/features/forward_candidate_context/domain/port/forward_candidate_context_repository_port.dart';
import 'package:tentura/features/forward_candidate_context/domain/use_case/load_forward_candidate_context_case.dart';
import 'package:tentura/features/profile_view/data/repository/profile_shared_beacons_repository.dart';
import 'package:tentura/features/profile_view/domain/use_case/profile_shared_beacons_case.dart';

import '../features/complaint/recording_complaint_case.dart'
    show FakeComplaintBeacons, FakeComplaintProfiles;
import '../features/credentials/credentials_case_test.dart'
    show FakeCredentialsRepository, TrackingAuthLocal;
import '../support/test_realtime_sync.dart';

class _FakeClosureRepository extends Fake implements ClosureRepository {}

class _FakeComplaintRepository extends Fake implements ComplaintRepository {}

class _FakeForwardCandidateContextRepository extends Fake
    implements ForwardCandidateContextRepositoryPort {}

class _FakeSharedBeaconsRepository extends Fake
    implements ProfileSharedBeaconsRepository {}

const _featureCases = {
  'ClosureCase',
  'ComplaintCase',
  'LoadForwardCandidateContextCase',
  'ProfileSharedBeaconsCase',
};

void main() {
  test(
    'ComplaintCase can be constructed with only its feature dependencies',
    () {
      final credentials = CredentialsCase(
        FakeCredentialsRepository(),
        TrackingAuthLocal(),
        env: const Env(),
        logger: Logger('CredentialsCaseTest'),
      );

      _expectFeatureDependenciesOnly<ComplaintCase>(ComplaintCase.new, [
        _FakeComplaintRepository(),
        credentials,
        FakeComplaintBeacons(),
        FakeComplaintProfiles(),
      ]);
    },
  );

  test(
    'ProfileSharedBeaconsCase only needs its repository and realtime sync',
    () {
      final realtime = buildTestRealtimeSync();
      addTearDown(realtime.port.dispose);

      _expectFeatureDependenciesOnly<ProfileSharedBeaconsCase>(
        ProfileSharedBeaconsCase.new,
        [_FakeSharedBeaconsRepository(), realtime.case_],
      );
    },
  );

  test('ClosureCase only needs its repository', () {
    _expectFeatureDependenciesOnly<ClosureCase>(ClosureCase.new, [
      _FakeClosureRepository(),
    ]);
  });

  test('LoadForwardCandidateContextCase only needs its repository port', () {
    _expectFeatureDependenciesOnly<LoadForwardCandidateContextCase>(
      LoadForwardCandidateContextCase.new,
      [_FakeForwardCandidateContextRepository()],
    );
  });

  test('generated DI supplies only feature dependencies to the cases', () {
    _expectFeatureOnlyCalls([File('lib/app/di/di_current.config.dart')]);
  });

  test('test callers construct the cases with only feature dependencies', () {
    final thisTest = File(
      'test/architecture/use_case_constructor_dependencies_test.dart',
    ).absolute.path;
    final sources = Directory('test')
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .where(
          (file) =>
              file.absolute.path != thisTest && file.path.endsWith('.dart'),
        );

    _expectFeatureOnlyCalls(sources);
  });
}

void _expectFeatureDependenciesOnly<T>(
  Function constructor,
  List<Object> dependencies,
) {
  // Invoke the real constructor with the desired arguments while keeping the
  // test compilable with the old signature.
  late final Object instance;
  expect(
    () => instance = Function.apply(constructor, dependencies) as Object,
    returnsNormally,
    reason: '$T must be constructible without env or logger',
  );
  expect(instance, isA<T>());
  expect(instance is UseCaseBase, isFalse);

  // Supplying either argument must also fail if it was left behind as optional.
  expect(
    () => Function.apply(constructor, dependencies, {#env: const Env()}),
    throwsNoSuchMethodError,
    reason: '$T must not accept env',
  );
  expect(
    () => Function.apply(constructor, dependencies, {#logger: Logger('test')}),
    throwsNoSuchMethodError,
    reason: '$T must not accept logger',
  );
}

void _expectFeatureOnlyCalls(Iterable<File> sources) {
  final constructedCases = <String>{};
  final violations = <String>[];
  for (final file in sources) {
    final source = file.readAsStringSync();
    if (!_featureCases.any(source.contains)) continue;

    final parsed = parseString(content: source, path: file.path);
    final visitor = _CaseConstructorCalls();
    parsed.unit.accept(visitor);
    for (final (name, arguments) in visitor.calls) {
      constructedCases.add(name);
      for (final argument in arguments.arguments.whereType<NamedArgument>()) {
        final label = argument.name.lexeme;
        if (label != 'env' && label != 'logger') continue;
        final line = parsed.lineInfo.getLocation(argument.offset).lineNumber;
        violations.add('${file.path}:$line: $name receives $label');
      }
    }
  }

  expect(
    constructedCases,
    _featureCases,
    reason: 'Every case must have a constructor call in the scanned sources',
  );
  expect(violations..sort(), isEmpty);
}

// In an unresolved syntax tree, calls without new or const can be represented
// as method invocations, including the prefixed calls in Injectable output.
class _CaseConstructorCalls extends RecursiveAstVisitor<void> {
  final calls = <(String, ArgumentList)>[];

  void _record(String name, ArgumentList arguments) {
    if (_featureCases.contains(name)) calls.add((name, arguments));
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    _record(node.methodName.name, node.argumentList);
    super.visitMethodInvocation(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    _record(node.constructorName.type.name.lexeme, node.argumentList);
    super.visitInstanceCreationExpression(node);
  }
}
