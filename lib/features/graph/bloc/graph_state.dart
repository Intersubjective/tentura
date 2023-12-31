part of 'graph_cubit.dart';

final class GraphState extends StateBase {
  const GraphState({
    required this.focus,
    this.isAnimated = false,
    this.positiveOnly = true,
    super.status = FetchStatus.isEmpty,
    super.error,
  });

  final String focus;
  final bool isAnimated;
  final bool positiveOnly;

  @override
  GraphState copyWith({
    String? focus,
    bool? isAnimated,
    bool? positiveOnly,
    FetchStatus? status,
    Object? error,
  }) =>
      GraphState(
        focus: focus ?? this.focus,
        isAnimated: isAnimated ?? this.isAnimated,
        positiveOnly: positiveOnly ?? this.positiveOnly,
        status: status ?? (error == null ? this.status : FetchStatus.hasError),
        error: error ?? this.error,
      );

  @override
  List<Object?> get props => [
        positiveOnly,
        isAnimated,
        status,
        focus,
        error,
      ];
}
