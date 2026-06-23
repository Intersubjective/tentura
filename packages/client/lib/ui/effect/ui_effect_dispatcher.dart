import 'dart:async';

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/features/auth/domain/exception.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';

import '../bloc/state_base.dart';
import '../l10n/l10n.dart';
import '../message/action_message_base.dart';
import '../utils/ui_utils.dart';
import 'ui_effect.dart';

/// Executes a [UiEffect] using the given [BuildContext] (root adapter).
///
/// Navigation uses [RootRouter] from GetIt because [UiEffectHandler] lives in
/// `MaterialApp.router`'s builder — above the AutoRouter subtree — so
/// `context.router` is unavailable there.
void dispatchUiEffect(
  BuildContext context,
  UiEffect effect, {
  String? localeName,
}) {
  localeName ??= L10n.of(context)?.localeName;
  final router = GetIt.I<RootRouter>();
  switch (effect) {
    case NavigatePush(:final path):
      router.pushPath(
        path,
        includePrefixMatches: true,
        onFailure: GetIt.I<Logger>().fine,
      );
    case NavigateBack(:final result):
      if (result != null) {
        unawaited(router.maybePop(result));
      } else {
        router.back();
      }
    case NavigateReplace(:final target):
      switch (target) {
        case NavigateReplaceTarget.home:
          unawaited(router.replaceAll([const HomeRoute()]));
        case NavigateReplaceTarget.authLogin:
          unawaited(router.replaceAll([const AuthLoginRoute()]));
      }
    case ShowMessage(:final message):
      switch (message) {
        case final LocalizableActionMessage m:
          showSnackBar(
            context,
            text: m.toL10n(localeName),
            action: SnackBarAction(
              label: m.label.toL10n(localeName),
              onPressed: m.onPressed,
            ),
          );
        default:
          showSnackBar(context, text: message.toL10n(localeName));
      }
    case ShowError(:final error):
      switch (error) {
        case AuthSessionLostException():
          GetIt.I<AuthCubit>().noteAuthSessionLoss(error);
        case final Localizable e:
          showSnackBar(
            context,
            isError: true,
            text: e.toL10n(localeName),
          );
        default:
          showSnackBar(
            context,
            isError: true,
            text: error.toString(),
          );
      }
  }
}

/// Legacy adapter: maps [StateBase] status to [UiEffect] and dispatches.
void dispatchStateBaseEffects(
  BuildContext context,
  StateBase state, {
  bool listenNavigatingState = true,
  bool listenMessagingState = true,
  bool listenHasErrorState = true,
  String? localeName,
}) {
  localeName ??= L10n.of(context)?.localeName;
  final status = state.status;
  switch (status) {
    case StateIsNavigating s when listenNavigatingState:
      if (s.path == kPathBack) {
        dispatchUiEffect(context, const NavigateBack(), localeName: localeName);
      } else {
        dispatchUiEffect(context, NavigatePush(s.path), localeName: localeName);
      }
    case StateIsMessaging s when listenMessagingState:
      dispatchUiEffect(
        context,
        ShowMessage(s.message),
        localeName: localeName,
      );
    case StateHasError s when listenHasErrorState:
      dispatchUiEffect(
        context,
        ShowError(s.error),
        localeName: localeName,
      );
    default:
      break;
  }
}
