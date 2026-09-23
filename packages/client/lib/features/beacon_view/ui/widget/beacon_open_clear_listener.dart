import 'package:flutter/widgets.dart';

import 'package:tentura/domain/attention/request_open_clear.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';

/// §4 — "Opening a Request clears a **snapshot** taken when it opened, after
/// it successfully displays".
///
/// Every entry route into the Request detail mounts `BeaconViewRoute`, so one
/// listener here covers all of them: My Desk, For You, History, push, profile,
/// graph and deep links alike. Nothing clears before navigation, so a
/// forbidden or failed open clears nothing — the cubit reaches
/// `beaconContentLoaded && !beaconUnavailable` only after the fetch succeeded.
///
/// Opening a child clears the child only, and opening a parent the parent
/// only: the id below is the one this route mounted, never its relatives.
class BeaconOpenClearListener extends StatefulWidget {
  const BeaconOpenClearListener({
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
  State<BeaconOpenClearListener> createState() =>
      _BeaconOpenClearListenerState();
}

class _BeaconOpenClearListenerState extends State<BeaconOpenClearListener> {
  late final _gate = RequestOpenClearGate(clear: widget.clear);

  @override
  Widget build(BuildContext context) =>
      BlocListener<BeaconViewCubit, BeaconViewState>(
        listenWhen: (previous, current) =>
            current.beaconContentLoaded && !current.beaconUnavailable,
        listener: (context, state) => _gate.reportDisplayed(widget.beaconId),
        child: widget.child,
      );
}
