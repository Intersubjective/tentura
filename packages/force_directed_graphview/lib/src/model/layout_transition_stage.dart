import 'package:meta/meta.dart';

/// When one node takes part in a layout transition: it starts [delay] after
/// the transition begins and then travels for [duration]. Nodes sharing a stage
/// move as one group.
@immutable
final class LayoutTransitionStage {
  const LayoutTransitionStage({required this.delay, required this.duration});

  final Duration delay;
  final Duration duration;

  /// Time from the start of the transition until this stage lands.
  Duration get end => delay + duration;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LayoutTransitionStage &&
          delay == other.delay &&
          duration == other.duration;

  @override
  int get hashCode => Object.hash(delay, duration);
}
