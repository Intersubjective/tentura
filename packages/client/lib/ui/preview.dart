import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/design_system/tentura_theme.dart';

export 'package:flutter/widget_previews.dart';
export 'package:flutter/widgets.dart';

// Consts

/// Widgets of shared layer
const commonWidgetsGroup = 'Shared Widgets';

/// Widget-preview theme for Flutter 3.47+ (`PreviewThemeData` is abstract).
final class TenturaPreviewTheme extends PreviewThemeData {
  const TenturaPreviewTheme();

  @override
  Widget apply(BuildContext context, Widget child) {
    final brightness =
        MediaQuery.maybePlatformBrightnessOf(context) ?? Brightness.light;
    return Theme(
      data: brightness == Brightness.dark
          ? TenturaTheme.dark()
          : TenturaTheme.light(),
      child: child,
    );
  }
}

/// Create Theme for Preview
PreviewThemeData previewThemeData() => const TenturaPreviewTheme();

// Preview data
const profileCaptainNemo = Profile(
  id: 'U3ea0a229ad85',
  displayName: 'Captain Nemo',
);
