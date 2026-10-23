import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/bloc/realtime_status_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Non-blocking app-root banner shown only after a sustained live outage, or
/// at once when the network is unreachable (#513).
class RealtimeStatusPresenter extends StatelessWidget {
  const RealtimeStatusPresenter({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      BlocSelector<
        RealtimeStatusCubit,
        RealtimeStatusState,
        ({bool offline, bool paused})
      >(
        selector: (state) =>
            (offline: state.showOfflineBanner, paused: state.showPausedBanner),
        // The banner takes its own room at the top and pushes the screen
        // down instead of overlaying the app bar title (#513). The child
        // keeps its slot either way, so showing the banner keeps its state.
        builder: (context, banners) {
          final shown = banners.offline || banners.paused;
          return Column(
            children: [
              // Offline explains a paused socket too, so it wins.
              if (shown) _RealtimeStatusBanner(offline: banners.offline),
              Expanded(
                // The banner already pads for the status bar inset.
                child: MediaQuery.removePadding(
                  context: context,
                  removeTop: shown,
                  child: child,
                ),
              ),
            ],
          );
        },
      );
}

class _RealtimeStatusBanner extends StatelessWidget {
  const _RealtimeStatusBanner({required this.offline});

  final bool offline;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    // The banner's colour fills the status bar inset it pads for.
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: SafeArea(
        bottom: false,
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: tt.screenHPadding,
            vertical: tt.tightGap,
          ),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: tt.border)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                offline
                    ? Icons.cloud_off_outlined
                    : Icons.sync_problem_outlined,
                color: tt.warn,
              ),
              SizedBox(width: tt.iconTextGap),
              Flexible(
                child: Text(
                  offline
                      ? L10n.of(context)!.connectivityOfflineBanner
                      : L10n.of(context)!.realtimeUpdatesPausedBanner,
                  style: TenturaText.bodySmall(tt.text),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
