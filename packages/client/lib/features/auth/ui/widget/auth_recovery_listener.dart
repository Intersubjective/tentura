import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/ui/l10n/l10n.dart';

import 'package:tentura/features/auth/domain/entity/auth_recovery_outcome.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/ui/navigation/app_navigator.dart';

/// Whether [AuthRecoveryListener] should react to an [AuthState] transition.
bool authRecoveryListenerShouldListen(
  AuthState previous,
  AuthState current,
) =>
    previous.authRecoveryNeeded != current.authRecoveryNeeded ||
    previous.authSessionLossCount != current.authSessionLossCount ||
    previous.pendingRecoveryNavigation != current.pendingRecoveryNavigation;

/// App-root auth recovery banner, navigation, and session-loss handling.
class AuthRecoveryListener extends StatelessWidget {
  const AuthRecoveryListener({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => BlocListener<AuthCubit, AuthState>(
    listenWhen: authRecoveryListenerShouldListen,
    listener: (context, state) {
      _handlePendingNavigation(context, state);
      _handleRecoveryBanner(context, state);
    },
    child: child,
  );

  void _handlePendingNavigation(BuildContext context, AuthState state) {
    final pending = state.pendingRecoveryNavigation;
    if (pending == null) {
      return;
    }
    final navigator = GetIt.I<AppNavigator>();
    switch (pending) {
      case AuthRecoveryNavigation.nativeLogin:
        unawaited(navigator.resetToLogin());
      case AuthRecoveryNavigation.nativeBack:
        navigator.back();
      case AuthRecoveryNavigation.webInviteLanding:
      case AuthRecoveryNavigation.none:
        break;
    }
    context.read<AuthCubit>().clearPendingRecoveryNavigation();
  }

  void _handleRecoveryBanner(BuildContext context, AuthState state) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) {
      return;
    }

    if (state.authSessionLossCount >= 2 && state.authRecoveryNeeded) {
      messenger.clearMaterialBanners();
      unawaited(
        GetIt.I<AppNavigator>().resetToRecover(),
      );
      return;
    }

    if (!state.authRecoveryNeeded || state.isBootstrapping) {
      messenger.clearMaterialBanners();
      return;
    }

    final l10n = L10n.of(context);
    messenger
      ..clearMaterialBanners()
      ..showMaterialBanner(
        MaterialBanner(
          content: Text(
            l10n?.authSessionProblemBanner ??
                "We couldn't verify your session. Sign in again.",
          ),
          actions: [
            TextButton(
              onPressed: () {
                messenger.clearMaterialBanners();
                unawaited(
                  GetIt.I<AppNavigator>().openRecover(),
                );
              },
              child: Text(l10n?.authSessionProblemFixAction ?? 'Fix sign-in'),
            ),
            TextButton(
              onPressed: () =>
                  context.read<AuthCubit>().dismissAuthRecoveryBanner(),
              child: Text(l10n?.buttonDismiss ?? 'Dismiss'),
            ),
          ],
        ),
      );
  }
}
