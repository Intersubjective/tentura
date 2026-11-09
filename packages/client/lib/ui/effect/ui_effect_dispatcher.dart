import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/domain/exception/generic_exception.dart';
import 'package:tentura/features/auth/domain/exception.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/ui/navigation/app_navigator.dart';
import 'package:tentura/ui/navigation/home_tab.dart';

import '../l10n/l10n.dart';
import '../message/action_message_base.dart';
import '../utils/ui_utils.dart';
import 'ui_effect.dart';

/// Executes a [UiEffect] using the given [BuildContext] (root adapter).
///
/// Navigation uses `AppNavigator` from `GetIt` because `UiEffectHandler` lives
/// in `MaterialApp.router`'s builder — above the AutoRouter subtree — so
/// `context.router` is unavailable there.
void dispatchUiEffect(
  BuildContext context,
  UiEffect effect, {
  String? localeName,
}) {
  localeName ??= L10n.of(context)?.localeName;
  final navigator = GetIt.I<AppNavigator>();
  switch (effect) {
    case NavigatePush(:final path):
      unawaited(navigator.openPath(path));
    case NavigateBlockedUsers():
      unawaited(navigator.openBlockedUsers());
    case NavigateBack(:final result):
      unawaited(navigator.popOrGoHome(result));
    case NavigateReplace(:final target):
      switch (target) {
        case NavigateReplaceTarget.home:
          unawaited(navigator.resetToHome());
        case NavigateReplaceTarget.homeInboxTab:
          unawaited(navigator.resetToHome(tab: HomeTab.inbox));
        case NavigateReplaceTarget.authLogin:
          unawaited(navigator.resetToLogin());
      }
    case ShowMessage(:final message):
      void show() {
        switch (message) {
          case final LocalizableActionMessage m:
            showSnackBar(
              context,
              text: m.toL10n(localeName),
              duration: m is LocalizableUndoMessage ? m.duration : null,
              action: SnackBarAction(
                label: m.label.toL10n(localeName),
                onPressed: m.onPressed,
              ),
            );
          default:
            showSnackBar(context, text: message.toL10n(localeName));
        }
      }

      // ClearSnackBarsOnPushObserver clears bars in a microtask on didPush
      // (#470). A ShowMessage immediately before NavigateReplace (invalid invite
      // → home, etc.) lost the bar once navigation went through AppNavigator
      // (d528f8ca6, #1124). Yield one frame plus that microtask, same as
      // HomePostJoinListener after a route push.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        scheduleMicrotask(() {
          if (!context.mounted) return;
          show();
        });
      });
    case ShowError(:final error):
      switch (error) {
        case AuthSessionLostException():
          GetIt.I<AuthCubit>().noteAuthSessionLoss(error);
        case final Localizable e:
          showSnackBar(
            context,
            isError: true,
            text: e.toL10n(localeName),
            // Plain copy for a server code (#683): the server's own text
            // still goes to "Copy details".
            detail: e is RemoteApiException && e.hasPlainCopy
                ? e.message
                : null,
            error: error is AuthSessionLostException ? null : error,
          );
        default:
          // Unmapped errors are usually transport / GraphQL text
          // ("field 'x' not found in type 'query_root'"): say something a
          // person can act on, keep the raw text for "Copy details".
          showSnackBar(
            context,
            isError: true,
            text: L10n.of(context)?.errorGenericAction ?? error.toString(),
            detail: error.toString(),
            error: error is AuthSessionLostException ? null : error,
          );
      }
  }
}
