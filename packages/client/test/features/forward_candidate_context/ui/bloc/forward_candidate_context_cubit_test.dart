import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/forward_candidate_context/domain/entity/candidate_connection_context.dart';
import 'package:tentura/features/forward_candidate_context/domain/port/forward_candidate_context_repository_port.dart';
import 'package:tentura/features/forward_candidate_context/domain/use_case/load_forward_candidate_context_case.dart';
import 'package:tentura/features/forward_candidate_context/ui/bloc/forward_candidate_context_cubit.dart';
import 'package:tentura/features/forward_candidate_context/ui/bloc/forward_candidate_context_state.dart';

void main() {
  late _DeferredRepository repository;
  late LoadForwardCandidateContextCase loadCase;

  setUp(() {
    repository = _DeferredRepository();
    loadCase = LoadForwardCandidateContextCase(
      repository,
      env: const Env(),
      logger: Logger('ForwardCandidateContextCubitTest'),
    );
  });

  test('direct contact skips the use case', () async {
    final cubit = ForwardCandidateContextCubit(
      profile: const Profile(id: 'candidate', myVote: 1),
      context: 'personal',
      loadCase: loadCase,
    );
    addTearDown(cubit.close);

    await cubit.load();

    expect(cubit.state.phase, ForwardCandidateContextPhase.direct);
    expect(repository.calls, 0);
  });

  test('a newer retry wins over an older completion', () async {
    final cubit = _transitiveCubit(loadCase);
    addTearDown(cubit.close);

    final first = cubit.load();
    final second = cubit.retry();
    repository.completers[1].complete(_pathContext());
    await second;
    repository.completers[0].complete(
      const CandidateConnectionContext(
        status: CandidateConnectionContextStatus.unavailable,
      ),
    );
    await first;

    expect(cubit.state.phase, ForwardCandidateContextPhase.path);
    expect(repository.calls, 2);
  });

  test('maps bounded fallback, unavailable, and transport failure', () async {
    final cubit = _transitiveCubit(loadCase);
    addTearDown(cubit.close);

    var pending = cubit.load();
    repository.completers[0].complete(
      const CandidateConnectionContext(
        status: CandidateConnectionContextStatus.longPath,
      ),
    );
    await pending;
    expect(cubit.state.phase, ForwardCandidateContextPhase.longPath);

    pending = cubit.retry();
    repository.completers[1].complete(
      const CandidateConnectionContext(
        status: CandidateConnectionContextStatus.unavailable,
      ),
    );
    await pending;
    expect(cubit.state.phase, ForwardCandidateContextPhase.unavailable);

    pending = cubit.retry();
    repository.completers[2].completeError(StateError('offline'));
    await pending;
    expect(cubit.state.phase, ForwardCandidateContextPhase.transportError);
  });

  test('completion after disposal is ignored', () async {
    final cubit = _transitiveCubit(loadCase);
    final pending = cubit.load();
    await cubit.close();

    repository.completers.single.complete(_pathContext());
    await pending;

    expect(cubit.isClosed, isTrue);
  });
}

ForwardCandidateContextCubit _transitiveCubit(
  LoadForwardCandidateContextCase loadCase,
) => ForwardCandidateContextCubit(
  profile: const Profile(id: 'candidate'),
  context: 'personal',
  loadCase: loadCase,
);

CandidateConnectionContext _pathContext() => const CandidateConnectionContext(
  status: CandidateConnectionContextStatus.path,
  nodes: [
    CandidateConnectionNode(
      kind: CandidateConnectionNodeKind.viewer,
      id: 'viewer',
    ),
    CandidateConnectionNode(
      kind: CandidateConnectionNodeKind.candidate,
      id: 'candidate',
    ),
  ],
);

final class _DeferredRepository
    implements ForwardCandidateContextRepositoryPort {
  final completers = <Completer<CandidateConnectionContext>>[];
  int calls = 0;

  @override
  Future<CandidateConnectionContext> load({
    required String candidateId,
    required String context,
  }) {
    calls++;
    final completer = Completer<CandidateConnectionContext>();
    completers.add(completer);
    return completer.future;
  }
}
