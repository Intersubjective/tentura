import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

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
    final tooltipText = beaconViewRoomAppBarTooltip(state, l10n);
    return Badge(
      isLabelVisible: state.roomUnreadCount > 0,
      label: Text('${state.roomUnreadCount}'),
      child: IconButton(
        key: TestIds.key(TestIds.beaconRoomOpen),
        // On Flutter web desktop, hovered IconButton tooltips can trigger an
        // Overlay layout assert while the window is resizing.
        tooltip: kIsWeb ? null : tooltipText,
        icon: Icon(Icons.forum_rounded, semanticLabel: tooltipText),
        onPressed: onPressed,
      ),
    );
  }
}
