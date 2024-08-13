part of 'context_cubit.dart';

final class ContextState extends StateBase {
  const ContextState({
    this.contexts = const {},
    this.selected = '',
    super.status,
    super.error,
  });

  final Set<String> contexts;
  final String selected;

  @override
  List<Object?> get props => [
        selected,
        contexts,
        status,
        error,
      ];

  @override
  ContextState copyWith({
    String? selected,
    Set<String>? contexts,
    FetchStatus? status,
    Object? error,
  }) =>
      ContextState(
        contexts: contexts ?? this.contexts,
        selected: selected ?? this.selected,
        status: status ?? this.status,
        error: error ?? this.error,
      );

  @override
  ContextState setError(Object error) => ContextState(
        status: FetchStatus.isFailure,
        contexts: contexts,
        error: error,
      );

  @override
  ContextState setLoading() => ContextState(
        status: FetchStatus.isLoading,
        contexts: contexts,
      );
}
