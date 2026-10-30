// DEPRECATED scope: prefer `context.tt` (TenturaTokens) for new layout; do not add
// new `kPadding*` / spacing constants here — use design-system tokens instead.

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:intl/intl.dart';
import 'package:logging/logging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

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
  SnackBar build(double clearance, Duration shownFor) {
    final lifted = clearance > 0;
    final floating = isFloating || isError || lifted;
    return SnackBar(
      action: effectiveAction,
      duration: shownFor,
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
    );
  }

  return _LiftableSnackBar.show(
    messenger: scaffoldMessenger,
    build: build,
    duration: duration,
    persist: persist,
  );
}

/// The bar last shown through [showSnackBar] while it is up, so it can be
/// moved when a body-bottom action appears or changes height under it
/// (#605, from #406): a bar is placed once, when shown, so the "X shared a
/// post with you" bar shown while the post was loading covered its composer.
class _LiftableSnackBar {
  _LiftableSnackBar._({
    required this.messenger,
    required this.build,
    required this.clearance,
    required this.endsAt,
    required this.persist,
  });

  static _LiftableSnackBar? _current;

  static var _listening = false;

  final ScaffoldMessengerState messenger;

  final SnackBar Function(double clearance, Duration shownFor) build;

  final double clearance;

  final DateTime endsAt;

  final bool persist;

  static ScaffoldFeatureController<SnackBar, SnackBarClosedReason> show({
    required ScaffoldMessengerState messenger,
    required SnackBar Function(double clearance, Duration shownFor) build,
    required Duration duration,
    required bool persist,
    DateTime? endsAt,
  }) {
    if (!_listening) {
      _listening = true;
      snackBarClearanceChanges.addListener(_onClearanceChanged);
    }
    final clearance = snackBarBottomClearance();
    final bar = _LiftableSnackBar._(
      messenger: messenger,
      build: build,
      clearance: clearance,
      endsAt: endsAt ?? DateTime.now().add(duration),
      persist: persist,
    );
    final controller = messenger.showSnackBar(build(clearance, duration));
    _current = bar;
    unawaited(
      controller.closed.then((_) {
        if (identical(_current, bar)) {
          _current = null;
          _changedAt = null;
        }
      }),
    );
    return controller;
  }

  /// Frame time of the last height change that reached under the bar, while
  /// waiting for the height to settle; null when not waiting.
  static Duration? _changedAt;

  /// A composer grows line by line; wait for its height to settle rather
  /// than move the bar on every line (PR #819 review).
  static const _settleDelay = Duration(milliseconds: 300);

  /// Moving a bar removes it and shows a new one, which slides in and is
  /// announced again by screen readers: only move it when the action now
  /// reaches under it. A shrink, or a growth that still clears the bar (a
  /// lifted bar keeps a kSpacingSmall gap above the action it was lifted
  /// over), leaves it where it is.
  static bool _covered(_LiftableSnackBar bar) {
    final gap = bar.clearance > 0 ? kSpacingSmall : 0.0;
    return snackBarBottomClearance() > bar.clearance + gap;
  }

  static void _onClearanceChanged() {
    final bar = _current;
    if (bar == null || !bar.messenger.mounted || !_covered(bar)) {
      _changedAt = null;
      return;
    }
    final waiting = _changedAt != null;
    _changedAt = SchedulerBinding.instance.currentSystemFrameTimeStamp;
    // Frames, not a Timer: nothing is left pending when the screen goes.
    if (!waiting) _waitForSettledHeight();
  }

  static void _waitForSettledHeight() {
    SchedulerBinding.instance
      ..addPostFrameCallback((_) {
        final changedAt = _changedAt;
        if (changedAt == null) return;
        final now = SchedulerBinding.instance.currentSystemFrameTimeStamp;
        if (now - changedAt < _settleDelay) {
          _waitForSettledHeight();
          return;
        }
        _changedAt = null;
        _reliftIfCovered();
      })
      ..scheduleFrame();
  }

  static void _reliftIfCovered() {
    final bar = _current;
    if (bar == null || !bar.messenger.mounted || !_covered(bar)) return;
    // Shown again in its new place for the time it had left; a bar can't
    // be moved in place (its margin is fixed when it is built).
    final left = bar.endsAt.difference(DateTime.now());
    if (!bar.persist && left <= Duration.zero) return;
    _current = null;
    bar.messenger.removeCurrentSnackBar();
    show(
      messenger: bar.messenger,
      build: bar.build,
      duration: left < _minimumRelift ? _minimumRelift : left,
      persist: bar.persist,
      endsAt: bar.endsAt,
    );
  }

  static const _minimumRelift = Duration(seconds: 1);
}

Widget separatorBuilder(_, _) => const Divider(
  endIndent: kSpacingMedium,
  indent: kSpacingMedium,
);
