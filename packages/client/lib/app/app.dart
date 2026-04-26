import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/ui/bloc/app_update_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/app_reload.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/design_system/tentura_responsive_scope.dart';
import 'package:tentura/design_system/tentura_theme.dart';

import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/features/settings/ui/bloc/settings_cubit.dart';

import 'di/di.dart';
import 'di/globals.dart';
import 'platform/lifecycle_handler.dart';
import 'router/root_router.dart';

class App extends StatelessWidget {
  static Future<void> runner() async {
    FlutterNativeSplash.preserve(
      widgetsBinding: WidgetsFlutterBinding.ensureInitialized(),
    );
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    await configureDependencies();
    FlutterNativeSplash.remove();
    // Web: defer ensureSemantics() until after layout is stable. A single post-frame
    // tick can still race deep-link / first-frame pointer delivery; two ticks avoids
    // hit-testing the root Semantics node before constraints exist.
    if (kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          SemanticsBinding.instance.ensureSemantics();
        });
      });
    }
    runApp(
      const Globals(
        child: LifecycleHandler(
          child: App(),
        ),
      ),
    );
  }

  const App({super.key});

  @override
  Widget build(
    BuildContext context,
  ) => BlocSelector<SettingsCubit, SettingsState, ThemeMode>(
    bloc: GetIt.I<SettingsCubit>(),
    selector: (state) => state.themeMode,
    builder: (_, themeMode) {
      final router = GetIt.I<RootRouter>();
      return MaterialApp.router(
        title: kAppTitle,
        themeMode: themeMode,
        scaffoldMessengerKey: snackbarKey,
        debugShowCheckedModeBanner: false,
        theme: TenturaTheme.light(),
        darkTheme: TenturaTheme.dark(),
        routerConfig: router.config(
          deepLinkBuilder: router.deepLinkBuilder,
          deepLinkTransformer: router.deepLinkTransformer,
          reevaluateListenable: router.reevaluateListenable,
          // One observer instance per Navigator. Nested AutoRouter inherits
          // observers from ancestors; GetIt singleton caused observer.navigator
          // assertion failures on nested stacks (e.g. web).
          navigatorObservers: () => [
            SentryNavigatorObserver(),
            ClearSnackBarsOnPushObserver(),
          ],
        ),
        supportedLocales: L10n.supportedLocales,
        localizationsDelegates: L10n.localizationsDelegates,
        onGenerateTitle: (context) => L10n.of(context)?.appTitle ?? kAppTitle,
        builder: (context, child) {
          if (child == null) {
            return const SizedBox();
          }
          return MultiBlocProvider(
            providers: [
              BlocProvider.value(
                value: GetIt.I<ScreenCubit>(),
              ),
              BlocProvider.value(
                value: GetIt.I<SettingsCubit>(),
              ),
              BlocProvider.value(
                value: GetIt.I<AuthCubit>(),
              ),
              BlocProvider.value(
                value: GetIt.I<ProfileCubit>(),
              ),
              BlocProvider.value(
                value: GetIt.I<AppUpdateCubit>(),
              ),
            ],
            child: MultiBlocListener(
              listeners: [
                BlocListener<AppUpdateCubit, AppUpdateState>(
                  listenWhen: (previous, current) =>
                      previous.updateAvailable != current.updateAvailable ||
                      previous.dismissed != current.dismissed,
                  listener: (context, state) {
                    final messenger = ScaffoldMessenger.maybeOf(context);
                    if (messenger == null) {
                      return;
                    }
                    if (!state.updateAvailable || state.dismissed) {
                      messenger.clearMaterialBanners();
                      return;
                    }
                    messenger
                      ..clearMaterialBanners()
                      ..showMaterialBanner(
                        MaterialBanner(
                          content: const Text(
                            kIsWeb
                                ? 'A new version is available. '
                                      'Refresh the page to update.'
                                : 'A new version is available. '
                                      'Please update the app.',
                          ),
                          actions: [
                            if (kIsWeb)
                              const TextButton(
                                onPressed: reloadWebApp,
                                child: Text('Refresh'),
                              ),
                            TextButton(
                              onPressed: () =>
                                  context.read<AppUpdateCubit>().dismiss(),
                              child: const Text('Dismiss'),
                            ),
                          ],
                        ),
                      );
                  },
                ),
                BlocListener<ScreenCubit, ScreenState>(
                  listener: (context, state) => commonScreenBlocListener(
                    context,
                    state,
                    listenNavigatingState: false,
                  ),
                ),
                const BlocListener<SettingsCubit, SettingsState>(
                  listener: commonScreenBlocListener,
                ),
                const BlocListener<AuthCubit, AuthState>(
                  listener: commonScreenBlocListener,
                ),
              ],
              child: TenturaResponsiveScope(child: child),
            ),
          );
        },
      );
    },
  );
}
