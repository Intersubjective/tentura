import 'dart:async';

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

import 'package:tentura_root/domain/entity/localizable.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/features/auth/domain/exception.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';

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
        case NavigateReplaceTarget.homeInboxTab:
          unawaited(
            router.replaceAll([
              const HomeRoute(children: [InboxRoute()]),
            ]),
          );
        case NavigateReplaceTarget.authLogin:
          unawaited(router.replaceAll([const AuthLoginRoute()]));
      }
    case ShowMessage(:final message):
      void show() {
        switch (message) {
          case final LocalizableActionMessage m:
            showSnackBar(
              context,
              text: m.toL10n(localeName),
              duration: const Duration(seconds: 8),
              action: SnackBarAction(
                label: m.label.toL10n(localeName),
                onPressed: m.onPressed,
              ),
            );
          default:
            showSnackBar(context, text: message.toL10n(localeName));
        }
      }

      // Let route/dialog dismiss and list rebuild before the nudge snackbar.
      if (message is LocalizableActionMessage) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          show();
        });
      } else {
        show();
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
            error: error is AuthSessionLostException ? null : error,
          );
        default:
          showSnackBar(
            context,
            isError: true,
            text: error.toString(),
            error: error is AuthSessionLostException ? null : error,
          );
      }
  }
}
