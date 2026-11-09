import 'package:flutter/material.dart';

import 'package:tentura/ui/navigation/home_tab.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/home/ui/widget/home_rail_frame.dart';
import 'package:tentura/ui/widget/auto_leading_with_fallback.dart';

/// Home rail tab for a Request opened from [entry] query (`?entry=`).
HomeTab homeTabForBeaconViewEntry(String? entry) => switch (entry?.trim()) {
  kBeaconEntryInbox => HomeTab.inbox,
  kBeaconEntryRoomNotification => HomeTab.updates,
  _ => HomeTab.work,
};

/// Back-only top bar row shared by the kind gate and the Request first-load
/// shell (#545 PR A).
Widget beaconViewLoadingShellTopBarRow({
  required BuildContext context,
  required VoidCallback onBack,
  Key? headerKey,
}) {
  final tt = context.tt;
  return Padding(
    key: headerKey,
    padding: EdgeInsetsDirectional.symmetric(horizontal: tt.screenHPadding),
    child: Row(
      children: [
        AutoLeadingWithFallback(
          fallbackPath: kPathMyWork,
          onFallback: onBack,
        ),
      ],
    ),
  );
}

PreferredSizeWidget beaconViewLoadingShellAppBar(
  BuildContext context, {
  required VoidCallback onBack,
  Key? headerKey,
}) {
  return TenturaTopBar.of(
    context,
    alignment: TenturaTopBarAlignment.edgeToEdge,
    title: const SizedBox.shrink(),
    row: beaconViewLoadingShellTopBarRow(
      context: context,
      onBack: onBack,
      headerKey: headerKey,
    ),
  );
}

/// Full-frame shell while the kind gate or Request body gate has not revealed.
class BeaconViewLoadingShellFrame extends StatelessWidget {
  const BeaconViewLoadingShellFrame({
    required this.entry,
    required this.onBack,
    this.body = const SizedBox.shrink(),
    this.headerKey,
    super.key,
  });

  final String? entry;
  final VoidCallback onBack;
  final Widget body;
  final Key? headerKey;

  @override
  Widget build(BuildContext context) {
    return HomeRailFrame(
      selectedTab: homeTabForBeaconViewEntry(entry),
      child: Scaffold(
        appBar: beaconViewLoadingShellAppBar(
          context,
          onBack: onBack,
          headerKey: headerKey,
        ),
        body: SafeArea(child: body),
      ),
    );
  }
}
