import 'frame_slice_scheduler.dart';

/// Bounded stepping for «Rearrange everyone» preview (same contract as
/// [FrameSliceScheduler.start] / [FrameSliceScheduler.cancelJob]).
abstract interface class RearrangePreviewScheduler {
  void start({
    required bool Function(int units) step,
    required void Function() onComplete,
  });

  void cancel();

  void cancelJob(void Function() onComplete);

  void dispose();
}

/// Production adapter around [FrameSliceScheduler].
final class FrameSliceRearrangePreviewScheduler
    implements RearrangePreviewScheduler {
  FrameSliceRearrangePreviewScheduler(this._inner);

  final FrameSliceScheduler _inner;

  @override
  void start({
    required bool Function(int units) step,
    required void Function() onComplete,
  }) => _inner.start(step: step, onComplete: onComplete);

  @override
  void cancel() => _inner.cancel();

  @override
  void cancelJob(void Function() onComplete) => _inner.cancelJob(onComplete);

  @override
  void dispose() => _inner.dispose();
}
