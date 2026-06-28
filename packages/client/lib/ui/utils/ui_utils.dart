// DEPRECATED scope: prefer `context.tt` (TenturaTokens) for new layout; do not add
// new `kPadding*` / spacing constants here — use design-system tokens instead.

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:logging/logging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:auto_route/auto_route.dart';

import 'package:tentura/app/sentry/report_user_facing_error.dart';
import 'package:tentura/consts.dart';

import 'package:tentura/features/auth/domain/exception.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';

import '../bloc/screen_cubit.dart';
import '../effect/ui_effect_bus.dart';
import '../effect/ui_effect_handler.dart';
import '../l10n/l10n.dart';

/// Provides a route-local [ScreenCubit] and [UiEffectHandler] subtree.
Widget localScreenCubitScope({required Widget child}) {
  final effects = UiEffectBus();
  return MultiBlocProvider(
    providers: [
      BlocProvider(create: (_) => ScreenCubit(effects)),
    ],
    child: UiEffectHandler(effects: effects, child: child),
  );
}

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
      // Clear before the next pointer frame. A post-frame clear races Firefox
      // trackpad pan-zoom hit tests against SnackBar's Dismissible overlay.
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
  Duration? duration,
  Object? error,
  StackTrace? stackTrace,
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
    if (error != null) {
      reportUserFacingError(error, stackTrace: stackTrace);
    }
    GetIt.I<Logger>().severe(fullText, error, stackTrace);
  }

  // Errors get a Copy action so the (often cryptic) server message can be
  // pasted into a bug report. Only added when the caller didn't supply its own.
  final effectiveAction =
      action ??
      (isError && fullText.isNotEmpty
          ? SnackBarAction(
              label: L10n.of(context)?.copyToClipboard ?? 'Copy',
              onPressed: () => Clipboard.setData(ClipboardData(text: fullText)),
            )
          : null);

  return scaffoldMessenger.showSnackBar(
    SnackBar(
      action: effectiveAction,
      duration: duration,
      // Action and close icon coexist (M3); users can dismiss without using the action.
      showCloseIcon: true,
      margin: isFloating ? kPaddingAll : null,
      // Web: horizontal Dismissible + PointerPanZoom (Firefox trackpad) can hit-test
      // before the snack bar is laid out during route transitions (Sentry #7579576017).
      dismissDirection: kIsWeb
          ? DismissDirection.none
          : DismissDirection.horizontal,
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
