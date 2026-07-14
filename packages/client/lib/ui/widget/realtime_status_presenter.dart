import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/bloc/realtime_status_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Non-blocking app-root banner shown only after a sustained live outage.
class RealtimeStatusPresenter extends StatelessWidget {
  const RealtimeStatusPresenter({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      BlocSelector<RealtimeStatusCubit, RealtimeStatusState, bool>(
        selector: (state) => state.showPausedBanner,
        builder: (context, showPausedBanner) => Stack(
          fit: StackFit.expand,
          children: [
            child,
            if (showPausedBanner)
              const Align(
                alignment: Alignment.topCenter,
                child: _RealtimePausedBanner(),
              ),
          ],
        ),
      );
}

class _RealtimePausedBanner extends StatelessWidget {
  const _RealtimePausedBanner();

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
              Icon(Icons.sync_problem_outlined, color: tt.warn),
              SizedBox(width: tt.iconTextGap),
              Flexible(
                child: Text(
                  L10n.of(context)!.realtimeUpdatesPausedBanner,
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
