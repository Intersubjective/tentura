// DEPRECATED scope: prefer `context.tt` (TenturaTokens) for new layout; do not add
// new `kPadding*` / spacing constants here — use design-system tokens instead.

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:intl/intl.dart';
import 'package:logging/logging.dart';
import 'package:flutter/material.dart';

import 'package:tentura/app/sentry/report_user_facing_error.dart';
import 'package:tentura/consts.dart';

import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';

import '../bloc/screen_cubit.dart';
import '../effect/ui_effect_bus.dart';
import '../effect/ui_effect_handler.dart';
import '../l10n/l10n.dart';
import 'package:tentura/design_system/tentura_radii.dart';
import 'copy_text_to_clipboard.dart';
import 'snack_bar_clearance.dart';

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

const kPaddingH = EdgeInsets.symmetric(horizontal: kSpacingMedium);
const kPaddingT = EdgeInsets.only(top: kSpacingMedium);
const kPaddingV = EdgeInsets.symmetric(vertical: kSpacingMedium);

const kPaddingSmallT = EdgeInsets.only(top: kSpacingSmall);
const kPaddingSmallH = EdgeInsets.symmetric(horizontal: kSpacingSmall);
const kPaddingSmallV = EdgeInsets.symmetric(vertical: kSpacingSmall);

const kBorderRadius = 8.0;

final _fmtYMdByLocale = <String?, DateFormat>{};
final _fmtHmByLocale = <String?, DateFormat>{};

final GlobalKey<ScaffoldMessengerState> snackbarKey =
    GlobalKey<ScaffoldMessengerState>();

/// Clears snack bars when the user moves to another screen: a new route is
/// stacked (e.g. leaving Inbox for a beacon) or a Home tab is switched (#470;
/// AutoTabsRouter pushes no route and reports tab changes only to inherited
/// [AutoRouterObserver]s). Per-navigator instance — do not use a singleton
/// (nested routers).
class ClearSnackBarsOnPushObserver extends AutoRouterObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) _clear();
  }

  @override
  void didChangeTabRoute(TabPageRoute route, TabPageRoute previousRoute) =>
      _clear();

  @override
  void didInitTabRoute(TabPageRoute route, TabPageRoute? previousRoute) {
    // No previous tab = Home itself mounting, not a move away from a screen.
    if (previousRoute != null) _clear();
  }

  // Clear before the next pointer frame. A post-frame clear races Firefox
  // trackpad pan-zoom hit tests against SnackBar's Dismissible overlay.
  static void _clear() => scheduleMicrotask(() {
    snackbarKey.currentState?.clearSnackBars();
    // #448: a pane's own messenger is not under [snackbarKey]; without this
    // its bar outlived the move and could sit beside an app-wide bar.
    for (final pane in _paneMessengers.toList()) {
      pane.currentState?.clearSnackBars();
    }
  });
}

final _paneMessengers = <GlobalKey<ScaffoldMessengerState>>{};

/// A pane-local [ScaffoldMessenger] (e.g. the request page's Now pane, #448)
/// whose bars are cleared together with the app-wide ones by
/// [ClearSnackBarsOnPushObserver] on a push or a Home tab change.
class PaneScaffoldMessenger extends StatefulWidget {
  const PaneScaffoldMessenger({required this.child, super.key});

  final Widget child;

  @override
  State<PaneScaffoldMessenger> createState() => _PaneScaffoldMessengerState();
}

class _PaneScaffoldMessengerState extends State<PaneScaffoldMessenger> {
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    _paneMessengers.add(_messengerKey);
  }

  @override
  void dispose() {
    _paneMessengers.remove(_messengerKey);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ScaffoldMessenger(key: _messengerKey, child: widget.child);
}

/// Display-only formatters: always render the viewer's local wall-clock
/// time, regardless of whether [dateTime] is UTC or already local
/// (`.toLocal()` on an already-local value is a no-op). Do not bypass these
/// with a raw `DateFormat` call on an unconverted `DateTime` — that was the
/// bug behind issue #112's beacon_tile/inbox_item_tile/HUD-composer leaks.
///
/// Pass the app's [locale] (`L10n.localeName`): without it the date follows
/// the process default (US `M/d/y`), not the language the person chose
/// (#609: «05.10.2026» in Russian).
String dateFormatYMD(DateTime? dateTime, {String? locale}) => dateTime == null
    ? ''
    : _fmtYMdByLocale
          .putIfAbsent(locale, () => DateFormat.yMd(locale))
          .format(dateTime.toLocal());

