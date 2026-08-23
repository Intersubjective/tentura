import 'package:tentura/ui/bloc/state_base.dart';

import '../../domain/entity/candidate_connection_context.dart';

enum ForwardCandidateContextPhase {
  direct,
  loading,
  path,
  longPath,
  unavailable,
  transportError,
}

final class ForwardCandidateContextState extends StateBase {
  const ForwardCandidateContextState({
    required this.phase,
    this.connectionContext,
    this.error,
  });

  final ForwardCandidateContextPhase phase;
  final CandidateConnectionContext? connectionContext;
  final Object? error;
}
