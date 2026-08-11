import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'tentura_theme.dart';

/// Colors for the browser-tab favicon dot. Resolved outside the widget tree
/// (the indicator lives above MaterialApp), so it takes an explicit Brightness.
@immutable
final class TenturaTabIndicatorStyle {
  const TenturaTabIndicatorStyle({required this.dot, required this.halo});

  final Color dot;
  final Color halo;
}

abstract final class TenturaTabIndicator {
  /// Built at most once per brightness: [TenturaTheme.light]/[TenturaTheme.dark]
  /// construct a full [ThemeData] including [ColorScheme.fromSeed], which is
  /// far too expensive to call per repaint.
  static final _cache = <Brightness, TenturaTabIndicatorStyle>{};

  static TenturaTabIndicatorStyle resolve(Brightness brightness) =>
      _cache.putIfAbsent(brightness, () {
        final scheme = (brightness == Brightness.dark
                ? TenturaTheme.dark()
                : TenturaTheme.light())
            .colorScheme;
        return TenturaTabIndicatorStyle(dot: scheme.error, halo: scheme.surface);
      });
}
