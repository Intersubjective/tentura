import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/realtime/realtime_connection_status.dart';
import 'package:tentura/ui/bloc/realtime_status_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/util/ui_utils.dart';

const _kRealtimePausedSnackDuration = Duration(seconds: 6);

/// Non-blocking app-root banner for offline (#513); paused live updates use a
/// floating SnackBar so controls do not jump (#1061).
class RealtimeStatusPresenter extends StatefulWidget {
  const RealtimeStatusPresenter({required this.child, super.key});

  final Widget child;

  @override
  State<RealtimeStatusPresenter> createState() =>
      _RealtimeStatusPresenterState();
}

class _RealtimeStatusPresenterState extends State<RealtimeStatusPresenter> {
  bool _pausedSnackShownThisEpisode = false;

  void _onRealtimeState(BuildContext context, RealtimeStatusState state) {
    final paused = state.showPausedBanner && !state.showOfflineBanner;
    if (paused && !_pausedSnackShownThisEpisode) {
      _pausedSnackShownThisEpisode = true;
      showSnackBar(
        context,
        text: L10n.of(context)!.realtimeUpdatesPausedBanner,
        duration: _kRealtimePausedSnackDuration,
      );
    }
    if (state.phase == RealtimeConnectionPhase.authenticated &&
        !state.showPausedBanner) {
      _pausedSnackShownThisEpisode = false;
    }
  }

  @override
  Widget build(BuildContext context) =>
      BlocListener<RealtimeStatusCubit, RealtimeStatusState>(
        listenWhen: (previous, current) =>
            previous.showPausedBanner != current.showPausedBanner ||
            previous.showOfflineBanner != current.showOfflineBanner ||
            previous.phase != current.phase,
        listener: _onRealtimeState,
        child: BlocSelector<RealtimeStatusCubit, RealtimeStatusState, bool>(
          selector: (state) => state.showOfflineBanner,
          builder: (context, showOffline) {
            return Column(
              children: [
                if (showOffline) const _RealtimeOfflineBanner(),
                Expanded(
                  child: MediaQuery.removePadding(
                    context: context,
                    removeTop: showOffline,
                    child: widget.child,
                  ),
                ),
              ],
            );
          },
        ),
      );
}

class _RealtimeOfflineBanner extends StatelessWidget {
  const _RealtimeOfflineBanner();

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
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
              Icon(Icons.cloud_off_outlined, color: tt.warn),
              SizedBox(width: tt.iconTextGap),
              Flexible(
                child: Text(
                  L10n.of(context)!.connectivityOfflineBanner,
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
