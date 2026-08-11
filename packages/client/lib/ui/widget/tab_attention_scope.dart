import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/app/platform/tab_attention_indicator.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_tab_indicator.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/features/settings/ui/bloc/settings_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/model/tab_attention_display.dart';

/// Owns tab-attention pacing and drives the platform adapter directly.
class TabAttentionController {
  TabAttentionController({
    required TabAttentionIndicator indicator,
    AttentionCase? attention,
    SettingsCubit? settings,
  }) : _indicator = indicator,
       _attention = attention,
       _settings = settings,
       _unreadTotal = attention?.snapshot.summary.unreadTotal ?? 0,
       _isBackground = indicator.isBackground,
       _baseTitle = kAppTitle,
       _themeMode = settings?.state.themeMode ?? ThemeMode.system,
       _style = TenturaTabIndicator.resolve(
         _resolveBrightness(settings?.state.themeMode ?? ThemeMode.system),
       ) {
    _backgroundSub = _indicator.backgroundChanges.listen((isBackground) {
      _isBackground = isBackground;
      _scheduleRecompute();
    });

    final attentionCase = _attention;
    if (attentionCase != null) {
      _unreadSub = attentionCase.unreadSummary
          .map((summary) => summary.unreadTotal)
          .distinct()
          .listen((unreadTotal) {
            _unreadTotal = unreadTotal;
            _scheduleRecompute();
          });
    }

    final settingsCubit = _settings;
    if (settingsCubit != null) {
      _settingsSub = settingsCubit.stream.listen((state) {
        if (state.themeMode == _themeMode) return;
        _themeMode = state.themeMode;
        _onEffectiveBrightnessChanged();
      });
    }

    _scheduleRecompute();
  }

  static const _throttleDuration = Duration(milliseconds: 250);

  final TabAttentionIndicator _indicator;
  final AttentionCase? _attention;
  final SettingsCubit? _settings;

  StreamSubscription<bool>? _backgroundSub;
  StreamSubscription<int>? _unreadSub;
  StreamSubscription<SettingsState>? _settingsSub;
  Timer? _throttleTimer;

  var _unreadTotal = 0;
  var _isBackground = false;
  var _baseTitle = kAppTitle;
  var _themeMode = ThemeMode.system;
  late TenturaTabIndicatorStyle _style;
  var _disposed = false;

  var _throttleWindowOpen = false;
  TabAttentionDisplay? _pendingDisplay;
  (bool, String)? _pendingTitleKey;
  (bool, int)? _pendingBadgeKey;

  (bool, String)? _lastTitleKey;
  (bool, int)? _lastBadgeKey;

  static Brightness _resolveBrightness(ThemeMode themeMode) {
    if (themeMode == ThemeMode.system) {
      return WidgetsBinding.instance.platformDispatcher.platformBrightness;
    }
    return themeMode == ThemeMode.dark ? Brightness.dark : Brightness.light;
  }

  TabAttentionDisplay get _currentDisplay => resolveTabAttentionDisplay(
    unreadTotal: _unreadTotal,
    isBackground: _isBackground,
  );

  Brightness _effectiveBrightness() => _resolveBrightness(_themeMode);

  (bool, String) _titleKeyFor(TabAttentionDisplay display) =>
      (_isBackground, display.label);

  (bool, int) _badgeKeyFor(TabAttentionDisplay display) =>
      (_isBackground, display.count);

  void onPlatformBrightnessChanged() {
    if (_themeMode != ThemeMode.system) return;
    _onEffectiveBrightnessChanged();
  }

  void _onEffectiveBrightnessChanged() {
    final nextStyle = TenturaTabIndicator.resolve(_effectiveBrightness());
    if (identical(nextStyle, _style)) return;
    _style = nextStyle;
    if (_currentDisplay == tabAttentionNone) return;
    // Favicon only: title/badge keys are unchanged; never assign dispatcher.
    _indicator.apply(
      _currentDisplay,
      _style,
      baseTitle: _baseTitle,
      applyTitle: false,
      applyFavicon: true,
      applyBadge: false,
    );
  }

  /// Updates the localized base title used when tab attention is cleared.
  ///
  /// While attention is active, only the stored clear title changes — no
  /// direct-DOM apply (title must not mutate from the reporter while the
  /// indicator is showing). When the display is clear, apply synchronously.
  void setBaseTitle(String baseTitle) {
    if (_baseTitle == baseTitle) return;
    _baseTitle = baseTitle;
    if (_currentDisplay != tabAttentionNone) return;
    _cancelThrottle();
    _forceApply(tabAttentionNone);
  }

  void _scheduleRecompute({bool bypassThrottle = false}) {
    if (_disposed) return;
    final display = _currentDisplay;
    final titleKey = _titleKeyFor(display);
    final badgeKey = _badgeKeyFor(display);

    final titleChanged = titleKey != _lastTitleKey;
    final badgeChanged = badgeKey != _lastBadgeKey;
    if (!titleChanged && !badgeChanged) return;

    if (display == tabAttentionNone || bypassThrottle) {
      _cancelThrottle();
      _applyDisplay(
        display,
        titleKey: titleKey,
        badgeKey: badgeKey,
      );
      return;
    }

    if (!_throttleWindowOpen) {
      _throttleWindowOpen = true;
      _applyDisplay(
        display,
        titleKey: titleKey,
        badgeKey: badgeKey,
      );
      _throttleTimer = Timer(_throttleDuration, _onThrottleWindowEnd);
      return;
    }

    _pendingDisplay = display;
    _pendingTitleKey = titleKey;
    _pendingBadgeKey = badgeKey;
  }

