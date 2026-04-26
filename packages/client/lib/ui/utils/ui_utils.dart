// DEPRECATED scope: prefer `context.tt` (TenturaTokens) for new layout; do not add
// new `kPadding*` / spacing constants here — use design-system tokens instead.

import 'package:intl/intl.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:flutter/material.dart';
import 'package:auto_route/auto_route.dart';

import 'package:tentura/consts.dart';

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
      snackbarKey.currentState?.clearSnackBars();
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
  Duration duration = const Duration(seconds: kSnackBarDuration),
}) {
  final theme = Theme.of(context);
  final scaffoldMessenger =
      ScaffoldMessenger.maybeOf(context) ?? snackbarKey.currentState!
        ..clearSnackBars();
  if (isError) {
    GetIt.I<Logger>().fine(text);
  }
  return scaffoldMessenger.showSnackBar(
    SnackBar(
      action: action,
      duration: duration,
      showCloseIcon: action == null,
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
    final StateHasError s when listenHasErrorState => showSnackBar(
      context,
      isError: true,
      text: switch (s.error) {
        final Localizable e => e.toL10n(localeName),
        final Object e => e.toString(),
      },
    ),
    _ => null,
  };
}
