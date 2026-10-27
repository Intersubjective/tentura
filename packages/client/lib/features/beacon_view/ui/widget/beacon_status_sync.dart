import 'package:flutter/widgets.dart';

import 'package:tentura/features/beacon_threads/ui/bloc/thread_host_cubit.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';

/// Pushes the Request's lifecycle status (and author) from the
/// [BeaconViewCubit] above into the [ThreadHostCubit] above, which hands it
/// to the General room: without it the room reads the Request as not open,
/// and the composer stays read-only.
///
/// Syncs once the content has loaded (already at mount, or later) and again
/// on every status change. Part of `BeaconViewScope`; the screen test
/// harness mounts it too, so tests see the room the app shows (#415, #619).
///
/// Looks the room host up only while in the tree (#745): a state can reach
/// the listener after the Request has left it (a removed subtree whose
/// teardown failed keeps its listeners alive, deactivated), and a lookup
/// from a deactivated context finds no providers (ProviderNotFound).
class BeaconStatusSync extends StatefulWidget {
  const BeaconStatusSync({required this.child, super.key});

  final Widget child;

  @override
  State<BeaconStatusSync> createState() => _BeaconStatusSyncState();
}

class _BeaconStatusSyncState extends State<BeaconStatusSync> {
  /// False from [deactivate] on: the Request has left the tree, and
  /// `mounted` alone does not say so.
  bool _inTree = true;

  @override
  void initState() {
    super.initState();
    final state = context.read<BeaconViewCubit>().state;
    if (state.beaconContentLoaded) _sync(state);
  }

  @override
  void activate() {
    super.activate();
    _inTree = true;
  }

  @override
  void deactivate() {
    _inTree = false;
    super.deactivate();
  }

  void _sync(BeaconViewState state) {
    if (!mounted || !_inTree) return;
    context.read<ThreadHostCubit>().syncBeaconStatus(
      state.beacon.status,
      authorId: state.beacon.author.id,
    );
  }

  @override
  Widget build(BuildContext context) =>
      BlocListener<BeaconViewCubit, BeaconViewState>(
        listenWhen: (p, c) =>
            c.beaconContentLoaded &&
            (p.beaconContentLoaded != c.beaconContentLoaded ||
                p.beacon.status != c.beacon.status),
        listener: (context, state) => _sync(state),
        child: widget.child,
      );
}
