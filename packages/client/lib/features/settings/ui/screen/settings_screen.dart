import 'package:flutter/material.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/dialog/show_seed_dialog.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/linear_pi_active.dart';

import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/profile/ui/dialog/my_profile_delete.dart';

import '../bloc/settings_cubit.dart';
import '../widget/language_switch_button.dart';
import '../widget/theme_switch_button.dart';

@RoutePage()
class SettingsScreen extends StatelessWidget implements AutoRouteWrapper {
  const SettingsScreen({super.key});

  @override
  Widget wrappedRoute(BuildContext context) {
    final authCubit = GetIt.I<AuthCubit>();
    return BlocListener<AuthCubit, AuthState>(
      bloc: authCubit,
      listener: commonScreenBlocListener,
      child: this,
    );
  }

  Future<void> _confirmResetLocal(BuildContext context) async {
    final l10n = L10n.of(context)!;
    final cubit = GetIt.I<SettingsCubit>();
    final seedWarning = await cubit.hasSeedOnlyLocalAccounts();
    if (!context.mounted) return;
    final confirmed = await TenturaConfirmDialog.show(
      context: context,
      title: l10n.authRecoveryResetLocalTitle,
      content: seedWarning
          ? '${l10n.authRecoveryResetLocalBody}\n\n'
                '${l10n.authRecoveryResetSeedWarning}'
          : l10n.authRecoveryResetLocalBody,
      confirmLabel: l10n.authRecoveryResetLocalTitle,
      cancelLabel: l10n.buttonCancel,
    );
    if ((confirmed ?? false) && context.mounted) {
      await cubit.resetLocalAuthState();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cubit = GetIt.I<SettingsCubit>();
    final authCubit = GetIt.I<AuthCubit>();
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final visibleVersion = cubit.state.visibleVersion;
    return Scaffold(
      appBar: AppBar(
        leading: const AutoLeadingButton(),
        title: Text(l10n.labelSettings),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(LinearPiActive.height),
          child: BlocSelector<AuthCubit, AuthState, bool>(
            bloc: authCubit,
            selector: (state) => state.isLoading,
            builder: LinearPiActive.builder,
          ),
        ),
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
              _SettingsCommandList(
                l10n: l10n,
                authCubit: authCubit,
                settingsCubit: cubit,
                onConfirmResetLocal: () => _confirmResetLocal(context),
              ),
              if (visibleVersion != null && visibleVersion.isNotEmpty)
                Center(
                  child: TenturaMetaText(
                    visibleVersion,
                    maxLines: 2,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsCommandList extends StatelessWidget {
  const _SettingsCommandList({
    required this.l10n,
    required this.authCubit,
    required this.settingsCubit,
    required this.onConfirmResetLocal,
  });

  final L10n l10n;
  final AuthCubit authCubit;
  final SettingsCubit settingsCubit;
  final VoidCallback onConfirmResetLocal;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final scheme = Theme.of(context).colorScheme;
    return BlocSelector<AuthCubit, AuthState, bool>(
      bloc: authCubit,
      selector: (state) => state.isLoading,
      builder: (context, isLoading) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: tt.rowGap,
          children: [
            FutureBuilder<String?>(
              future: settingsCubit.tryGetCurrentAccountSeed(),
              builder: (context, snapshot) {
                final seed = snapshot.data;
                if (seed == null || seed.isEmpty) {
                  return const SizedBox.shrink();
                }
                return TenturaCommandButton(
                  label: l10n.showSeed,
                  icon: const Icon(Icons.remove_red_eye_outlined),
                  onPressed: () async {
                    if (context.mounted) {
                      await ShowSeedDialog.show(context, seed: seed);
                    }
                  },
                );
              },
            ),
            TenturaCommandButton(
              label: l10n.signInMethods,
              icon: const Icon(Icons.key_outlined),
              onPressed: () => context.router.push(CredentialsRoute()),
            ),
            TenturaCommandButton(
              label: l10n.notificationSettings,
              icon: const Icon(Icons.notifications_outlined),
              onPressed: () =>
                  context.router.push(const NotificationSettingsRoute()),
            ),
            if (!kIsWeb)
              TenturaCommandButton(
                label: l10n.showIntroAgain,
                icon: const Icon(Icons.reset_tv),
                onPressed: () => settingsCubit.setIntroEnabled(true),
              ),
            TenturaCommandButton(
              label: l10n.authRecoveryResetLocalTitle,
              icon: const Icon(Icons.delete_forever_outlined),
              onPressed: isLoading ? null : onConfirmResetLocal,
            ),
            TenturaCommandButton(
              label: l10n.settingsRequestProfileDeletion,
              icon: const Icon(Icons.person_off_outlined),
              onPressed: isLoading
                  ? null
                  : () => MyProfileDeleteDialog.show(context),
            ),
            FilledButton.icon(
              onPressed: isLoading ? null : settingsCubit.signOut,
              icon: const Icon(Icons.logout),
              label: Text(l10n.logout),
              style: FilledButton.styleFrom(
                minimumSize: Size.fromHeight(tt.buttonHeight),
                backgroundColor: scheme.error,
                foregroundColor: scheme.onError,
              ),
            ),
          ],
        );
      },
    );
  }
}
