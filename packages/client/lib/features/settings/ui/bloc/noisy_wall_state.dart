import 'package:tentura/ui/bloc/state_base.dart';

export 'package:tentura/ui/bloc/state_base.dart';

class NoisyWallState extends StateBase {
  const NoisyWallState({
    this.enabled,
    super.status = const StateIsLoading(),
  });

  /// Null until the first fetch succeeds.
  final bool? enabled;

  NoisyWallState copyWith({bool? enabled, StateStatus? status}) =>
      NoisyWallState(
        enabled: enabled ?? this.enabled,
        status: status ?? this.status,
      );
}
