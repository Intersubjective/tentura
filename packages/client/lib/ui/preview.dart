import 'package:flutter/widget_previews.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/design_system/tentura_theme.dart';

export 'package:flutter/widget_previews.dart';
export 'package:flutter/widgets.dart';

// Consts

/// Widgets of shared layer
const commonWidgetsGroup = 'Shared Widgets';

/// Create Theme for Preview
PreviewThemeData previewThemeData() => PreviewThemeData(
  materialLight: TenturaTheme.light(),
  materialDark: TenturaTheme.dark(),
);

// Preview data
const profileCaptainNemo = Profile(
  id: 'U3ea0a229ad85',
  title: 'Captain Nemo',
);
