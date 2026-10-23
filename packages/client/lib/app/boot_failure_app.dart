import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/design_system/components/tentura_empty_state.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/app_reload.dart';

/// Shown instead of the app when startup failed (e.g. the local database
/// could not be opened, #674), so the user never waits on an endless splash.
///
/// Startup failed, so nothing from DI is available: no saved theme or locale.
/// The system's are used.
class BootFailureApp extends StatelessWidget {
  const BootFailureApp({
    this.onReload = reloadWebApp,
    this.isWeb = kIsWeb,
    super.key,
  });

  static const reloadKey = TenturaEmptyState.actionKey;

  /// Reloads the page; only offered on the web.
  final VoidCallback onReload;

  final bool isWeb;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: kAppTitle,
    debugShowCheckedModeBanner: false,
    theme: TenturaTheme.light(),
    darkTheme: TenturaTheme.dark(),
    supportedLocales: L10n.supportedLocales,
    localizationsDelegates: L10n.localizationsDelegates,
    home: Builder(
      builder: (context) {
        final l10n = L10n.of(context)!;
        return Scaffold(
          body: SafeArea(
            child: TenturaEmptyState(
              icon: Icons.error_outline,
              title: l10n.bootFailureTitle,
              body: isWeb ? l10n.bootFailureBodyWeb : l10n.bootFailureBodyNative,
              actionLabel: isWeb ? l10n.bootFailureReload : null,
              onAction: isWeb ? onReload : null,
            ),
          ),
        );
      },
    ),
  );
}
