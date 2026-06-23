import 'package:flutter/material.dart';

import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'beacon_view_app_bar_overflow.dart';

class BeaconViewRoomAppBarButton extends StatelessWidget {
  const BeaconViewRoomAppBarButton({
    required this.state,
    required this.onPressed,
    super.key,
  });

  final BeaconViewState state;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    return Badge(
      isLabelVisible: state.roomUnreadCount > 0,
      label: Text('${state.roomUnreadCount}'),
      child: IconButton(
        tooltip: beaconViewRoomAppBarTooltip(state, l10n),
        icon: const Icon(Icons.forum_rounded),
        onPressed: onPressed,
      ),
    );
  }
}
