import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

/// Whether Request chrome should show persistent Forward.
bool beaconViewShowsForwardAppBarAction({
  required BeaconViewState state,
  required bool showBeaconContent,
  required bool showInitialLoading,
}) {
  if (!showBeaconContent || showInitialLoading) return false;
  return state.beacon.allowsForward;
}

/// Persistent secondary Forward control for Request chrome (never primary filled).
class BeaconViewForwardAppBarButton extends StatelessWidget {
  const BeaconViewForwardAppBarButton({
    required this.onPressed,
    super.key,
  });

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final label = l10n.labelForward;
    final compact = context.windowClass == WindowClass.compact;
    final hitSize = tt.buttonHeight < kMinInteractiveDimension
        ? kMinInteractiveDimension
        : tt.buttonHeight;

    final button = TextButton.icon(
      key: TestIds.key(TestIds.beaconForward),
      onPressed: onPressed,
      icon: Icon(Icons.send_outlined, size: tt.iconSize),
      label: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      style: TextButton.styleFrom(
        minimumSize: Size(hitSize, hitSize),
        padding: EdgeInsets.symmetric(horizontal: tt.tightGap),
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );

    final sized = compact
        ? ConstrainedBox(
            constraints: BoxConstraints(maxWidth: hitSize * 3),
            child: button,
          )
        : button;

    return Semantics(
      identifier: TestIds.beaconForward,
      button: true,
      label: label,
      child: kIsWeb
          ? sized
          : Tooltip(
              message: label,
              child: sized,
            ),
    );
  }
}
