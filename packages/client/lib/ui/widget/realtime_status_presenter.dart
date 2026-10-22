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
        builder: (context, banners) => Stack(
          fit: StackFit.expand,
          children: [
            child,
            // Offline explains a paused socket too, so it wins.
            if (banners.offline)
              const Align(
                alignment: Alignment.topCenter,
                child: _RealtimeStatusBanner(offline: true),
              )
            else if (banners.paused)
              const Align(
                alignment: Alignment.topCenter,
                child: _RealtimeStatusBanner(offline: false),
              ),
          ],
        ),
      );
}

class _RealtimeStatusBanner extends StatelessWidget {
  const _RealtimeStatusBanner({required this.offline});

  final bool offline;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return SafeArea(
      bottom: false,
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
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
