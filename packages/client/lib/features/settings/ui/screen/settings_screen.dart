import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/dialog/show_seed_dialog.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import '../bloc/settings_cubit.dart';
import '../widget/language_switch_button.dart';
import '../widget/theme_switch_button.dart';

@RoutePage()
class SettingsScreen extends StatelessWidget implements AutoRouteWrapper {
  const SettingsScreen({super.key});

  @override
  Widget wrappedRoute(BuildContext context) => this;

  Future<void> _confirmResetLocal(BuildContext context, L10n l10n) async {
    final cubit = GetIt.I<SettingsCubit>();
    final seedWarning = await cubit.hasSeedOnlyLocalAccounts();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.authRecoveryResetLocalTitle),
        content: Text(
          seedWarning
              ? '${l10n.authRecoveryResetLocalBody}\n\n'
                    '${l10n.authRecoveryResetSeedWarning}'
              : l10n.authRecoveryResetLocalBody,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.buttonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.authRecoveryResetLocalTitle),
          ),
        ],
      ),
    );
    if ((confirmed ?? false) && context.mounted) {
      await cubit.resetLocalAuthState();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cubit = GetIt.I<SettingsCubit>();
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final scheme = Theme.of(context).colorScheme;
    final visibleVersion = cubit.state.visibleVersion;
    final actionButtonStyle = OutlinedButton.styleFrom(
      minimumSize: Size.fromHeight(tt.buttonHeight),
    );
    return Scaffold(
      appBar: AppBar(
        leading: const AutoLeadingButton(),
        title: Text(l10n.labelSettings),
        actions: visibleVersion != null && visibleVersion.isNotEmpty
            ? [
                Padding(
                  padding: EdgeInsets.only(right: tt.screenHPadding),
                  child: Center(
                    child: Text(
                      visibleVersion,
                      style: TenturaText.bodySmall(scheme.onSurfaceVariant),
                    ),
                  ),
                ),
              ]
            : null,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(tt.screenHPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: tt.sectionGap,
            children: [
              const LanguageSwitchButton(),
              const ThemeSwitchButton(),

              // Seed (device-key accounts only; OAuth/session accounts have no local seed)
              FutureBuilder<String?>(
                future: cubit.tryGetCurrentAccountSeed(),
                builder: (context, snapshot) {
                  final seed = snapshot.data;
                  if (seed == null || seed.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return OutlinedButton.icon(
                    style: actionButtonStyle,
                    icon: const Icon(Icons.remove_red_eye_outlined),
                    label: Text(l10n.showSeed),
                    onPressed: () async {
                      if (context.mounted) {
                        await ShowSeedDialog.show(context, seed: seed);
                      }
                    },
                  );
                },
              ),

              // Sign-in methods
              OutlinedButton.icon(
                style: actionButtonStyle,
                icon: const Icon(Icons.key_outlined),
                label: Text(l10n.signInMethods),
                onPressed: () => context.router.push(CredentialsRoute()),
              ),

              // Intro — native only: on web onboarding lives on the static
              // landing and the router never enters IntroRoute (intro guards
              // are no-ops on web), so this replay button would do nothing.
              if (!kIsWeb)
                OutlinedButton.icon(
                  style: actionButtonStyle,
                  icon: const Icon(Icons.reset_tv),
                  label: Text(l10n.showIntroAgain),
                  onPressed: () => cubit.setIntroEnabled(true),
                ),

              OutlinedButton.icon(
                style: actionButtonStyle,
                onPressed: () => _confirmResetLocal(context, l10n),
                icon: const Icon(Icons.delete_forever_outlined),
                label: Text(l10n.authRecoveryResetLocalTitle),
              ),

              FilledButton.icon(
                onPressed: cubit.signOut,
                icon: const Icon(Icons.logout),
                label: Text(l10n.logout),
                style: FilledButton.styleFrom(
                  minimumSize: Size.fromHeight(tt.buttonHeight),
                  backgroundColor: scheme.error,
                  foregroundColor: scheme.onError,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
