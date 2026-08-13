import 'package:tentura/ui/bloc/state_base.dart';

export 'package:tentura/ui/bloc/state_base.dart';

class RoutingMuteState extends StateBase {
  RoutingMuteState({
    Set<String>? mutedSlugs,
    super.status = const StateIsLoading(),
  }) : mutedSlugs = mutedSlugs ?? const {};

  final Set<String> mutedSlugs;

  RoutingMuteState copyWith({
    Set<String>? mutedSlugs,
    StateStatus? status,
  }) =>
      RoutingMuteState(
        mutedSlugs: mutedSlugs ?? this.mutedSlugs,
        status: status ?? this.status,
      );
}