  void _onThrottleWindowEnd() {
    _throttleTimer = null;
    _throttleWindowOpen = false;
    if (_disposed) return;

    final pending = _pendingDisplay;
    final pendingTitleKey = _pendingTitleKey;
    final pendingBadgeKey = _pendingBadgeKey;
    _pendingDisplay = null;
    _pendingTitleKey = null;
    _pendingBadgeKey = null;
    if (pending == null ||
        pendingTitleKey == null ||
        pendingBadgeKey == null) {
      return;
    }

    final titleChanged = pendingTitleKey != _lastTitleKey;
    final badgeChanged = pendingBadgeKey != _lastBadgeKey;
    if (!titleChanged && !badgeChanged) return;

    _applyDisplay(
      pending,
      titleKey: pendingTitleKey,
      badgeKey: pendingBadgeKey,
    );
  }

  void _cancelThrottle() {
    _throttleTimer?.cancel();
    _throttleTimer = null;
    _throttleWindowOpen = false;
    _pendingDisplay = null;
    _pendingTitleKey = null;
    _pendingBadgeKey = null;
  }

  void _applyDisplay(
    TabAttentionDisplay display, {
    required (bool, String) titleKey,
    required (bool, int) badgeKey,
  }) {
    if (_disposed) return;

    final titleChanged = titleKey != _lastTitleKey;
    final badgeChanged = badgeKey != _lastBadgeKey;
    if (!titleChanged && !badgeChanged) return;

    if (titleChanged) {
      _lastTitleKey = titleKey;
    }
    if (badgeChanged) {
      _lastBadgeKey = badgeKey;
    }
    _indicator.apply(
      display,
      _style,
      baseTitle: _baseTitle,
      applyTitle: titleChanged,
      applyFavicon: titleChanged,
      applyBadge: badgeChanged,
    );
  }

  void _forceApply(TabAttentionDisplay display) {
    if (_disposed) return;
    _lastTitleKey = _titleKeyFor(display);
    _lastBadgeKey = _badgeKeyFor(display);
    _indicator.apply(
      display,
      _style,
      baseTitle: _baseTitle,
      applyTitle: true,
      applyFavicon: true,
      applyBadge: true,
    );
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _cancelThrottle();
    _backgroundSub?.cancel();
    _unreadSub?.cancel();
    _settingsSub?.cancel();
    _indicator.apply(
      tabAttentionNone,
      _style,
      baseTitle: _baseTitle,
      applyTitle: true,
      applyFavicon: true,
      applyBadge: true,
    );
    _indicator.dispose();
  }
}

class TabAttentionScope extends StatefulWidget {
  const TabAttentionScope({
    required this.child,
    this.attention,
    this.indicator,
    this.settings,
    super.key,
  });

  final Widget child;
  final AttentionCase? attention;
  final TabAttentionIndicator? indicator;
  final SettingsCubit? settings;

  /// Access the root controller from the localized base-title reporter.
  static TabAttentionController? controllerOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_TabAttentionControllerInherited>()
      ?.controller;

  @override
  State<TabAttentionScope> createState() => _TabAttentionScopeState();
}

class _TabAttentionControllerInherited extends InheritedWidget {
  const _TabAttentionControllerInherited({
    required this.controller,
    required super.child,
  });

  final TabAttentionController controller;

  @override
  bool updateShouldNotify(_TabAttentionControllerInherited oldWidget) =>
      !identical(controller, oldWidget.controller);
}

class _TabAttentionScopeState extends State<TabAttentionScope>
    with WidgetsBindingObserver {
  late final TabAttentionController _controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = TabAttentionController(
      indicator: widget.indicator ?? TabAttentionIndicator(),
      attention: widget.attention ?? _resolveAttention(),
      settings: widget.settings ?? _resolveSettings(),
    );
  }

  AttentionCase? _resolveAttention() {
    if (!GetIt.I.isRegistered<AttentionCase>()) return null;
    return GetIt.I<AttentionCase>();
  }

  SettingsCubit? _resolveSettings() {
    if (!GetIt.I.isRegistered<SettingsCubit>()) return null;
    return GetIt.I<SettingsCubit>();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    _controller.onPlatformBrightnessChanged();
  }

  @override
  Widget build(BuildContext context) => _TabAttentionControllerInherited(
    controller: _controller,
    child: widget.child,
  );
}

/// Sits below [MaterialApp] localization and updates the controller's clear title.
class TabAttentionBaseTitleReporter extends StatefulWidget {
  const TabAttentionBaseTitleReporter({required this.child, super.key});

  final Widget child;

  @override
  State<TabAttentionBaseTitleReporter> createState() =>
      _TabAttentionBaseTitleReporterState();
}

class _TabAttentionBaseTitleReporterState
    extends State<TabAttentionBaseTitleReporter> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    TabAttentionScope.controllerOf(
      context,
    )?.setBaseTitle(L10n.of(context)?.appTitle ?? kAppTitle);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
