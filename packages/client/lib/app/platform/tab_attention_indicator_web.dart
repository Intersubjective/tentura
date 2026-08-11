import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_tab_indicator.dart';
import 'package:tentura/ui/model/tab_attention_display.dart';

const _faviconLinkId = 'tentura-tab-attention-favicon';
const _defaultStaticHref = 'favicon.png';

class TabAttentionIndicator {
  TabAttentionIndicator() {
    _initFaviconLink();
    _initBaseImage();
    _backgroundController = StreamController<bool>.broadcast(
      onListen: _emitBackground,
    );
    _visibilitySubscription = web.document.onVisibilityChange.listen((_) {
      _emitBackground();
    });
    _pageShowSubscription = web.EventStreamProviders.pageShowEvent
        .forTarget(web.window)
        .listen(_onPageShow);
  }

  late final StreamController<bool> _backgroundController;
  late final web.HTMLLinkElement _faviconLink;
  late final String _staticHref;

  StreamSubscription<web.Event>? _visibilitySubscription;
  StreamSubscription<web.Event>? _pageShowSubscription;

  web.HTMLImageElement? _baseImage;
  var _baseImageLoaded = false;
  String? _pendingFaviconLabel;
  TenturaTabIndicatorStyle? _pendingFaviconStyle;
  String? _lastFaviconLabel;

  TabAttentionDisplay? _lastDisplay;
  TenturaTabIndicatorStyle? _lastStyle;
  String? _lastBaseTitle;
  var _disposed = false;

  /// `true` while the tab/window is hidden. Never fires on native.
  Stream<bool> get backgroundChanges => _backgroundController.stream;

  bool get isBackground =>
      _qaForceBackground || web.document.visibilityState == 'hidden';

  /// Writes all web tab chrome synchronously. Never waits for a Flutter frame.
  /// [baseTitle] is the current localized title supplied while the app is visible.
  void apply(
    TabAttentionDisplay display,
    TenturaTabIndicatorStyle style, {
    required String baseTitle,
  }) {
    _lastDisplay = display;
    _lastStyle = style;
    _lastBaseTitle = baseTitle;

    final title = composeTabTitle(baseTitle: baseTitle, display: display);
    try {
      web.document.title = title;
    } catch (_) {
      // Title is the mandatory channel; swallow only unexpected DOM failures.
    }

    _applyFavicon(display, style);
    final badgeApplied = _applyBadge(display.count);
    _publishQaState(display, title, badgeApplied);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;

    final style = _lastStyle;
    final baseTitle = _lastBaseTitle;
    if (style != null && baseTitle != null) {
      apply(tabAttentionNone, style, baseTitle: baseTitle);
    }

    _visibilitySubscription?.cancel();
    _pageShowSubscription?.cancel();
    if (!_backgroundController.isClosed) {
      unawaited(_backgroundController.close());
    }
  }

  void _initFaviconLink() {
    final existing = web.document.getElementById(_faviconLinkId);
    if (existing case final web.HTMLLinkElement link) {
      _faviconLink = link;
      _staticHref =
          link.getAttribute('data-static-href') ?? _defaultStaticHref;
      return;
    }

    var pristine = _defaultStaticHref;
    final iconLinks = web.document.querySelectorAll('link[rel~="icon"]');
    for (var i = 0; i < iconLinks.length; i++) {
      final link = iconLinks.item(i);
      if (link case final web.HTMLLinkElement iconLink) {
        pristine = iconLink.getAttribute('href') ?? pristine;
        break;
      }
    }
    _staticHref = pristine;

    for (var i = iconLinks.length - 1; i >= 0; i--) {
      final node = iconLinks.item(i);
      if (node case final web.Element element) {
        element.remove();
      }
    }

    final managed = web.document.createElement('link') as web.HTMLLinkElement
      ..id = _faviconLinkId
      ..rel = 'icon'
      ..href = pristine;
    managed.dataset['staticHref'] = pristine;
    web.document.head?.appendChild(managed);
    _faviconLink = managed;
  }

