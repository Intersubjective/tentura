import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../bloc/fcm_cubit.dart';
import '../bloc/fcm_state.dart';

/// Puts [NotificationPermissionBanner] above [child] while
/// [FcmState.showsPermissionPrompt] holds.
///
/// The tree keeps one shape whether or not the banner shows, so [child] (the
/// home tab navigators) never remounts when it appears or goes.
class NotificationPermissionPromptFrame extends StatelessWidget {
  const NotificationPermissionPromptFrame({
    required this.child,
    this.cubit,
    super.key,
  });

  final Widget child;

  /// Defaults to the global [FcmCubit] (none in shell tests that skip DI).
  final FcmCubit? cubit;

  @override
  Widget build(BuildContext context) {
    final fcmCubit =
        cubit ??
        (GetIt.I.isRegistered<FcmCubit>() ? GetIt.I<FcmCubit>() : null);
    if (fcmCubit == null) return child;
    return BlocBuilder<FcmCubit, FcmState>(
      bloc: fcmCubit,
      buildWhen: (p, c) => p.showsPermissionPrompt != c.showsPermissionPrompt,
      builder: (context, state) {
        final shows = state.showsPermissionPrompt;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (shows)
              SafeArea(
                bottom: false,
                child: NotificationPermissionBanner(
                  // Called straight from the tap: the browser shows its
                  // prompt only inside a user gesture.
                  onAllow: () => unawaited(fcmCubit.requestPermissionFromUser()),
                  onDismiss: () => unawaited(fcmCubit.dismissPermissionPrompt()),
                ),
              ),
            Expanded(
              child: MediaQuery.removePadding(
                context: context,
                removeTop: shows,
                child: child,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// A small in-app explanation shown before the browser's own permission
/// prompt: why Tentura wants notifications and what to click. The browser
/// prompt opens only from [onAllow].
class NotificationPermissionBanner extends StatelessWidget {
  const NotificationPermissionBanner({
    required this.onAllow,
    required this.onDismiss,
    super.key,
  });

  final VoidCallback onAllow;

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    return Material(
      color: tt.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: tt.border)),
        ),
        child: Padding(
          padding: EdgeInsetsDirectional.only(
            start: tt.screenHPadding,
            end: tt.tightGap,
            top: tt.rowGap,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.notifications_outlined,
                    size: tt.iconSize,
                    color: tt.info,
                  ),
                  SizedBox(width: tt.iconTextGap),
                  Expanded(
                    child: Semantics(
                      container: true,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.notificationPromptTitle,
                            style: TenturaText.titleSmall(tt.text),
                          ),
                          SizedBox(height: tt.tightGap),
                          Text(
                            l10n.notificationPromptBody,
                            style: TenturaText.bodySmall(tt.textMuted),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Wrap(
                  alignment: WrapAlignment.end,
                  children: [
                    TenturaTextAction(
                      label: l10n.notificationPromptDismiss,
                      tone: TenturaTone.neutral,
                      onPressed: onDismiss,
                      semanticsIdentifier: 'notification-prompt-dismiss',
                    ),
                    TenturaTextAction(
                      label: l10n.notificationPromptAllow,
                      onPressed: onAllow,
                      semanticsIdentifier: 'notification-prompt-allow',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