/// Time as `Hm` in [locale] (pass `L10n.localeName`, #670); null keeps the
/// process default locale.
String timeFormatHm(DateTime? dateTime, {String? locale}) => dateTime == null
    ? ''
    : _fmtHmByLocale
          .putIfAbsent(locale, () => DateFormat.Hm(locale))
          .format(dateTime.toLocal());

/// [showTimePicker] on the 24-hour dial: the app shows every time as `Hm`,
/// so the 12-hour AM/PM dial did not match what the person then sees (#446).
Future<TimeOfDay?> showAppTimePicker({
  required BuildContext context,
  required TimeOfDay initialTime,
}) => showTimePicker(
  context: context,
  initialTime: initialTime,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
    child: child!,
  ),
);

/// Returns null (and shows nothing) when no [ScaffoldMessenger] is reachable:
/// neither above [context] nor mounted under [snackbarKey] (#613).
ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? showSnackBar(
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

  /// Technical text kept for the copy action when [text] is a friendly
  /// summary of it.
  String? detail,

  /// Blocking bars only: stays until closed by hand. Every other bar
  /// (errors included) auto-dismisses after `duration`, even with an action
  /// — Flutter would otherwise pin any bar that has an action (#470).
  bool persist = false,
}) {
  duration ??= const Duration(seconds: kSnackBarDuration);
  final theme = Theme.of(context);
  // The full, untruncated message. The SnackBar may clip long text on screen,
  // so we keep the complete string for logging and for the Copy action.
  final shownText = [
    ?text,
    ...?textSpans?.map((s) => s.toPlainText()),
  ].join();
  final fullText = detail == null || detail.isEmpty
      ? shownText
      : '$shownText\n$detail';

  if (isError) {
    if (error != null) {
      reportUserFacingError(error, stackTrace: stackTrace);
    }
    GetIt.I<Logger>().warning(fullText);
  }

  // No messenger above the context and the app-level one is not mounted
  // (early start-up, teardown, a detached overlay): drop the bar rather than
  // crash on a null state (#613).
  final scaffoldMessenger =
      ScaffoldMessenger.maybeOf(context) ?? snackbarKey.currentState;
  if (scaffoldMessenger == null) {
    if (GetIt.I.isRegistered<Logger>()) {
      GetIt.I<Logger>().warning(
        'showSnackBar: no ScaffoldMessenger: $fullText',
      );
    }
    return null;
  }
  scaffoldMessenger.clearSnackBars();

  // Errors get a Copy action so the (often cryptic) server message can be
  // pasted into a bug report. Only added when the caller didn't supply its own.
  final effectiveAction =
      action ??
      (isError && fullText.isNotEmpty
          ? SnackBarAction(
              label: L10n.of(context)?.copyErrorDetails ?? 'Copy',
              // The theme's action colour is for the dark inverse bar; on the
              // light error container it read as disabled (#426).
              textColor: theme.colorScheme.onErrorContainer,
              onPressed: () {
                unawaited(copyTextToClipboard(fullText));
              },
            )
          : null);

  // A primary action at the bottom of the body (Forward/Recipients
  // composer) is invisible to the Scaffold's bar layout: float the bar above
  // it so the action stays tappable (#406).
  final clearance = snackBarBottomClearance();
  final lifted = clearance > 0;
  final floating = isFloating || isError || lifted;

  return scaffoldMessenger.showSnackBar(
    SnackBar(
      action: effectiveAction,
      duration: duration,
      persist: persist,
      // Action and close icon coexist (M3); users can dismiss without using the action.
      showCloseIcon: true,
      closeIconColor: isError ? theme.colorScheme.onErrorContainer : null,
      // Errors float in the error container with an icon instead of a
      // full-bleed red bar (UI review): readable, and clearly separate from
      // the bottom navigation and CTAs it used to cover.
      margin: lifted
          ? kPaddingAll.copyWith(bottom: clearance + kSpacingSmall)
          : floating
          ? kPaddingAll
          : null,
      // Web: horizontal Dismissible + PointerPanZoom (Firefox trackpad) can hit-test
      // before the snack bar is laid out during route transitions (Sentry #7579576017).
      dismissDirection: kIsWeb
          ? DismissDirection.none
          : DismissDirection.horizontal,
      behavior: floating ? SnackBarBehavior.floating : null,
      shape: isError
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(TenturaRadii.cardDense),
            )
          : null,
      backgroundColor: isError
          ? theme.colorScheme.errorContainer
          : color ?? theme.snackBarTheme.backgroundColor,
      content: RichText(
        text: TextSpan(
          text: text,
          children: textSpans,
          style: isError
              ? theme.snackBarTheme.contentTextStyle?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
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
