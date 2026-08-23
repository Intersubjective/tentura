import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:tentura/domain/entity/profile.dart';

import '../../domain/entity/candidate_connection_context.dart';
import '../../domain/use_case/load_forward_candidate_context_case.dart';
import 'forward_candidate_context_state.dart';

final class ForwardCandidateContextCubit
    extends Cubit<ForwardCandidateContextState> {
  ForwardCandidateContextCubit({
    required this.profile,
    required this.context,
    LoadForwardCandidateContextCase? loadCase,
  }) : _loadCase = loadCase ?? GetIt.I<LoadForwardCandidateContextCase>(),
       super(
         ForwardCandidateContextState(
           phase: profile.isFriend
               ? ForwardCandidateContextPhase.direct
               : ForwardCandidateContextPhase.loading,
         ),
       );

  final Profile profile;
  final String context;
  final LoadForwardCandidateContextCase _loadCase;
  int _generation = 0;

  Future<void> load() async {
    if (profile.isFriend) return;
    final generation = ++_generation;
    emit(
      const ForwardCandidateContextState(
        phase: ForwardCandidateContextPhase.loading,
      ),
    );
    try {
      final result = await _loadCase.load(
        candidateId: profile.id,
        context: context,
      );
      if (isClosed || generation != _generation) return;
      emit(
        ForwardCandidateContextState(
          phase: _phaseFor(result.status),
          connectionContext: result,
        ),
      );
    } catch (error) {
      if (isClosed || generation != _generation) return;
      emit(
        ForwardCandidateContextState(
          phase: ForwardCandidateContextPhase.transportError,
          error: error,
        ),
      );
    }
  }

  Future<void> retry() => load();

  @override
  Future<void> close() {
    _generation++;
    return super.close();
  }
}

ForwardCandidateContextPhase _phaseFor(
  CandidateConnectionContextStatus status,
) => switch (status) {
  CandidateConnectionContextStatus.path => ForwardCandidateContextPhase.path,
  CandidateConnectionContextStatus.longPath =>
    ForwardCandidateContextPhase.longPath,
  CandidateConnectionContextStatus.unavailable =>
    ForwardCandidateContextPhase.unavailable,
};
