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