  void _initBaseImage() {
    final image = web.HTMLImageElement();
    image.onLoad.listen((_) {
      _baseImageLoaded = true;
      final label = _pendingFaviconLabel;
      final style = _pendingFaviconStyle;
      if (label != null && style != null) {
        _paintFavicon(style);
        _pendingFaviconLabel = null;
        _pendingFaviconStyle = null;
      }
    });
    image.src = _staticHref;
    _baseImage = image;
  }

  void _applyFavicon(TabAttentionDisplay display, TenturaTabIndicatorStyle style) {
    try {
      if (display.label.isEmpty) {
        _lastFaviconLabel = null;
        _pendingFaviconLabel = null;
        _pendingFaviconStyle = null;
        _faviconLink.href = _staticHref;
        return;
      }

      if (display.label == _lastFaviconLabel) return;
      _lastFaviconLabel = display.label;

      if (!_baseImageLoaded) {
        _pendingFaviconLabel = display.label;
        _pendingFaviconStyle = style;
        return;
      }

      _paintFavicon(style);
    } catch (_) {
      // Degrade to title-only when favicon work fails.
    }
  }

  void _paintFavicon(TenturaTabIndicatorStyle style) {
    try {
      final canvas = web.HTMLCanvasElement();
      canvas.width = 32;
      canvas.height = 32;
      final ctx = canvas.getContext('2d') as web.CanvasRenderingContext2D?;
      if (ctx == null) return;

      ctx.imageSmoothingEnabled = false;
      final baseImage = _baseImage;
      if (_baseImageLoaded && baseImage != null) {
        ctx.drawImage(baseImage, 0, 0, 32, 32);
      }

      ctx.fillStyle = _colorToCss(style.halo).toJS;
      ctx.beginPath();
      ctx.arc(22, 10, 9, 0, math.pi * 2);
      ctx.fill();

      ctx.fillStyle = _colorToCss(style.dot).toJS;
      ctx.beginPath();
      ctx.arc(22, 10, 7, 0, math.pi * 2);
      ctx.fill();

      _faviconLink.href = canvas.toDataURL('image/png');
    } catch (_) {
      // SecurityError / unsupported canvas → title-only degradation.
    }
  }

  bool _applyBadge(int count) {
    if (!_isInstalledContext) return false;

    final navigator = web.window.navigator as JSObject;
    if (!navigator.has('setAppBadge')) return false;

    try {
      final promise = count > 0
          ? web.window.navigator.setAppBadge(count)
          : web.window.navigator.clearAppBadge();
      promise.toDart.catchError((Object _) => null);
      return true;
    } catch (_) {
      return false;
    }
  }

  bool get _isInstalledContext =>
      web.window.matchMedia('(display-mode: standalone)').matches ||
      web.window.matchMedia('(display-mode: window-controls-overlay)').matches;

  bool get _qaForceBackground {
    if (!kQaIntegrationTestMode) return false;
    final value = (web.window as JSObject).getProperty(
      '__tenturaForceTabBackground'.toJS,
    );
    if (value == null || !value.isA<JSBoolean>()) return false;
    return (value as JSBoolean).toDart;
  }

  void _publishQaState(
    TabAttentionDisplay display,
    String title,
    bool badgeApplied,
  ) {
    if (!kQaIntegrationTestMode) return;
    final state = <String, Object?>{
      'count': display.count,
      'label': display.label,
      'badgeApplied': badgeApplied,
      'title': title,
    };
    (web.window as JSObject).setProperty(
      '__tenturaTabAttention'.toJS,
      state.jsify(),
    );
  }

  void _emitBackground() {
    if (!_backgroundController.isClosed) {
      _backgroundController.add(isBackground);
    }
  }

  void _onPageShow(web.Event event) {
    if (event case final web.PageTransitionEvent pageShow when pageShow.persisted) {
      _emitBackground();
      final display = _lastDisplay;
      final style = _lastStyle;
      final baseTitle = _lastBaseTitle;
      if (display != null && style != null && baseTitle != null) {
        apply(display, style, baseTitle: baseTitle);
      }
    }
  }

  String _colorToCss(Color color) {
    final r = (color.r * 255.0).round().clamp(0, 255);
    final g = (color.g * 255.0).round().clamp(0, 255);
    final b = (color.b * 255.0).round().clamp(0, 255);
    return 'rgba($r, $g, $b, ${color.a})';
  }
}
