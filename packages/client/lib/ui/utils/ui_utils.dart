// DEPRECATED scope: prefer `context.tt` (TenturaTokens) for new layout; do not add
// new `kPadding*` / spacing constants here — use design-system tokens instead.

import 'package:intl/intl.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:auto_route/auto_route.dart';

import 'package:tentura/consts.dart';

import 'package:tentura/features/auth/domain/exception.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';

import '../bloc/state_base.dart';
import '../l10n/l10n.dart';
import '../message/action_message_base.dart';

const kSpacingSmall = 8.0;
const kSpacingMedium = 16.0;
const kSpacingLarge = 24.0;

const kPaddingAll = EdgeInsets.all(kSpacingMedium);
const kPaddingAllS = EdgeInsets.all(kSpacingSmall);
const kPaddingAllL = EdgeInsets.all(kSpacingLarge);

const kPaddingH = EdgeInsets.symmetric(horizontal: kSpacingMedium);
const kPaddingT = EdgeInsets.only(top: kSpacingMedium);
const kPaddingV = EdgeInsets.symmetric(vertical: kSpacingMedium);

const kPaddingLargeT = EdgeInsets.only(top: kSpacingLarge);
const kPaddingLargeV = EdgeInsets.symmetric(vertical: kSpacingLarge);

const kPaddingSmallT = EdgeInsets.only(top: kSpacingSmall);
const kPaddingSmallH = EdgeInsets.symmetric(horizontal: kSpacingSmall);
const kPaddingSmallV = EdgeInsets.symmetric(vertical: kSpacingSmall);

const kPaddingBottomTextInput = EdgeInsets.only(
  bottom: 80,
  left: kSpacingMedium,
  right: kSpacingMedium,
);

const kBorderRadius = 8.0;

final _fmtYMd = DateFormat.yMd();
final _fmtHm = DateFormat.Hm();

final GlobalKey<ScaffoldMessengerState> snackbarKey =
    GlobalKey<ScaffoldMessengerState>();

/// Clears snack bars when a new route is stacked (e.g. leaving Inbox for a
/// beacon). Per-navigator instance — do not use a singleton (nested routers).
class ClearSnackBarsOnPushObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => snackbarKey.currentState?.clearSnackBars(),
      );
    }
  }
}

String dateFormatYMD(DateTime? dateTime) =>
    dateTime == null ? '' : _fmtYMd.format(dateTime);

String timeFormatHm(DateTime? dateTime) =>
    dateTime == null ? '' : _fmtHm.format(dateTime);

ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showSnackBar(
  BuildContext context, {
  String? text,
  Color? color,
  bool isError = false,
  bool isFloating = false,
  SnackBarAction? action,
  List<TextSpan>? textSpans,
  Duration? duration,
}) {
  // Errors linger longer so the message can be read and the Copy button tapped.
  duration ??= Duration(seconds: isError ? 15 : kSnackBarDuration);
  final theme = Theme.of(context);
  final scaffoldMessenger =
      ScaffoldMessenger.maybeOf(context) ?? snackbarKey.currentState!
        ..clearSnackBars();

  // The full, untruncated message. The SnackBar may clip long text on screen,
  // so we keep the complete string for logging and for the Copy action.
  final fullText = [
    ?text,
    ...?textSpans?.map((s) => s.toPlainText()),
  ].join();

  if (isError) {
    // Report the full error so it always lands in the logs/console regardless
    // of the configured log level (the default debug level hides `fine`).
    GetIt.I<Logger>().severe(fullText);
  }

  // Errors get a Copy action so the (often cryptic) server message can be
  // pasted into a bug report. Only added when the caller didn't supply its own.
  final effectiveAction =
      action ??
      (isError && fullText.isNotEmpty
          ? SnackBarAction(
              label: L10n.of(context)?.copyToClipboard ?? 'Copy',
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: fullText)),
            )
          : null);

  return scaffoldMessenger.showSnackBar(
    SnackBar(
      action: effectiveAction,
      duration: duration,
      // Keep the close icon for errors even though they now carry an action.
      showCloseIcon: effectiveAction == null || isError,
      margin: isFloating ? kPaddingAll : null,
      dismissDirection: DismissDirection.horizontal,
      behavior: isFloating ? SnackBarBehavior.floating : null,
      backgroundColor: isError
          ? theme.colorScheme.error
          : color ?? theme.snackBarTheme.backgroundColor,
      content: RichText(
        text: TextSpan(
          text: text,
          children: textSpans,
          style: isError
              ? theme.snackBarTheme.contentTextStyle?.copyWith(
                  color: theme.colorScheme.onError,
                )
              : theme.snackBarTheme.contentTextStyle,
        ),
      ),
    ),
  );
}

Widget separatorBuilder(_, _) => const Divider(
  endIndent: kSpacingMedium,
  indent: kSpacingMedium,
);

void commonScreenBlocListener(
  BuildContext context,
  StateBase state, {
  bool listenNavigatingState = true,
  bool listenMessagingState = true,
  bool listenHasErrorState = true,
  String? localeName,
}) {
  localeName ??= L10n.of(context)?.localeName;
  return switch (state.status) {
    final StateIsNavigating s when listenNavigatingState =>
      s.path == kPathBack
          ? context.back()
          : context.router.pushPath(
              s.path,
              includePrefixMatches: true,
              onFailure: GetIt.I<Logger>().fine,
            ),
    final StateIsMessaging s when listenMessagingState => switch (s.message) {
      final LocalizableActionMessage m => showSnackBar(
        context,
        text: m.toL10n(localeName),
        action: SnackBarAction(
          label: m.label.toL10n(localeName),
          onPressed: m.onPressed,
        ),
      ),
      final LocalizableMessage m => showSnackBar(
        context,
        text: m.toL10n(localeName),
      ),
    },
    final StateHasError s when listenHasErrorState =>
      switch (s.error) {
        AuthSessionLostException() => GetIt.I<AuthCubit>().noteAuthSessionLoss(
          s.error,
        ),
        final Localizable e => showSnackBar(
          context,
          isError: true,
          text: e.toL10n(localeName),
        ),
        final Object e => showSnackBar(
          context,
          isError: true,
          text: e.toString(),
        ),
      },
    _ => null,
  };
}
