import 'package:flutter/widgets.dart';

import 'package:tentura/domain/attention/request_open_clear.dart';
import 'package:tentura/features/evaluation/ui/bloc/evaluation_cubit.dart';
import 'package:tentura/ui/bloc/state_base.dart';

/// §4 — "Opening a review deep link clears that Request's optional updates and
/// leaves the review obligation live."
///
/// `destination_map.dart` sends `review_all_packages_in` receipts to the
/// beacon detail and every other review receipt here, so the review screen
/// needs its own listener: the beacon host never mounts for these.
///
/// The obligation survives because [AttentionCase.clearRequestOpen] captures
/// the `request_open` kind, whose snapshot excludes obligations — the review
/// stays owed after the screen has cleared its optional updates.
class ReviewOpenClearListener extends StatefulWidget {
  const ReviewOpenClearListener({
    required this.beaconId,
    required this.child,
    this.clear,
    super.key,
  });

  final String beaconId;

  /// Test seam; production resolves [AttentionCase] from the locator.
  final RequestOpenClear? clear;

  final Widget child;

  @override
  State<ReviewOpenClearListener> createState() =>
      _ReviewOpenClearListenerState();
}

class _ReviewOpenClearListenerState extends State<ReviewOpenClearListener> {
  late final _gate = RequestOpenClearGate(clear: widget.clear);

  @override
  Widget build(BuildContext context) =>
      BlocListener<EvaluationCubit, EvaluationState>(
        listenWhen: (previous, current) => current.reviewContentLoaded,
        listener: (context, state) => _gate.reportDisplayed(widget.beaconId),
        child: widget.child,
      );
}
