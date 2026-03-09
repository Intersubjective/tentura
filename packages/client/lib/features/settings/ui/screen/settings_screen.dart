import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/ui/dialog/show_seed_dialog.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import '../bloc/settings_cubit.dart';
import '../widget/theme_switch_button.dart';

@RoutePage()
class SettingsScreen extends StatelessWidget implements AutoRouteWrapper {
  const SettingsScreen({super.key});

  @override
  Widget wrappedRoute(BuildContext context) =>
      BlocListener<SettingsCubit, SettingsState>(
        listener: commonScreenBlocListener,
        bloc: GetIt.I<SettingsCubit>(),
        child: this,
      );

  @override
  Widget build(BuildContext context) {
    final cubit = GetIt.I<SettingsCubit>();
    final l10n = L10n.of(context)!;
    final visibleVersion = cubit.state.visibleVersion;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.labelSettings),
        actions: visibleVersion != null && visibleVersion.isNotEmpty
            ? [
                Padding(
                  padding: const EdgeInsets.only(
                    right: kSpacingMedium,
                  ),
                  child: Text(visibleVersion),
                ),
              ]
            : null,
      ),
      body: Padding(
        padding: kPaddingAll,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: kSpacingMedium,
          children: [
            const ThemeSwitchButton(),

            // Seed
            OutlinedButton.icon(
              icon: const Icon(Icons.remove_red_eye_outlined),
              label: Text(l10n.showSeed),
              onPressed: () async {
                final seed = await cubit.getCurrentAccountSeed();
                if (context.mounted) {
                  await ShowSeedDialog.show(context, seed: seed);
                }
              },
            ),

            // Intro
            OutlinedButton.icon(
              icon: const Icon(Icons.reset_tv),
              label: Text(l10n.showIntroAgain),
              onPressed: () => cubit.setIntroEnabled(true),
            ),

            //Logout
            FilledButton.icon(
              onPressed: cubit.signOut,
              icon: const Icon(Icons.people),
              label: Text(l10n.logout),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor:  Theme.of(context).colorScheme.onError,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
