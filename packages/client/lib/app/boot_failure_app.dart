import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/data/database/reopening_query_executor.dart';
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
    this.error,
    this.onReload = reloadWebApp,
    this.isWeb = kIsWeb,
    super.key,
  });

  static const reloadKey = TenturaEmptyState.actionKey;

  /// Why startup failed. Another tab holding the local database (#1123) gets
  /// its own explanation: close the other Tentura tabs.
  final Object? error;

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
        final lockHeld = error is LocalDatabaseLockHeldException;
        return Scaffold(
          body: SafeArea(
            child: TenturaEmptyState(
              icon: Icons.error_outline,
              title: lockHeld ? l10n.bootLockHeldTitle : l10n.bootFailureTitle,
              body: lockHeld
                  ? l10n.bootLockHeldBody
                  : isWeb
                  ? l10n.bootFailureBodyWeb
                  : l10n.bootFailureBodyNative,
              actionLabel: !isWeb
                  ? null
                  : lockHeld
                  ? l10n.bootLockHeldReload
                  : l10n.bootFailureReload,
              onAction: isWeb ? onReload : null,
            ),
          ),
        );
      },
    ),
  );
}
